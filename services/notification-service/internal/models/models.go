package models

import (
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

// NotificationType represents the type of notification
type NotificationType string

const (
	NotificationTypeEmail     NotificationType = "email"
	NotificationTypeSMS       NotificationType = "sms"
	NotificationTypePush      NotificationType = "push"
	NotificationTypeWebSocket NotificationType = "websocket"
	NotificationTypeWebhook   NotificationType = "webhook"
)

// NotificationStatus represents the delivery status
type NotificationStatus string

const (
	NotificationStatusPending   NotificationStatus = "pending"
	NotificationStatusSent      NotificationStatus = "sent"
	NotificationStatusDelivered NotificationStatus = "delivered"
	NotificationStatusFailed    NotificationStatus = "failed"
	NotificationStatusRetrying  NotificationStatus = "retrying"
)

// Priority levels for notifications
type Priority string

const (
	PriorityLow    Priority = "low"
	PriorityNormal Priority = "normal"
	PriorityHigh   Priority = "high"
	PriorityUrgent Priority = "urgent"
)

// Notification represents a notification message
type Notification struct {
	ID          string             `json:"id" db:"id"`
	Type        NotificationType   `json:"type" db:"type"`
	Recipient   string             `json:"recipient" db:"recipient"`
	Subject     string             `json:"subject" db:"subject"`
	Message     string             `json:"message" db:"message"`
	Data        map[string]interface{} `json:"data" db:"data"`
	Status      NotificationStatus `json:"status" db:"status"`
	Priority    Priority           `json:"priority" db:"priority"`
	TemplateID  string             `json:"template_id,omitempty" db:"template_id"`
	CustomerID  string             `json:"customer_id" db:"customer_id"`
	OrderID     string             `json:"order_id,omitempty" db:"order_id"`
	CreatedAt   time.Time          `json:"created_at" db:"created_at"`
	ScheduledAt *time.Time         `json:"scheduled_at,omitempty" db:"scheduled_at"`
	SentAt      *time.Time         `json:"sent_at,omitempty" db:"sent_at"`
	DeliveredAt *time.Time         `json:"delivered_at,omitempty" db:"delivered_at"`
	FailedAt    *time.Time         `json:"failed_at,omitempty" db:"failed_at"`
	RetryCount  int                `json:"retry_count" db:"retry_count"`
	MaxRetries  int                `json:"max_retries" db:"max_retries"`
	ErrorMessage string            `json:"error_message,omitempty" db:"error_message"`
	Metadata    map[string]interface{} `json:"metadata" db:"metadata"`
}

// NotificationTemplate represents a reusable notification template
type NotificationTemplate struct {
	ID          string                 `json:"id" db:"id"`
	Name        string                 `json:"name" db:"name"`
	Type        NotificationType       `json:"type" db:"type"`
	Subject     string                 `json:"subject" db:"subject"`
	Body        string                 `json:"body" db:"body"`
	Variables   []string               `json:"variables" db:"variables"`
	Metadata    map[string]interface{} `json:"metadata" db:"metadata"`
	CreatedAt   time.Time              `json:"created_at" db:"created_at"`
	UpdatedAt   time.Time              `json:"updated_at" db:"updated_at"`
	IsActive    bool                   `json:"is_active" db:"is_active"`
}

// CustomerPreferences represents customer notification preferences
type CustomerPreferences struct {
	CustomerID        string                    `json:"customer_id" db:"customer_id"`
	EmailEnabled      bool                      `json:"email_enabled" db:"email_enabled"`
	SMSEnabled        bool                      `json:"sms_enabled" db:"sms_enabled"`
	PushEnabled       bool                      `json:"push_enabled" db:"push_enabled"`
	WebhookEnabled    bool                      `json:"webhook_enabled" db:"webhook_enabled"`
	WebhookURL        string                    `json:"webhook_url,omitempty" db:"webhook_url"`
	PreferredTypes    []NotificationType        `json:"preferred_types" db:"preferred_types"`
	QuietHours        *QuietHours               `json:"quiet_hours,omitempty" db:"quiet_hours"`
	Categories        map[string]bool           `json:"categories" db:"categories"`
	CreatedAt         time.Time                 `json:"created_at" db:"created_at"`
	UpdatedAt         time.Time                 `json:"updated_at" db:"updated_at"`
}

// QuietHours represents time ranges when notifications should not be sent
type QuietHours struct {
	Enabled   bool   `json:"enabled"`
	StartTime string `json:"start_time"` // Format: "22:00"
	EndTime   string `json:"end_time"`   // Format: "08:00"
	Timezone  string `json:"timezone"`   // Format: "UTC" or "America/New_York"
}

// DeliveryStats represents notification delivery statistics
type DeliveryStats struct {
	TotalSent      int64   `json:"total_sent"`
	TotalDelivered int64   `json:"total_delivered"`
	TotalFailed    int64   `json:"total_failed"`
	DeliveryRate   float64 `json:"delivery_rate"`
	AvgDeliveryTime float64 `json:"avg_delivery_time_seconds"`
	ByType         map[NotificationType]TypeStats `json:"by_type"`
	ByPriority     map[Priority]PriorityStats     `json:"by_priority"`
	TimeRange      string  `json:"time_range"`
}

// TypeStats represents statistics by notification type
type TypeStats struct {
	Sent         int64   `json:"sent"`
	Delivered    int64   `json:"delivered"`
	Failed       int64   `json:"failed"`
	DeliveryRate float64 `json:"delivery_rate"`
}

// PriorityStats represents statistics by priority
type PriorityStats struct {
	Sent         int64   `json:"sent"`
	Delivered    int64   `json:"delivered"`
	Failed       int64   `json:"failed"`
	AvgTime      float64 `json:"avg_delivery_time_seconds"`
}

// WebSocket models
var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow connections from any origin for demo
	},
}

// Client represents a WebSocket client
type Client struct {
	Hub        *Hub
	Conn       *websocket.Conn
	Send       chan []byte
	CustomerID string
	UserAgent  string
	IPAddress  string
	ConnectedAt time.Time
}

// Hub maintains active WebSocket connections and broadcasts messages
type Hub struct {
	Clients    map[*Client]bool
	Register   chan *Client
	Unregister chan *Client
	Broadcast  chan []byte
	mutex      sync.RWMutex
}

// WebSocketMessage represents a message sent over WebSocket
type WebSocketMessage struct {
	Type      string      `json:"type"`
	Data      interface{} `json:"data"`
	Timestamp time.Time   `json:"timestamp"`
}

// NewWebSocketHub creates a new WebSocket hub
func NewWebSocketHub() *Hub {
	return &Hub{
		Clients:    make(map[*Client]bool),
		Register:   make(chan *Client),
		Unregister: make(chan *Client),
		Broadcast:  make(chan []byte),
	}
}

// Run starts the WebSocket hub
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.Register:
			h.mutex.Lock()
			h.Clients[client] = true
			h.mutex.Unlock()
			log.Printf("WebSocket client connected: %s", client.CustomerID)

		case client := <-h.Unregister:
			h.mutex.Lock()
			if _, ok := h.Clients[client]; ok {
				delete(h.Clients, client)
				close(client.Send)
			}
			h.mutex.Unlock()
			log.Printf("WebSocket client disconnected: %s", client.CustomerID)

		case message := <-h.Broadcast:
			h.mutex.RLock()
			for client := range h.Clients {
				select {
				case client.Send <- message:
				default:
					close(client.Send)
					delete(h.Clients, client)
				}
			}
			h.mutex.RUnlock()
		}
	}
}

// GetActiveConnections returns the number of active WebSocket connections
func (h *Hub) GetActiveConnections() int {
	h.mutex.RLock()
	defer h.mutex.RUnlock()
	return len(h.Clients)
}

// SendToCustomer sends a message to a specific customer
func (h *Hub) SendToCustomer(customerID string, message interface{}) error {
	wsMessage := WebSocketMessage{
		Type:      "notification",
		Data:      message,
		Timestamp: time.Now(),
	}

	messageBytes, err := json.Marshal(wsMessage)
	if err != nil {
		return err
	}

	h.mutex.RLock()
	defer h.mutex.RUnlock()

	for client := range h.Clients {
		if client.CustomerID == customerID {
			select {
			case client.Send <- messageBytes:
			default:
				close(client.Send)
				delete(h.Clients, client)
			}
		}
	}

	return nil
}

// BroadcastToAll sends a message to all connected clients
func (h *Hub) BroadcastToAll(message interface{}) error {
	wsMessage := WebSocketMessage{
		Type:      "broadcast",
		Data:      message,
		Timestamp: time.Now(),
	}

	messageBytes, err := json.Marshal(wsMessage)
	if err != nil {
		return err
	}

	h.Broadcast <- messageBytes
	return nil
}

// Event Hub message models
type OrderCreatedEvent struct {
	EventType   string    `json:"EventType"`
	OrderID     string    `json:"OrderId"`
	CustomerID  string    `json:"CustomerId"`
	ProductID   int       `json:"ProductId"`
	Quantity    int       `json:"Quantity"`
	TotalAmount float64   `json:"TotalAmount"`
	Timestamp   time.Time `json:"Timestamp"`
}

type OrderStatusUpdatedEvent struct {
	EventType  string    `json:"EventType"`
	OrderID    string    `json:"OrderId"`
	Status     string    `json:"Status"`
	Timestamp  time.Time `json:"Timestamp"`
}

// Request/Response models
type CreateNotificationRequest struct {
	Type        NotificationType       `json:"type" binding:"required"`
	Recipient   string                 `json:"recipient" binding:"required"`
	Subject     string                 `json:"subject"`
	Message     string                 `json:"message" binding:"required"`
	Data        map[string]interface{} `json:"data"`
	Priority    Priority               `json:"priority"`
	TemplateID  string                 `json:"template_id,omitempty"`
	CustomerID  string                 `json:"customer_id" binding:"required"`
	OrderID     string                 `json:"order_id,omitempty"`
	ScheduledAt *time.Time             `json:"scheduled_at,omitempty"`
}

type UpdateNotificationStatusRequest struct {
	Status       NotificationStatus `json:"status" binding:"required"`
	ErrorMessage string             `json:"error_message,omitempty"`
}

type BulkNotificationRequest struct {
	Notifications []CreateNotificationRequest `json:"notifications" binding:"required,min=1,max=100"`
}

type BroadcastNotificationRequest struct {
	Type     NotificationType       `json:"type" binding:"required"`
	Subject  string                 `json:"subject"`
	Message  string                 `json:"message" binding:"required"`
	Data     map[string]interface{} `json:"data"`
	Priority Priority               `json:"priority"`
	Filters  BroadcastFilters       `json:"filters"`
}

type BroadcastFilters struct {
	CustomerIDs []string             `json:"customer_ids,omitempty"`
	Types       []NotificationType   `json:"types,omitempty"`
	Categories  []string             `json:"categories,omitempty"`
}

// HealthCheck response
type HealthResponse struct {
	Status      string    `json:"status"`
	Timestamp   time.Time `json:"timestamp"`
	Service     string    `json:"service"`
	Version     string    `json:"version"`
	Uptime      string    `json:"uptime"`
	Checks      map[string]interface{} `json:"checks,omitempty"`
}