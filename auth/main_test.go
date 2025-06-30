package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Настройка тестового окружения
func TestMain(m *testing.M) {
	// Устанавливаем Gin в тестовый режим
	gin.SetMode(gin.TestMode)

	// Устанавливаем тестовые переменные окружения
	os.Setenv("WEBUI_SECRET_KEY", "test-secret-key-for-testing")

	// Запускаем тесты
	code := m.Run()

	// Очищаем переменные окружения
	os.Unsetenv("WEBUI_SECRET_KEY")

	os.Exit(code)
}

// Тест корневого эндпоинта
func TestRootEndpoint(t *testing.T) {
	// Создаем тестовый роутер
	router := setupRouter()

	// Создаем тестовый запрос
	req, err := http.NewRequest("GET", "/", nil)
	require.NoError(t, err)

	// Создаем ResponseRecorder для записи ответа
	w := httptest.NewRecorder()

	// Выполняем запрос
	router.ServeHTTP(w, req)

	// Проверяем статус код
	assert.Equal(t, http.StatusOK, w.Code)

	// Проверяем содержимое ответа
	var response map[string]any
	err = json.Unmarshal(w.Body.Bytes(), &response)
	require.NoError(t, err)

	assert.Equal(t, "auth-service is running", response["message"])
}

// Тест валидации с отсутствующим токеном
func TestValidateEndpointMissingToken(t *testing.T) {
	router := setupRouter()

	req, err := http.NewRequest("GET", "/validate", nil)
	require.NoError(t, err)

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	// Ожидаем 401 Unauthorized
	assert.Equal(t, http.StatusUnauthorized, w.Code)

	var response map[string]any
	err = json.Unmarshal(w.Body.Bytes(), &response)
	require.NoError(t, err)

	assert.Equal(t, "unauthorized", response["message"])
	assert.Equal(t, "token missing", response["error"])
}

// Тест валидации с валидным токеном
func TestValidateEndpointValidToken(t *testing.T) {
	router := setupRouter()

	// Создаем валидный JWT токен
	token := createValidJWTToken(t)

	req, err := http.NewRequest("GET", "/validate", nil)
	require.NoError(t, err)

	// Добавляем токен в cookie
	req.AddCookie(&http.Cookie{
		Name:  "token",
		Value: token,
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	// Ожидаем 200 OK
	assert.Equal(t, http.StatusOK, w.Code)

	var response map[string]any
	err = json.Unmarshal(w.Body.Bytes(), &response)
	require.NoError(t, err)

	assert.Equal(t, "authorized", response["message"])
}

// Тест валидации с невалидным токеном
func TestValidateEndpointInvalidToken(t *testing.T) {
	router := setupRouter()

	req, err := http.NewRequest("GET", "/validate", nil)
	require.NoError(t, err)

	// Добавляем невалидный токен
	req.AddCookie(&http.Cookie{
		Name:  "token",
		Value: "invalid.jwt.token",
	})

	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	// Ожидаем 401 Unauthorized
	assert.Equal(t, http.StatusUnauthorized, w.Code)

	var response map[string]any
	err = json.Unmarshal(w.Body.Bytes(), &response)
	require.NoError(t, err)

	assert.Equal(t, "unauthorized", response["message"])
}

// Тест функции verifyToken с валидным токеном
func TestVerifyTokenValid(t *testing.T) {
	token := createValidJWTToken(t)

	valid, err := verifyToken(token)

	assert.NoError(t, err)
	assert.True(t, valid)
}

// Тест функции verifyToken с невалидным токеном
func TestVerifyTokenInvalid(t *testing.T) {
	valid, err := verifyToken("invalid.jwt.token")

	assert.Error(t, err)
	assert.False(t, valid)
}

// Тест функции verifyToken с отсутствующим секретом
func TestVerifyTokenMissingSecret(t *testing.T) {
	// Временно удаляем переменную окружения
	originalSecret := os.Getenv("WEBUI_SECRET_KEY")
	os.Unsetenv("WEBUI_SECRET_KEY")
	defer os.Setenv("WEBUI_SECRET_KEY", originalSecret)

	token := "any.jwt.token"

	valid, err := verifyToken(token)

	assert.Error(t, err)
	assert.False(t, valid)
	assert.Contains(t, err.Error(), "JWT_SECRET env variable missing")
}

// Тест функции verifyToken с истекшим токеном
func TestVerifyTokenExpired(t *testing.T) {
	token := createExpiredJWTToken(t)

	valid, err := verifyToken(token)

	assert.Error(t, err)
	assert.False(t, valid)
}

// Вспомогательные функции

// setupRouter создает тестовый роутер
func setupRouter() *gin.Engine {
	router := gin.New()

	router.GET("/", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"message": "auth-service is running",
		})
	})

	router.GET("/validate", func(c *gin.Context) {
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
				"error":   err.Error(),
			})
			return
		}

		if valid {
			c.JSON(http.StatusOK, gin.H{
				"message": "authorized",
			})
		}
	})

	return router
}

// createValidJWTToken создает валидный JWT токен для тестов
func createValidJWTToken(t *testing.T) string {
	secret := os.Getenv("WEBUI_SECRET_KEY")
	require.NotEmpty(t, secret, "WEBUI_SECRET_KEY должен быть установлен для тестов")

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": "test-user",
		"iat": time.Now().Unix(),
		"exp": time.Now().Add(time.Hour).Unix(),
	})

	tokenString, err := token.SignedString([]byte(secret))
	require.NoError(t, err)

	return tokenString
}

// createExpiredJWTToken создает истекший JWT токен для тестов
func createExpiredJWTToken(t *testing.T) string {
	secret := os.Getenv("WEBUI_SECRET_KEY")
	require.NotEmpty(t, secret, "WEBUI_SECRET_KEY должен быть установлен для тестов")

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"sub": "test-user",
		"iat": time.Now().Add(-2 * time.Hour).Unix(),
		"exp": time.Now().Add(-time.Hour).Unix(), // Истек час назад
	})

	tokenString, err := token.SignedString([]byte(secret))
	require.NoError(t, err)

	return tokenString
}
