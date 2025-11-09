package telemetry

import (
	"context"
	"fmt"
	"log"
	"net/url"
	"os"
	"runtime"
	"time"

	"notification-service/internal/config"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/instrumentation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
	"go.opentelemetry.io/otel/trace"
)

var (
	// Global tracer and meter
	Tracer trace.Tracer
	Meter  metric.Meter

	// Custom metrics - Counters
	NotificationsSentCounter    metric.Int64Counter
	NotificationErrorsCounter   metric.Int64Counter
	EventHubMessagesReceived    metric.Int64Counter
	EventHubMessagesProcessed   metric.Int64Counter
	EventHubProcessingErrors    metric.Int64Counter
	WebSocketMessagesSent       metric.Int64Counter
	WebSocketMessagesErrors     metric.Int64Counter

	// Custom metrics - Histograms
	NotificationDeliveryHist    metric.Float64Histogram
	EventProcessingDuration     metric.Float64Histogram
	EventHubConsumeDuration     metric.Float64Histogram
	WebSocketDeliveryDuration   metric.Float64Histogram

	// Custom metrics - UpDownCounters
	ActiveWebSocketConnections  metric.Int64UpDownCounter
	EventHubActivePartitions    metric.Int64UpDownCounter

	// Custom metrics - Observable Gauges
	QueueSizeGauge             metric.Int64ObservableGauge
)

// InitTelemetry initializes OpenTelemetry with OTLP exporters
func InitTelemetry(cfg *config.Config) (func(context.Context) error, error) {
	ctx := context.Background()

	// Create resource with comprehensive attributes
	res, err := newResource(cfg)
	if err != nil {
		log.Printf("Warning: Failed to create resource: %v", err)
		// Continue with default resource
		res = resource.Default()
	}

	// Initialize trace provider
	traceProvider, err := newTraceProvider(ctx, cfg, res)
	if err != nil {
		return nil, fmt.Errorf("failed to create trace provider: %w", err)
	}
	otel.SetTracerProvider(traceProvider)

	// Initialize metric provider
	meterProvider, err := newMeterProvider(ctx, cfg, res)
	if err != nil {
		return nil, fmt.Errorf("failed to create meter provider: %w", err)
	}
	otel.SetMeterProvider(meterProvider)

	// Initialize log provider
	logProvider, err := newLogProvider(ctx, cfg, res)
	if err != nil {
		return nil, fmt.Errorf("failed to create log provider: %w", err)
	}

	// Set text map propagator for distributed tracing
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	// Initialize global tracer and meter
	Tracer = otel.Tracer("notification-service",
		trace.WithInstrumentationVersion("1.0.0"),
		trace.WithSchemaURL(semconv.SchemaURL),
	)

	Meter = otel.Meter("notification-service",
		metric.WithInstrumentationVersion("1.0.0"),
		metric.WithSchemaURL(semconv.SchemaURL),
	)

	// Initialize custom metrics
	if err := initMetrics(); err != nil {
		return nil, fmt.Errorf("failed to initialize metrics: %w", err)
	}

	log.Println("✓ OpenTelemetry initialized successfully")
	log.Printf("  - Service: %s", cfg.ServiceName)
	log.Printf("  - OTLP Traces Endpoint: %s", cfg.OTLPTracesEndpoint)
	log.Printf("  - OTLP Metrics Endpoint: %s", cfg.OTLPMetricsEndpoint)
	log.Printf("  - OTLP Logs Endpoint: %s", cfg.OTLPLogsEndpoint)
	log.Printf("  - Environment: %s", cfg.Environment)

	// Return shutdown function
	return func(ctx context.Context) error {
		log.Println("Shutting down OpenTelemetry...")
		
		// Shutdown tracer provider with timeout
		shutdownCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
		defer cancel()
		
		if err := traceProvider.Shutdown(shutdownCtx); err != nil {
			log.Printf("Error shutting down trace provider: %v", err)
		}
		
		if err := meterProvider.Shutdown(shutdownCtx); err != nil {
			log.Printf("Error shutting down meter provider: %v", err)
		}
		
		if logProvider != nil {
			if err := logProvider.Shutdown(shutdownCtx); err != nil {
				log.Printf("Error shutting down log provider: %v", err)
			}
		}
		
		log.Println("✓ OpenTelemetry shutdown complete")
		return nil
	}, nil
}

// newResource creates a resource with comprehensive service attributes
func newResource(cfg *config.Config) (*resource.Resource, error) {
	hostname, _ := os.Hostname()
	applicationId := os.Getenv("APPLICATION_INSIGHTS_APPLICATION_ID")
	if applicationId == "" {
		applicationId = "unknown"
	}
	
	// First, get the default resource which includes OTEL_RESOURCE_ATTRIBUTES from environment
	defaultRes := resource.Default()
	
	// Then create our service-specific attributes
	serviceRes := resource.NewWithAttributes(
		semconv.SchemaURL,
		// Service attributes - these should override any from environment
		semconv.ServiceName(cfg.ServiceName),
		semconv.ServiceVersion("1.0.0"),
		semconv.ServiceInstanceID(hostname),
		
		// Deployment attributes
		semconv.DeploymentEnvironment(cfg.Environment),
		attribute.String("deployment.platform", "kubernetes"),
		attribute.String("deployment.cloud", "azure"),
		
		// Runtime attributes
		attribute.String("telemetry.sdk.language", "go"),
		attribute.String("telemetry.sdk.version", runtime.Version()),
		
		// Custom attributes
		attribute.String("service.namespace", "otel-demo"),
		attribute.String("service.component", "notification-service"),
		attribute.String("service.description", "Real-time notification service with Event Hub and WebSocket"),
		attribute.String("microsoft.applicationId", applicationId),
	)
	
	// Merge with service attributes taking precedence (listed second)
	return resource.Merge(defaultRes, serviceRes)
}

// newTraceProvider creates a trace provider with OTLP HTTP exporter
func newTraceProvider(ctx context.Context, cfg *config.Config, res *resource.Resource) (*sdktrace.TracerProvider, error) {
	// If no OTLP endpoint configured, use noop provider
	if cfg.OTLPTracesEndpoint == "" {
		log.Println("Warning: No OTLP traces endpoint configured, traces will not be exported")
		return sdktrace.NewTracerProvider(
			sdktrace.WithResource(res),
		), nil
	}

	// Create OTLP HTTP trace exporter
	// Use minimal configuration for Azure Monitor compatibility
	traceExporter, err := otlptracehttp.New(
		ctx,
		otlptracehttp.WithEndpointURL(cfg.OTLPTracesEndpoint), // Use full URL directly
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create trace exporter: %w", err)
	}

	// Create trace provider with batch processor
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter,
			sdktrace.WithMaxExportBatchSize(512),
			sdktrace.WithBatchTimeout(5*time.Second),
			sdktrace.WithMaxQueueSize(2048),
		),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()), // Sample all traces for demo
	)

	return tp, nil
}

// newMeterProvider creates a meter provider with OTLP HTTP exporter
func newMeterProvider(ctx context.Context, cfg *config.Config, res *resource.Resource) (*sdkmetric.MeterProvider, error) {
	// If no OTLP endpoint configured, use noop provider
	if cfg.OTLPMetricsEndpoint == "" {
		log.Println("Warning: No OTLP metrics endpoint configured, metrics will not be exported")
		return sdkmetric.NewMeterProvider(
			sdkmetric.WithResource(res),
		), nil
	}

	// Create OTLP HTTP metric exporter
	// Use minimal configuration for Azure Monitor compatibility
	metricExporter, err := otlpmetrichttp.New(
		ctx,
		otlpmetrichttp.WithEndpointURL(cfg.OTLPMetricsEndpoint), // Use full URL directly
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create metric exporter: %w", err)
	}

	// Create meter provider with periodic reader
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(
			sdkmetric.NewPeriodicReader(metricExporter,
				sdkmetric.WithInterval(15*time.Second), // Export every 15 seconds
			),
		),
		sdkmetric.WithResource(res),
		// Define custom histogram buckets for latency metrics
		sdkmetric.WithView(
			sdkmetric.NewView(
				sdkmetric.Instrument{Name: "notification.delivery.duration"},
				sdkmetric.Stream{
					Aggregation: sdkmetric.AggregationExplicitBucketHistogram{
						Boundaries: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
					},
				},
			),
		),
		sdkmetric.WithView(
			sdkmetric.NewView(
				sdkmetric.Instrument{Name: "event.processing.duration"},
				sdkmetric.Stream{
					Aggregation: sdkmetric.AggregationExplicitBucketHistogram{
						Boundaries: []float64{0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5},
					},
				},
			),
		),
	)

	return mp, nil
}

// newLogProvider creates a log provider with OTLP HTTP exporter
func newLogProvider(ctx context.Context, cfg *config.Config, res *resource.Resource) (*sdklog.LoggerProvider, error) {
	// If no OTLP endpoint configured, return nil (logs won't be exported)
	if cfg.OTLPLogsEndpoint == "" {
		log.Println("Warning: No OTLP logs endpoint configured, logs will not be exported")
		return nil, nil
	}

	// Parse endpoint to extract host:port and path
	// Azure Monitor injects complete URL like "http://10.0.2.62:28331/v1/logs"
	// But Go OTLP HTTP exporter WithEndpoint() expects just "host:port" and WithURLPath() for path
	parsedURL, err := url.Parse(cfg.OTLPLogsEndpoint)
	if err != nil {
		return nil, fmt.Errorf("failed to parse logs endpoint: %w", err)
	}

	// Create OTLP HTTP log exporter
	logExporter, err := otlploghttp.New(
		ctx,
		otlploghttp.WithEndpoint(parsedURL.Host),  // Just host:port
		otlploghttp.WithURLPath(parsedURL.Path),   // Explicit path
		otlploghttp.WithInsecure(),
		otlploghttp.WithCompression(otlploghttp.GzipCompression),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create log exporter: %w", err)
	}

	// Create log provider with batch processor
	lp := sdklog.NewLoggerProvider(
		sdklog.WithProcessor(sdklog.NewBatchProcessor(logExporter)),
		sdklog.WithResource(res),
	)

	return lp, nil
}

func initMetrics() error {
	var err error

	// === Counters ===
	
	// Notification counters
	NotificationsSentCounter, err = Meter.Int64Counter(
		"notifications.sent.total",
		metric.WithDescription("Total number of notifications sent successfully"),
		metric.WithUnit("{notification}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create notifications_sent counter: %w", err)
	}

	NotificationErrorsCounter, err = Meter.Int64Counter(
		"notifications.errors.total",
		metric.WithDescription("Total number of notification delivery errors"),
		metric.WithUnit("{error}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create notification_errors counter: %w", err)
	}

	// Event Hub counters
	EventHubMessagesReceived, err = Meter.Int64Counter(
		"eventhub.messages.received.total",
		metric.WithDescription("Total number of Event Hub messages received"),
		metric.WithUnit("{message}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create eventhub_messages_received counter: %w", err)
	}

	EventHubMessagesProcessed, err = Meter.Int64Counter(
		"eventhub.messages.processed.total",
		metric.WithDescription("Total number of Event Hub messages processed successfully"),
		metric.WithUnit("{message}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create eventhub_messages_processed counter: %w", err)
	}

	EventHubProcessingErrors, err = Meter.Int64Counter(
		"eventhub.processing.errors.total",
		metric.WithDescription("Total number of Event Hub message processing errors"),
		metric.WithUnit("{error}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create eventhub_processing_errors counter: %w", err)
	}

	// WebSocket counters
	WebSocketMessagesSent, err = Meter.Int64Counter(
		"websocket.messages.sent.total",
		metric.WithDescription("Total number of WebSocket messages sent"),
		metric.WithUnit("{message}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create websocket_messages_sent counter: %w", err)
	}

	WebSocketMessagesErrors, err = Meter.Int64Counter(
		"websocket.messages.errors.total",
		metric.WithDescription("Total number of WebSocket message delivery errors"),
		metric.WithUnit("{error}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create websocket_messages_errors counter: %w", err)
	}

	// === Histograms ===
	
	NotificationDeliveryHist, err = Meter.Float64Histogram(
		"notification.delivery.duration",
		metric.WithDescription("Notification delivery duration from creation to completion"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return fmt.Errorf("failed to create notification_delivery_duration histogram: %w", err)
	}

	EventProcessingDuration, err = Meter.Float64Histogram(
		"event.processing.duration",
		metric.WithDescription("Event Hub message processing duration"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return fmt.Errorf("failed to create event_processing_duration histogram: %w", err)
	}

	EventHubConsumeDuration, err = Meter.Float64Histogram(
		"eventhub.consume.duration",
		metric.WithDescription("Time to consume messages from Event Hub partition"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return fmt.Errorf("failed to create eventhub_consume_duration histogram: %w", err)
	}

	WebSocketDeliveryDuration, err = Meter.Float64Histogram(
		"websocket.delivery.duration",
		metric.WithDescription("WebSocket message delivery duration"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return fmt.Errorf("failed to create websocket_delivery_duration histogram: %w", err)
	}

	// === UpDownCounters ===
	
	ActiveWebSocketConnections, err = Meter.Int64UpDownCounter(
		"websocket.connections.active",
		metric.WithDescription("Number of active WebSocket connections"),
		metric.WithUnit("{connection}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create active_websocket_connections counter: %w", err)
	}

	EventHubActivePartitions, err = Meter.Int64UpDownCounter(
		"eventhub.partitions.active",
		metric.WithDescription("Number of active Event Hub partitions being processed"),
		metric.WithUnit("{partition}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create eventhub_active_partitions counter: %w", err)
	}

	// === Observable Gauges ===
	
	QueueSizeGauge, err = Meter.Int64ObservableGauge(
		"notification.queue.size",
		metric.WithDescription("Current notification queue size"),
		metric.WithUnit("{notification}"),
	)
	if err != nil {
		return fmt.Errorf("failed to create notification_queue_size gauge: %w", err)
	}

	log.Println("✓ Custom metrics initialized successfully")
	return nil
}

// GetScope returns the current instrumentation scope
func GetScope() instrumentation.Scope {
	return instrumentation.Scope{
		Name:      "notification-service",
		Version:   "1.0.0",
		SchemaURL: semconv.SchemaURL,
	}
}

// RecordNotificationSent records a successful notification delivery
func RecordNotificationSent(ctx context.Context, notificationType string, channel string) {
	if NotificationsSentCounter != nil {
		NotificationsSentCounter.Add(ctx, 1,
			metric.WithAttributes(
				attribute.String("notification.type", notificationType),
				attribute.String("notification.channel", channel),
			),
		)
	}
}

// RecordNotificationError records a notification delivery error
func RecordNotificationError(ctx context.Context, notificationType string, channel string, errorType string) {
	if NotificationErrorsCounter != nil {
		NotificationErrorsCounter.Add(ctx, 1,
			metric.WithAttributes(
				attribute.String("notification.type", notificationType),
				attribute.String("notification.channel", channel),
				attribute.String("error.type", errorType),
			),
		)
	}
}

// RecordEventHubMessage records Event Hub message metrics
func RecordEventHubMessage(ctx context.Context, partitionID string, eventType string, success bool, duration float64) {
	attrs := []attribute.KeyValue{
		attribute.String("eventhub.partition_id", partitionID),
		attribute.String("event.type", eventType),
	}

	if EventHubMessagesReceived != nil {
		EventHubMessagesReceived.Add(ctx, 1, metric.WithAttributes(attrs...))
	}

	if success {
		if EventHubMessagesProcessed != nil {
			EventHubMessagesProcessed.Add(ctx, 1, metric.WithAttributes(attrs...))
		}
	} else {
		if EventHubProcessingErrors != nil {
			EventHubProcessingErrors.Add(ctx, 1, metric.WithAttributes(attrs...))
		}
	}

	if EventProcessingDuration != nil && duration > 0 {
		EventProcessingDuration.Record(ctx, duration, metric.WithAttributes(attrs...))
	}
}

// RecordWebSocketMessage records WebSocket message metrics
func RecordWebSocketMessage(ctx context.Context, customerID string, messageType string, success bool, duration float64) {
	attrs := []attribute.KeyValue{
		attribute.String("message.type", messageType),
		attribute.Bool("delivery.success", success),
	}

	if success {
		if WebSocketMessagesSent != nil {
			WebSocketMessagesSent.Add(ctx, 1, metric.WithAttributes(attrs...))
		}
	} else {
		if WebSocketMessagesErrors != nil {
			WebSocketMessagesErrors.Add(ctx, 1, metric.WithAttributes(attrs...))
		}
	}

	if WebSocketDeliveryDuration != nil && duration > 0 {
		WebSocketDeliveryDuration.Record(ctx, duration, metric.WithAttributes(attrs...))
	}
}
