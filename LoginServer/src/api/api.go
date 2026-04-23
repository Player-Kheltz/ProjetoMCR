// Package api contém as rotas HTTP e a lógica de inicialização do servidor web.
// Projeto MCR - Login Server
// Idioma: Português do Brasil (pt‑BR)
package api

import (
	"database/sql"
	"errors"
	"net/http"
	"sync"

	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"github.com/opentibiabr/login-server/src/api/limiter"
	"github.com/opentibiabr/login-server/src/configs"
	"github.com/opentibiabr/login-server/src/database"
	"github.com/opentibiabr/login-server/src/logger"
	"github.com/opentibiabr/login-server/src/server"
	"google.golang.org/grpc"
)

type Api struct {
	Router         *gin.Engine
	DB             *sql.DB
	GrpcConnection *grpc.ClientConn
	server.ServerInterface
}

// Initialize configura e retorna uma instância da API com todas as dependências.
func Initialize(gConfigs configs.GlobalConfigs) *Api {
	var _api Api
	var err error

	_api.DB = database.PullConnection(gConfigs)

	ipLimiter := &limiter.IPRateLimiter{
		Visitors: make(map[string]*limiter.Visitor),
		Mu:       &sync.RWMutex{},
	}
	ipLimiter.Init()

	gin.SetMode(gin.ReleaseMode)

	_api.Router = gin.New()
	_api.Router.Use(logger.LogRequest())
	_api.Router.Use(gin.Recovery())
	_api.Router.Use(ipLimiter.Limit())

	_api.initializeRoutes()

	// Conexão com o servidor gRPC (usado internamente para comunicação com o Canary)
	_api.GrpcConnection, err = grpc.Dial(gConfigs.LoginServerConfigs.Grpc.Format(), grpc.WithInsecure())
	if err != nil {
		logger.Error(errors.New("não foi possível iniciar o proxy reverso gRPC"))
	}

	return &_api
}

// Run inicia o servidor HTTP e aguarda conexões.
func (_api *Api) Run(gConfigs configs.GlobalConfigs) error {
	err := http.ListenAndServe(gConfigs.LoginServerConfigs.Http.Format(), _api.Router)

	// Libera a conexão gRPC ao encerrar
	if _api.GrpcConnection != nil {
		closeErr := _api.GrpcConnection.Close()
		if closeErr != nil {
			logger.Error(closeErr)
		}
	}

	return err
}

// GetName retorna o nome do serviço.
func (_api *Api) GetName() string {
	return "api"
}

// initializeRoutes registra as rotas da API.
func (_api *Api) initializeRoutes() {
	_api.Router.POST("/login", _api.login)
	_api.Router.POST("/login.php", _api.login) // Compatibilidade com clientes antigos

	// Nova rota para criação de conta integrada ao OTClient (Projeto MCR)
	_api.Router.POST("/register", _api.register)
}
