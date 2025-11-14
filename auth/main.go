package main

import (
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
)

func main() {
	// Проверяем аргументы командной строки для health check
	if len(os.Args) > 1 && os.Args[1] == "--health-check" {
		healthCheck()
		return
	}

	r := gin.New()

	r.Use(requestIDMiddleware())
	r.Use(gin.LoggerWithFormatter(requestLogger))
	r.Use(gin.Recovery())

	r.GET("/", func(c *gin.Context) {
		respondJSON(c, http.StatusOK, gin.H{
			"message": "auth-service is running",
			"version": "1.0.0",
			"status":  "healthy",
		})
	})

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		respondJSON(c, http.StatusOK, gin.H{
			"status":  "healthy",
			"service": "auth-service",
		})
	})

	r.GET("/validate", func(c *gin.Context) {
		cookieToken, err := c.Cookie("token")
		if err != nil {
			respondJSON(c, http.StatusUnauthorized, gin.H{
				"message": "unauthorized",
				"error":   "token missing",
			})
			return
		}

		valid, err := verifyToken(cookieToken)
		if err != nil {
			respondJSON(c, http.StatusUnauthorized, gin.H{
				"message": "unauthorized",
				"error":   err,
			})
			return
		}

		if valid {
			respondJSON(c, http.StatusOK, gin.H{
				"message": "authorized",
			})
		}
	})

	err := r.Run("0.0.0.0:9090")
	if err != nil {
		return
	}
}

func requestIDMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		reqID := c.GetHeader("X-Request-ID")
		if reqID == "" {
			reqID = uuid.NewString()
		}
		c.Set("request_id", reqID)
		c.Writer.Header().Set("X-Request-ID", reqID)
		c.Next()
	}
}

func requestLogger(param gin.LogFormatterParams) string {
	reqID, _ := param.Keys["request_id"].(string)
	return fmt.Sprintf(
		"{\"time\":\"%s\",\"status\":%d,\"latency_ms\":%.2f,\"client\":\"%s\",\"method\":\"%s\",\"path\":\"%s\",\"request_id\":\"%s\"}\n",
		param.TimeStamp.Format(time.RFC3339Nano),
		param.StatusCode,
		float64(param.Latency)/float64(time.Millisecond),
		param.ClientIP,
		param.Method,
		param.Path,
		reqID,
	)
}

func respondJSON(c *gin.Context, status int, payload gin.H) {
	if payload == nil {
		payload = gin.H{}
	}
	if _, exists := payload["request_id"]; !exists {
		payload["request_id"] = c.GetString("request_id")
	}
	c.JSON(status, payload)
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
