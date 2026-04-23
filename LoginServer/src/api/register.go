// src/api/register.go
// Projeto MCR - Endpoint de criação de conta (SHA1)
// Retorna apenas strings sem acentuação para evitar problemas de encoding no cliente.
package api

import (
	"crypto/sha1"
	"encoding/hex"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type RegisterRequest struct {
	AccountName     string `json:"account_name" binding:"required"`
	Password        string `json:"password" binding:"required"`
	ConfirmPassword string `json:"confirm_password" binding:"required"`
}

func (_api *Api) register(c *gin.Context) {
	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"success":    false,
			"error_code": "invalid_request",
			"message":    "Invalid data. Check the fields.",
		})
		return
	}

	if len(req.AccountName) < 3 || len(req.AccountName) > 32 {
		c.JSON(http.StatusBadRequest, gin.H{
			"success":    false,
			"error_code": "invalid_account_name_length",
			"message":    "Account name must be between 3 and 32 characters.",
		})
		return
	}

	if len(req.Password) < 3 {
		c.JSON(http.StatusBadRequest, gin.H{
			"success":    false,
			"error_code": "password_too_short",
			"message":    "Password must be at least 3 characters.",
		})
		return
	}

	if req.Password != req.ConfirmPassword {
		c.JSON(http.StatusBadRequest, gin.H{
			"success":    false,
			"error_code": "passwords_do_not_match",
			"message":    "Passwords do not match.",
		})
		return
	}

	var exists int
	err := _api.DB.QueryRow("SELECT 1 FROM accounts WHERE name = ?", req.AccountName).Scan(&exists)
	if err == nil {
		c.JSON(http.StatusConflict, gin.H{
			"success":    false,
			"error_code": "account_name_taken",
			"message":    "Account name already in use.",
		})
		return
	}

	hash := sha1.Sum([]byte(req.Password))
	hashedPassword := hex.EncodeToString(hash[:])
	creationTime := time.Now().Unix()

	_, err = _api.DB.Exec(`
		INSERT INTO accounts (name, password, email, creation, type, premdays, lastday, coins, coins_transferable, tournament_coins)
		VALUES (?, ?, ?, ?, 1, 0, 0, 0, 0, 0)`,
		req.AccountName, hashedPassword, req.AccountName, creationTime)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success":    false,
			"error_code": "database_error",
			"message":    "Error creating account. Please try again later.",
		})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"success":    true,
		"error_code": "",
		"message":    "Account created successfully! You can now log in.",
	})
}