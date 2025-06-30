package main

import (
	"fmt"
	"net/http"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
)

func main() {
	// Проверяем аргументы командной строки для health check
	if len(os.Args) > 1 && os.Args[1] == "--health-check" {
		healthCheck()
		return
	}

	r := gin.Default()

	// Добавляем middleware для логирования и восстановления после паники
	r.Use(gin.Logger())
	r.Use(gin.Recovery())

	r.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"message": "auth-service is running",
			"version": "1.0.0",
			"status":  "healthy",
		})
	})

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":  "healthy",
			"service": "auth-service",
		})
	})

	r.GET("/validate", func(c *gin.Context) {
		cookieToken, err := c.Cookie("token")
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"message": "unauthorized",
				"error":   "token missing",
			})
			return
		}

		valid, err := verifyToken(cookieToken)
		if err != nil {
			c.JSON(http.StatusUnauthorized, gin.H{
				"message": "unauthorized",
				"error":   err,
			})
			return
		}

		if valid {
			c.JSON(http.StatusOK, gin.H{
				"message": "authorized",
			})
		}
	})

	err := r.Run("0.0.0.0:9090")
	if err != nil {
		return
	}
}

// healthCheck выполняет проверку здоровья сервиса для Docker
func healthCheck() {
	resp, err := http.Get("http://localhost:9090/health")
	if err != nil {
		fmt.Printf("Health check failed: %v\n", err)
		os.Exit(1)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Printf("Health check failed with status: %d\n", resp.StatusCode)
		os.Exit(1)
	}

	fmt.Println("Health check passed")
	os.Exit(0)
}

func verifyToken(tokenString string) (bool, error) {
	jwtSecret := os.Getenv("WEBUI_SECRET_KEY")

	if len(jwtSecret) == 0 {
		return false, fmt.Errorf("JWT_SECRET env variable missing")
	}

	mySigningKey := []byte(jwtSecret)

	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (any, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("error parsing jwt")
		}
		return mySigningKey, nil
	})
	if err != nil {
		return false, err
	}

	return token.Valid, nil
}
