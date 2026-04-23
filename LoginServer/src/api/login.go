// Package api – Lógica de autenticação e resposta de login
// Projeto MCR - Login Server
package api

import (
	"context"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
	_ "github.com/go-sql-driver/mysql"
	"github.com/opentibiabr/login-server/src/api/models"
	"github.com/opentibiabr/login-server/src/grpc/login_proto_messages"
)

// login processa a requisição de autenticação.
func (_api *Api) login(c *gin.Context) {
	log.Println(">>> [DEBUG] Requisição de login recebida")

	var payload models.RequestPayload
	if err := c.ShouldBindJSON(&payload); err != nil {
		log.Printf(">>> [DEBUG] Erro ao fazer bind JSON: %v\n", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	log.Printf(">>> [DEBUG] Payload: email=%s, type=%s\n", payload.Email, payload.Type)

	if payload.Type != "login" {
		log.Println(">>> [DEBUG] Tipo de requisição não é 'login'")
		c.JSON(http.StatusNotImplemented, gin.H{"status": "não implementado"})
		return
	}

	// Verifica conexão gRPC
	if _api.GrpcConnection == nil {
		log.Println(">>> [ERRO] Conexão gRPC é nil")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Serviço de autenticação indisponível"})
		return
	}
	log.Println(">>> [DEBUG] Conexão gRPC OK")

	grpcClient := login_proto_messages.NewLoginServiceClient(_api.GrpcConnection)
	log.Println(">>> [DEBUG] Cliente gRPC criado")

	// O campo 'email' da requisição já contém o nome do herói (que também é o valor do campo 'email' na tabela accounts).
	// Nenhuma conversão é necessária.
	loginIdentifier := payload.Email

	// Chamada gRPC
	log.Printf(">>> [DEBUG] Chamando gRPC Login com identificador=%s\n", loginIdentifier)
	res, err := grpcClient.Login(
		context.Background(),
		&login_proto_messages.LoginRequest{Email: loginIdentifier, Password: payload.Password},
	)

	if err != nil {
		log.Printf(">>> [ERRO] Falha na chamada gRPC: %v\n", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Falha na comunicação com o servidor de jogo"})
		return
	}
	log.Println(">>> [DEBUG] Chamada gRPC concluída sem erro")

	if res == nil {
		log.Println(">>> [ERRO] Resposta gRPC é nil")
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Resposta inválida do servidor de jogo"})
		return
	}
	log.Println(">>> [DEBUG] Resposta gRPC não é nil")

	// Verifica erro retornado pelo Canary
	if res.GetError() != nil {
		log.Printf(">>> [DEBUG] Canary retornou erro: code=%d, msg=%s\n",
			res.GetError().Code, res.GetError().Message)
		c.JSON(http.StatusOK, buildErrorPayloadFromMessage(res))
		return
	}
	log.Println(">>> [DEBUG] Login autenticado com sucesso pelo Canary")

	// Constrói resposta de sucesso
	payloadResponse := buildPayloadFromMessage(res)
	log.Printf(">>> [DEBUG] Payload de resposta: sessão=%s, personagens=%d\n",
		payloadResponse.Session.SessionKey, len(payloadResponse.PlayData.Characters))

	c.JSON(http.StatusOK, payloadResponse)
	log.Println(">>> [DEBUG] Resposta JSON enviada")
}

// buildPayloadFromMessage com proteção nil
func buildPayloadFromMessage(msg *login_proto_messages.LoginResponse) models.ResponsePayload {
	playData := msg.GetPlayData()

	var characters []models.CharacterPayload
	if playData != nil {
		characters = models.LoadCharactersFromMessage(playData.Characters)
	}
	if characters == nil {
		characters = []models.CharacterPayload{}
	}

	return models.ResponsePayload{
		PlayData: models.PlayData{
			Worlds:     models.LoadWorldsFromMessage(playData.GetWorlds()),
			Characters: characters,
		},
		Session: models.LoadSessionFromMessage(msg.GetSession()),
	}
}

func buildErrorPayloadFromMessage(msg *login_proto_messages.LoginResponse) models.LoginErrorPayload {
	err := msg.GetError()
	if err == nil {
		return models.LoginErrorPayload{ErrorCode: 0, ErrorMessage: "Erro desconhecido"}
	}
	return models.LoginErrorPayload{
		ErrorCode:    int(err.Code),
		ErrorMessage: err.Message,
	}
}