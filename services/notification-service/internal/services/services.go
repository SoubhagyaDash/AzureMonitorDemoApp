package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"notification-service/internal/config"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/messaging/azeventhubs"
	"github.com/Azure/azure-sdk-for-go/sdk/messaging/azeventhubs/checkpoints"
	"github.com/Azure/azure-sdk-for-go/sdk/storage/azblob"
	"github.com/go-redis/redis/v8"
)

type NotificationService struct {
	redis    *RedisClient
	eventHub *EventHubService
}

func NewNotificationService(redis *RedisClient, eventHub *EventHubService) *NotificationService {
	return &NotificationService{
		redis:    redis,
		eventHub: eventHub,
	}
}

type RedisClient struct {
	client *redis.Client
}

func NewRedisClient(url string) *RedisClient {
	client := redis.NewClient(&redis.Options{
		Addr: url,
	})
	return &RedisClient{client: client}
}

func (r *RedisClient) Close() error {
	return r.client.Close()
}

// EventHubService handles Event Hub message consumption
type EventHubService struct {
	connectionString string
	eventHubName     string
	consumerClient   *azeventhubs.ConsumerClient
	processor        *azeventhubs.Processor
	consumerGroup    string
}

func NewEventHubService(connectionString, eventHubName string) *EventHubService {
	return &EventHubService{
		connectionString: connectionString,
		eventHubName:     eventHubName,
		consumerGroup:    azeventhubs.DefaultConsumerGroup,
	}
}

func (e *EventHubService) Close() error {
	if e.processor != nil {
		return e.processor.Close(context.Background())
	}
	if e.consumerClient != nil {
		return e.consumerClient.Close(context.Background())
	}
	return nil
}

// StartProcessing starts consuming messages from Event Hub
func (e *EventHubService) StartProcessing(ctx context.Context, handler func([]byte) error) error {
	if e.connectionString == "" {
		log.Println("Event Hub connection string not configured, skipping Event Hub processing")
		return nil
	}

	// Create consumer client
	consumerClient, err := azeventhubs.NewConsumerClientFromConnectionString(
		e.connectionString,
		e.eventHubName,
		e.consumerGroup,
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create Event Hub consumer client: %w", err)
	}
	e.consumerClient = consumerClient

	log.Printf("Event Hub consumer client created for hub: %s, consumer group: %s", e.eventHubName, e.consumerGroup)

	// Get partition IDs
	partitionIDs, err := consumerClient.GetPartitionIDs(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to get partition IDs: %w", err)
	}

	log.Printf("Event Hub has %d partitions", len(partitionIDs))

	// Process messages from all partitions
	for _, partitionID := range partitionIDs {
		go e.processPartition(ctx, partitionID, handler)
	}

	return nil
}

// processPartition processes messages from a single partition
func (e *EventHubService) processPartition(ctx context.Context, partitionID string, handler func([]byte) error) {
	log.Printf("Starting to process partition: %s", partitionID)

	partitionClient, err := e.consumerClient.NewPartitionClient(partitionID, &azeventhubs.PartitionClientOptions{
		StartPosition: azeventhubs.StartPosition{
			Earliest: true, // Start from the beginning for demo purposes
		},
	})
	if err != nil {
		log.Printf("ERROR: Failed to create partition client for partition %s: %v", partitionID, err)
		return
	}
	defer partitionClient.Close(ctx)

	for {
		select {
		case <-ctx.Done():
			log.Printf("Context cancelled, stopping processing for partition: %s", partitionID)
			return
		default:
			// Receive batch of events
			events, err := partitionClient.ReceiveEvents(ctx, 10, &azeventhubs.ReceiveEventsOptions{
				MaxWaitTime: 5 * time.Second,
			})
			if err != nil {
				log.Printf("ERROR: Failed to receive events from partition %s: %v", partitionID, err)
				time.Sleep(5 * time.Second)
				continue
			}

			// Process each event
			for _, event := range events {
				if event.Body == nil || len(event.Body) == 0 {
					continue
				}

				log.Printf("Received event from partition %s: %d bytes", partitionID, len(event.Body))

				// Call the handler
				if err := handler(event.Body); err != nil {
					log.Printf("ERROR: Handler failed for event from partition %s: %v", partitionID, err)
					// Continue processing other events even if one fails
					continue
				}

				// Log successful processing
				log.Printf("Successfully processed event from partition %s", partitionID)
			}
		}
	}
}

// OrderEvent represents an order event from Event Hub
type OrderEvent struct {
	EventType   string    `json:"EventType"`
	OrderID     string    `json:"OrderId"`
	CustomerID  string    `json:"CustomerId"`
	ProductID   int       `json:"ProductId"`
	Quantity    int       `json:"Quantity"`
	TotalAmount float64   `json:"TotalAmount"`
	Status      string    `json:"Status"`
	Timestamp   time.Time `json:"Timestamp"`
}

// ParseOrderEvent parses an order event from JSON
func ParseOrderEvent(data []byte) (*OrderEvent, error) {
	var event OrderEvent
	if err := json.Unmarshal(data, &event); err != nil {
		return nil, fmt.Errorf("failed to unmarshal order event: %w", err)
	}
	return &event, nil
}

type EmailService struct {
	cfg *config.Config
}

func NewEmailService(cfg *config.Config) *EmailService {
	return &EmailService{cfg: cfg}
}

type SMSService struct {
	cfg *config.Config
}

func NewSMSService(cfg *config.Config) *SMSService {
	return &SMSService{cfg: cfg}
}

type PushNotificationService struct {
	cfg *config.Config
}

func NewPushNotificationService(cfg *config.Config) *PushNotificationService {
	return &PushNotificationService{cfg: cfg}
}

type WebhookService struct {
	cfg *config.Config
}

func NewWebhookService(cfg *config.Config) *WebhookService {
	return &WebhookService{cfg: cfg}
}
