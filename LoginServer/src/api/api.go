package api

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"sync"
	"time"

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

func Initialize(gConfigs configs.GlobalConfigs) *Api {
	var _api Api
	var err error

	_api.DB = database.PullConnection(gConfigs)

	// Inicia limpeza periódica de contas guest expiradas (a cada 5 min)
	go func(db *sql.DB) {
		for {
			time.Sleep(5 * time.Minute)
			// Remove Almas de contas guest com mais de 30 min
			_, err := db.Exec(`
				DELETE FROM players
				WHERE name = 'Alma'
				AND account_id IN (
					SELECT id FROM accounts
					WHERE name LIKE 'guest_%'
					AND created_at > 0
					AND created_at < UNIX_TIMESTAMP() - 1800
				)
			`)
			if err != nil {
				logger.Error(fmt.Errorf("Limpeza de Almas guest: %v", err))
			}
			// Remove contas guest que ficaram sem personagens
			_, err = db.Exec(`
				DELETE FROM accounts
				WHERE name LIKE 'guest_%'
				AND created_at > 0
				AND created_at < UNIX_TIMESTAMP() - 1800
				AND id NOT IN (SELECT DISTINCT account_id FROM players)
			`)
			if err != nil {
				logger.Error(fmt.Errorf("Limpeza de contas guest: %v", err))
			}
		}
	}(_api.DB)

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

	_api.GrpcConnection, err = grpc.Dial(gConfigs.LoginServerConfigs.Grpc.Format(), grpc.WithInsecure())
	if err != nil {
		logger.Error(errors.New("não foi possível iniciar o proxy reverso gRPC"))
	}

	return &_api
}

func (_api *Api) Run(gConfigs configs.GlobalConfigs) error {
	err := http.ListenAndServe(gConfigs.LoginServerConfigs.Http.Format(), _api.Router)

	if _api.GrpcConnection != nil {
		closeErr := _api.GrpcConnection.Close()
		if closeErr != nil {
			logger.Error(closeErr)
		}
	}

	return err
}

func (_api *Api) GetName() string {
	return "api"
}

func (_api *Api) initializeRoutes() {
	_api.Router.POST("/login", _api.login)
	_api.Router.POST("/login.php", _api.login)
	_api.Router.POST("/register", _api.register)
	_api.Router.GET("/guest_login", _api.GuestLogin) // Nova rota MCR
}

// GuestLogin é o endpoint que gera conta temporária + Alma.
func (_api *Api) GuestLogin(c *gin.Context) {
	GuestLoginHandler(_api.DB)(c)
}