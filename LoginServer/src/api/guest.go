package api

import (
	"crypto/rand"
	"crypto/sha1"
	"database/sql"
	"encoding/hex"
	"fmt"
	"math/big"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/opentibiabr/login-server/src/logger"
)

func generateRandomString(length int) string {
	const charset = "abcdefghijklmnopqrstuvwxyz0123456789"
	result := make([]byte, length)
	for i := range result {
		idx, _ := rand.Int(rand.Reader, big.NewInt(int64(len(charset))))
		result[i] = charset[idx.Int64()]
	}
	return string(result)
}

func hashPassword(password string) string {
	h := sha1.New()
	h.Write([]byte(password))
	return hex.EncodeToString(h.Sum(nil))
}

func GuestLoginHandler(db *sql.DB) gin.HandlerFunc {
	return func(c *gin.Context) {
		accountName := "guest_" + generateRandomString(8)
		password := generateRandomString(12)
		hashedPassword := hashPassword(password)
		characterName := "Guest_" + generateRandomString(8)

		now := int(time.Now().Unix())

		// Insere conta com email = accountName (Canary autentica por email)
		_, err := db.Exec(
			"INSERT INTO accounts (name, password, email, created_at) VALUES (?, ?, ?, ?)",
			accountName, hashedPassword, accountName, now,
		)
		if err != nil {
			logger.Error(fmt.Errorf("Erro ao criar conta guest: %v", err))
			c.JSON(http.StatusInternalServerError, gin.H{
				"status":     "error",
				"error_code": "guest_creation_failed",
			})
			return
		}

		var accountID int
		err = db.QueryRow("SELECT id FROM accounts WHERE name = ?", accountName).Scan(&accountID)
		if err != nil {
			logger.Error(fmt.Errorf("Erro ao obter ID da conta guest: %v", err))
			c.JSON(http.StatusInternalServerError, gin.H{
				"status":     "error",
				"error_code": "guest_creation_failed",
			})
			return
		}

		_, err = db.Exec(
			`INSERT INTO players (
				name, account_id, level, vocation, sex,
				posx, posy, posz, town_id,
				health, healthmax, mana, manamax,
				looktype, lookhead, lookbody, looklegs, lookfeet, lookaddons,
				cap, lastlogin, lastip
			) VALUES (
				?, ?, 1, 0, 0,
				666, 666, 15, 1,
				100, 100, 0, 0,
				128, 0, 0, 0, 0, 0,
				400, 0, 0
			)`,
			characterName, accountID,
		)
		if err != nil {
			logger.Error(fmt.Errorf("Erro ao criar personagem convidado: %v", err))
			db.Exec("DELETE FROM accounts WHERE id = ?", accountID)
			c.JSON(http.StatusInternalServerError, gin.H{
				"status":     "error",
				"error_code": "alma_creation_failed",
			})
			return
		}

		c.JSON(http.StatusOK, gin.H{
			"status":    "success",
			"account":   accountName,
			"password":  password,
			"character": characterName,
		})
	}
}