package main

import (
	"fmt"
	"log"
	"os"
	"runtime/debug"
	"sync"
	"time"

	"github.com/opentibiabr/login-server/src/api"
	"github.com/opentibiabr/login-server/src/configs"
	grpc_login_server "github.com/opentibiabr/login-server/src/grpc"
	"github.com/opentibiabr/login-server/src/logger"
	"github.com/opentibiabr/login-server/src/server"
)

var numberOfServers = 2
var initDelay = 200

func main() {
	// --- INÍCIO DO ESCUDO ANTI-PÂNICO ---
	// Configura um arquivo para capturar qualquer erro que travaria o servidor.
	f, err := os.OpenFile("panic.log", os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err == nil {
		// Se conseguiu abrir o arquivo, define ele como saída do log padrão.
		log.SetOutput(f)
	} else {
		// Se falhar, ao menos tenta escrever no console.
		log.SetOutput(os.Stderr)
	}

	// Este 'defer' é o nosso segurança. Se o programa entrar em pânico em qualquer
	// lugar, ele vai capturar, anotar no log e depois encerrar com educação.
	defer func() {
		if r := recover(); r != nil {
			// Monta a mensagem de erro com a stack trace (rastro do erro).
			errMsg := fmt.Sprintf("!!! PANICO CAPTURADO !!!\nErro: %v\nStack Trace:\n%s\n", r, debug.Stack())
			log.Println(errMsg)

			// Tenta também enviar para o logger oficial do Login Server, se ele já foi inicializado.
			logger.Error(fmt.Errorf("%v", r))

			// Fecha o arquivo de log com carinho.
			if f != nil {
				f.Close()
			}
		}
	}()
	// --- FIM DO ESCUDO ANTI-PÂNICO ---

	logger.Init(configs.GetLogLevel())
	logger.Info("Bem-vindo ao OTBR Login Server (Projeto MCR)")
	logger.Info("Carregando configurações...")

	var wg sync.WaitGroup
	wg.Add(numberOfServers)

	err = configs.Init()
	if err != nil {
		logger.Debug("Falha ao carregar '.env' em ambiente de desenvolvimento, seguindo com padrões.")
	}

	gConfigs := configs.GetGlobalConfigs()

	go startServer(&wg, gConfigs, grpc_login_server.Initialize(gConfigs))
	go startServer(&wg, gConfigs, api.Initialize(gConfigs))

	time.Sleep(time.Duration(initDelay) * time.Millisecond)
	gConfigs.Display()

	// Aguarda até que o WaitGroup seja concluído
	wg.Wait()
	logger.Info("Até logo...")
}

func startServer(
	wg *sync.WaitGroup,
	gConfigs configs.GlobalConfigs,
	server server.ServerInterface,
) {
	logger.Info(fmt.Sprintf("Iniciando servidor %s...", server.GetName()))
	logger.Error(server.Run(gConfigs))
	wg.Done()
	logger.Warn(fmt.Sprintf("Servidor %s foi encerrado...", server.GetName()))
}
