package handlers

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"notification-service/internal/models"
	"notification-service/internal/services"
	"notification-service/internal/telemetry"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

type NotificationHandler struct {
	notificationService *services.NotificationService
	emailService        *services.EmailService
	smsService          *services.SMSService
	pushService         *services.PushNotificationService
	webhookService      *services.WebhookService
	wsHub               *models.Hub
}

func NewNotificationHandler(
	notificationService *services.NotificationService,
	emailService *services.EmailService,
	smsService *services.SMSService,
	pushService *services.PushNotificationService,
	webhookService *services.WebhookService,
	wsHub *models.Hub,
) *NotificationHandler {
	return &NotificationHandler{
		notificationService: notificationService,
		emailService:        emailService,
		smsService:          smsService,
		pushService:         pushService,
		webhookService:      webhookService,
		wsHub:               wsHub,
	}
}

func (h *NotificationHandler) CreateNotification(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "CreateNotification - not implemented"})
}

func (h *NotificationHandler) GetNotifications(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"notifications": []interface{}{}})
}

func (h *NotificationHandler) GetNotification(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"notification": nil})
}

func (h *NotificationHandler) UpdateNotificationStatus(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "UpdateNotificationStatus - not implemented"})
}

func (h *NotificationHandler) DeleteNotification(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "DeleteNotification - not implemented"})
}

func (h *NotificationHandler) CreateTemplate(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "CreateTemplate - not implemented"})
}

func (h *NotificationHandler) GetTemplates(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"templates": []interface{}{}})
}

func (h *NotificationHandler) GetTemplate(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"template": nil})
}

func (h *NotificationHandler) UpdateTemplate(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "UpdateTemplate - not implemented"})
}

func (h *NotificationHandler) DeleteTemplate(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "DeleteTemplate - not implemented"})
}

func (h *NotificationHandler) SendBulkNotifications(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "SendBulkNotifications - not implemented"})
}

func (h *NotificationHandler) BroadcastNotification(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "BroadcastNotification - not implemented"})
}

func (h *NotificationHandler) GetCustomerPreferences(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"preferences": nil})
}

func (h *NotificationHandler) UpdateCustomerPreferences(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"message": "UpdateCustomerPreferences - not implemented"})
}

func (h *NotificationHandler) GetDeliveryStats(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"stats": nil})
}

func (h *NotificationHandler) GetEngagementMetrics(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"metrics": nil})
}

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
}

func (h *NotificationHandler) HandleWebSocket(c *gin.Context) {
	conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// Handle WebSocket connection
	defer conn.Close()
}

func (h *NotificationHandler) ProcessEventHubMessage(message []byte) error {
	start := time.Now()
	ctx := context.Background()
	
	// Create a span for event processing
	ctx, span := telemetry.Tracer.Start(ctx, "ProcessEventHubMessage",
		trace.WithSpanKind(trace.SpanKindConsumer),
		trace.WithAttributes(
			attribute.Int("message.size", len(message)),
		),
	)
	defer span.End()

	// Parse the order event
	event, err := services.ParseOrderEvent(message)
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "Failed to parse event")
		log.Printf("Failed to parse event: %v", err)
		
		// Record error metric
		telemetry.RecordEventHubMessage(ctx, "unknown", "unknown", false, time.Since(start).Seconds())
		return err
	}

	// Add event details to span
	span.SetAttributes(
		attribute.String("event.type", event.EventType),
		attribute.String("order.id", event.OrderID),
		attribute.String("customer.id", event.CustomerID),
		attribute.Float64("order.total_amount", event.TotalAmount),
	)

	log.Printf("Processing %s event for Order ID: %s, Customer ID: %s", 
		event.EventType, event.OrderID, event.CustomerID)

	// Create notification based on event type
	notification := models.WebSocketMessage{
		Type:      "notification",
		Timestamp: time.Now(),
	}

	switch event.EventType {
	case "OrderCreated":
		notification.Data = map[string]interface{}{
			"type":        "order_created",
			"orderId":     event.OrderID,
			"customerId":  event.CustomerID,
			"subject":     "Order Confirmed",
			"message":     fmt.Sprintf("Your order #%s has been confirmed! Total: $%.2f", event.OrderID, event.TotalAmount),
			"totalAmount": event.TotalAmount,
			"productId":   event.ProductID,
			"quantity":    event.Quantity,
			"timestamp":   event.Timestamp,
		}

	case "OrderStatusUpdated":
		notification.Data = map[string]interface{}{
			"type":       "order_status_updated",
			"orderId":    event.OrderID,
			"customerId": event.CustomerID,
			"subject":    "Order Status Update",
			"message":    fmt.Sprintf("Order #%s status: %s", event.OrderID, event.Status),
			"status":     event.Status,
			"timestamp":  event.Timestamp,
		}

	case "PaymentProcessed":
		notification.Data = map[string]interface{}{
			"type":        "payment_processed",
			"orderId":     event.OrderID,
			"customerId":  event.CustomerID,
			"subject":     "Payment Processed",
			"message":     fmt.Sprintf("Payment of $%.2f processed for order #%s", event.TotalAmount, event.OrderID),
			"totalAmount": event.TotalAmount,
			"timestamp":   event.Timestamp,
		}

	default:
		log.Printf("Unknown event type: %s", event.EventType)
		notification.Data = map[string]interface{}{
			"type":       "order_event",
			"orderId":    event.OrderID,
			"customerId": event.CustomerID,
			"subject":    "Order Update",
			"message":    fmt.Sprintf("Update for order #%s", event.OrderID),
			"eventType":  event.EventType,
			"timestamp":  event.Timestamp,
		}
	}

	// Send notification via WebSocket with telemetry
	wsStart := time.Now()
	err = h.wsHub.SendToCustomer(event.CustomerID, notification)
	wsDuration := time.Since(wsStart).Seconds()
	
	if err != nil {
		span.RecordError(err)
		span.SetStatus(codes.Error, "Failed to send WebSocket notification")
		log.Printf("Failed to send WebSocket notification: %v", err)
		
		// Record WebSocket error metric
		telemetry.RecordWebSocketMessage(ctx, event.CustomerID, event.EventType, false, wsDuration)
		telemetry.RecordNotificationError(ctx, event.EventType, "websocket", err.Error())
		
		// Don't return error - WebSocket failure shouldn't fail event processing
	} else {
		log.Printf("Sent %s notification to customer %s via WebSocket", 
			event.EventType, event.CustomerID)
		
		// Record successful WebSocket delivery
		telemetry.RecordWebSocketMessage(ctx, event.CustomerID, event.EventType, true, wsDuration)
		telemetry.RecordNotificationSent(ctx, event.EventType, "websocket")
	}

	// Record successful event processing
	duration := time.Since(start).Seconds()
	telemetry.RecordEventHubMessage(ctx, "unknown-partition", event.EventType, true, duration)
	
	span.SetStatus(codes.Ok, "Event processed successfully")
	return nil
}

func HealthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "healthy"})
}

func ReadinessCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ready"})
}

func LivenessCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "live"})
}

func MetricsHandler(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"metrics": "prometheus metrics"})
}
