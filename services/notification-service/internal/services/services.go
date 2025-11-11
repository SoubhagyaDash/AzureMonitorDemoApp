package services

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"notification-service/internal/config"
	"notification-service/internal/telemetry"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore/to"
	"github.com/Azure/azure-sdk-for-go/sdk/messaging/azeventhubs"
	"github.com/go-redis/redis/v8"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
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

	// Log connection details (sanitized)
	log.Printf("Initializing Event Hub consumer with consumer group: %s", e.consumerGroup)
	
	// Create consumer client with tracing enabled
	// The Azure SDK for Go automatically uses the global OpenTelemetry tracer provider
	// No explicit configuration needed - it will pick up the global otel.SetTracerProvider
	// If connection string contains EntityPath, use empty string for eventHubName
	consumerClient, err := azeventhubs.NewConsumerClientFromConnectionString(
		e.connectionString,
		"", // Empty string because connection string contains EntityPath
		e.consumerGroup,
		nil,
	)
	if err != nil {
		return fmt.Errorf("failed to create Event Hub consumer client: %w", err)
	}
	e.consumerClient = consumerClient

	log.Printf("✓ Event Hub consumer client created successfully for consumer group: %s", e.consumerGroup)

	// Get partition properties to find partition IDs
	log.Println("Fetching Event Hub properties...")
	props, err := consumerClient.GetEventHubProperties(ctx, nil)
	if err != nil {
		return fmt.Errorf("failed to get Event Hub properties: %w", err)
	}

	log.Printf("✓ Event Hub has %d partitions: %v", len(props.PartitionIDs), props.PartitionIDs)
	log.Printf("✓ Event Hub name: %s", props.Name)

	// Process messages from all partitions
	log.Println("Starting partition processors...")
	for _, partitionID := range props.PartitionIDs {
		log.Printf("→ Launching goroutine for partition %s", partitionID)
		go e.processPartition(ctx, partitionID, handler)
	}

	log.Println("✓ All partition processors launched successfully")
	return nil
}

// processPartition processes messages from a single partition
func (e *EventHubService) processPartition(ctx context.Context, partitionID string, handler func([]byte) error) {
	log.Printf("Starting to process partition: %s", partitionID)

	partitionClient, err := e.consumerClient.NewPartitionClient(partitionID, &azeventhubs.PartitionClientOptions{
		StartPosition: azeventhubs.StartPosition{
			Latest: to.Ptr(true), // Start from latest - only receive new messages
		},
	})
	if err != nil {
		log.Printf("ERROR: Failed to create partition client for partition %s: %v", partitionID, err)
		return
	}
	defer partitionClient.Close(ctx)

	log.Printf("Partition %s: partition client created, starting to receive events...", partitionID)

	pollCount := 0
	for {
		select {
		case <-ctx.Done():
			log.Printf("Context cancelled, stopping processing for partition: %s", partitionID)
			return
		default:
			pollCount++
			// Log every 10th poll attempt to show we're actively polling
			if pollCount%10 == 0 {
				log.Printf("Partition %s: polling attempt #%d (still listening for events)", partitionID, pollCount)
			}
			
			// Receive batch of events with timeout
			receiveCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
			log.Printf("Partition %s: calling ReceiveEvents (max 10 events, 30s timeout)...", partitionID)
			events, err := partitionClient.ReceiveEvents(receiveCtx, 10, nil)
			cancel()
			
			if err != nil {
				log.Printf("ERROR: Failed to receive events from partition %s: %v", partitionID, err)
				time.Sleep(5 * time.Second)
				continue
			}

			log.Printf("Partition %s: ReceiveEvents returned %d events", partitionID, len(events))
			
			if len(events) > 0 {
				log.Printf("Partition %s: PROCESSING %d events", partitionID, len(events))
			} else {
				// No events, sleep briefly to avoid tight loop
				time.Sleep(1 * time.Second)
			}

			// Process each event
			for _, event := range events {
				if event.Body == nil || len(event.Body) == 0 {
					continue
				}

				log.Printf("Received event from partition %s: %d bytes", partitionID, len(event.Body))

				// Extract distributed tracing context from EventHub message properties
				propagator := otel.GetTextMapPropagator()
				carrier := propagation.MapCarrier{}
				
				// Map EventHub properties to W3C trace context format
				if event.Properties != nil {
					for key, value := range event.Properties {
						if strValue, ok := value.(string); ok {
							// Check for Diagnostic-Id (used by Azure SDKs) or traceparent
							if key == "Diagnostic-Id" || key == "traceparent" {
								carrier["traceparent"] = strValue
							} else if key == "tracestate" {
								carrier["tracestate"] = strValue
							}
						}
					}
				}
				
				// Extract context and create span as child of upstream context
				// Application Insights uses operation_ParentId for Application Map correlation
				eventCtx := propagator.Extract(ctx, carrier)
				upstreamSpanContext := trace.SpanContextFromContext(eventCtx)
				
				_, span := telemetry.Tracer.Start(eventCtx, "eventhub.receive",
					trace.WithSpanKind(trace.SpanKindConsumer),
					trace.WithAttributes(
						attribute.String("messaging.system", "eventhub"),
						attribute.String("messaging.destination", "notification-events"),
						attribute.String("messaging.operation", "receive"),
						attribute.String("partition.id", partitionID),
					),
				)
				
				// CRITICAL: Set Azure Monitor correlation attributes explicitly
				// This ensures Application Map can connect services through EventHub
				if upstreamSpanContext.IsValid() {
					span.SetAttributes(
						attribute.String("ai.operation.id", upstreamSpanContext.TraceID().String()),
						attribute.String("ai.operation.parentId", upstreamSpanContext.SpanID().String()),
					)
				}

				// Call the handler
				if err := handler(event.Body); err != nil {
					log.Printf("ERROR: Handler failed for event from partition %s: %v", partitionID, err)
					span.RecordError(err)
					span.SetStatus(codes.Error, err.Error())
					// Continue processing other events even if one fails
				} else {
					span.SetStatus(codes.Ok, "Event processed successfully")
				}
				
				span.End()
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
	Timestamp   string    `json:"Timestamp"` // Using string to handle .NET DateTime format
}

// ParseOrderEvent parses an order event from JSON
func ParseOrderEvent(data []byte) (*OrderEvent, error) {
	var event OrderEvent
	if err := json.Unmarshal(data, &event); err != nil {
		return nil, fmt.Errorf("failed to unmarshal order event: %w", err)
	}
	
	// Parse the timestamp - try multiple formats to handle .NET DateTime serialization
	if event.Timestamp != "" {
		// Try parsing common formats
		formats := []string{
			time.RFC3339,                      // 2006-01-02T15:04:05Z07:00
			time.RFC3339Nano,                  // 2006-01-02T15:04:05.999999999Z07:00
			"2006-01-02T15:04:05.9999999",     // .NET DateTime without timezone
			"2006-01-02T15:04:05",             // Simple ISO format
		}
		
		for _, format := range formats {
			if _, err := time.Parse(format, event.Timestamp); err == nil {
				break
			}
		}
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
