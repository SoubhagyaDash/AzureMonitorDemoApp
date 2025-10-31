package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"notification-service/internal/config"
	"notification-service/internal/handlers"
	"notification-service/internal/middleware"
	"notification-service/internal/models"
	"notification-service/internal/services"
	"notification-service/internal/telemetry"

	"github.com/gin-gonic/gin"
	"go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin"
)

func main() {
	// Load configuration
	cfg := config.Load()

	// Initialize OpenTelemetry
	shutdown, err := telemetry.InitTelemetry(cfg)
	if err != nil {
		log.Fatalf("Failed to initialize telemetry: %v", err)
	}
	defer func() {
		if err := shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down telemetry: %v", err)
		}
	}()

	// Initialize services
	redisClient := services.NewRedisClient(cfg.RedisURL)
	defer redisClient.Close()

	eventHubService := services.NewEventHubService(cfg.EventHubConnectionString, cfg.EventHubName)
	defer eventHubService.Close()

	notificationService := services.NewNotificationService(redisClient, eventHubService)
	emailService := services.NewEmailService(cfg)
	smsService := services.NewSMSService(cfg)
	pushService := services.NewPushNotificationService(cfg)
	webhookService := services.NewWebhookService(cfg)

	// Initialize WebSocket hub
	wsHub := models.NewWebSocketHub()
	go wsHub.Run()

	// Initialize handlers
	notificationHandler := handlers.NewNotificationHandler(
		notificationService,
		emailService,
		smsService,
		pushService,
		webhookService,
		wsHub,
	)

	// Setup Gin router
	if cfg.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.New()

	// Middleware
	router.Use(gin.Logger())
	router.Use(gin.Recovery())
	router.Use(otelgin.Middleware("notification-service"))
	router.Use(middleware.CORSMiddleware())
	router.Use(middleware.FailureInjectionMiddleware(cfg))
	router.Use(middleware.MetricsMiddleware())

	// Health check endpoints
	router.GET("/health", handlers.HealthCheck)
	router.GET("/health/ready", handlers.ReadinessCheck)
	router.GET("/health/live", handlers.LivenessCheck)

	// Metrics endpoint
	router.GET("/metrics", handlers.MetricsHandler)

	// API routes
	api := router.Group("/api/v1")
	{
		// Notification endpoints
		api.POST("/notifications", notificationHandler.CreateNotification)
		api.GET("/notifications", notificationHandler.GetNotifications)
		api.GET("/notifications/:id", notificationHandler.GetNotification)
		api.PUT("/notifications/:id/status", notificationHandler.UpdateNotificationStatus)
		api.DELETE("/notifications/:id", notificationHandler.DeleteNotification)

		// Template endpoints
		api.POST("/templates", notificationHandler.CreateTemplate)
		api.GET("/templates", notificationHandler.GetTemplates)
		api.GET("/templates/:id", notificationHandler.GetTemplate)
		api.PUT("/templates/:id", notificationHandler.UpdateTemplate)
		api.DELETE("/templates/:id", notificationHandler.DeleteTemplate)

		// Bulk operations
		api.POST("/notifications/bulk", notificationHandler.SendBulkNotifications)
		api.POST("/notifications/broadcast", notificationHandler.BroadcastNotification)

		// Customer preferences
		api.GET("/customers/:customerId/preferences", notificationHandler.GetCustomerPreferences)
		api.PUT("/customers/:customerId/preferences", notificationHandler.UpdateCustomerPreferences)

		// Analytics
		api.GET("/analytics/delivery-stats", notificationHandler.GetDeliveryStats)
		api.GET("/analytics/engagement-metrics", notificationHandler.GetEngagementMetrics)
	}

	// WebSocket endpoint
	router.GET("/ws", notificationHandler.HandleWebSocket)

	// Start event processing in background
	go func() {
		if err := eventHubService.StartProcessing(context.Background(), notificationHandler.ProcessEventHubMessage); err != nil {
			log.Printf("Error starting event processing: %v", err)
		}
	}()

	// Start HTTP server
	server := &http.Server{
		Addr:    fmt.Sprintf(":%s", cfg.Port),
		Handler: router,
	}

	// Start server in goroutine
	go func() {
		log.Printf("Notification service starting on port %s", cfg.Port)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Failed to start server: %v", err)
		}
	}()

	// Wait for interrupt signal to gracefully shutdown the server
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	log.Println("Shutting down notification service...")

	// Graceful shutdown with timeout
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := server.Shutdown(ctx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Notification service stopped")
}