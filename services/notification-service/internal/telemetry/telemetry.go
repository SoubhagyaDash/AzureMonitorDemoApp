package telemetry

import (
	"context"
	"time"

	"notification-service/internal/config"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/instrumentation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.17.0"
	"go.opentelemetry.io/otel/trace"
)

var (
	// Global tracer and meter
	Tracer trace.Tracer
	Meter  metric.Meter

	// Custom metrics
	NotificationsSentCounter    metric.Int64Counter
	NotificationDeliveryHist    metric.Float64Histogram
	NotificationErrorsCounter   metric.Int64Counter
	ActiveWebSocketConnections  metric.Int64UpDownCounter
	EventProcessingDuration     metric.Float64Histogram
	QueueSizeGauge             metric.Int64ObservableGauge
)

// InitTelemetry initializes OpenTelemetry with OTLP exporters
func InitTelemetry(cfg *config.Config) (func(context.Context) error, error) {
	// Create resource
	res := resource.NewWithAttributes(
		semconv.SchemaURL,
		semconv.ServiceName(cfg.ServiceName),
		semconv.ServiceVersion("1.0.0"),
		semconv.DeploymentEnvironment(cfg.Environment),
		semconv.ServiceInstanceID("notification-service-1"),
	)

	// Initialize trace provider
	traceExporter, err := otlptracehttp.New(
		context.Background(),
		otlptracehttp.WithEndpoint(cfg.OTLPEndpoint),
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	tracerProvider := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(traceExporter),
		sdktrace.WithResource(res),
		sdktrace.WithSampler(sdktrace.AlwaysSample()),
	)

	otel.SetTracerProvider(tracerProvider)

	// Initialize metric provider
	metricExporter, err := otlpmetrichttp.New(
		context.Background(),
		otlpmetrichttp.WithEndpoint(cfg.OTLPEndpoint),
		otlpmetrichttp.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	meterProvider := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExporter,
			sdkmetric.WithInterval(10*time.Second))),
		sdkmetric.WithResource(res),
		sdkmetric.WithView(sdkmetric.NewView(
			sdkmetric.Instrument{Name: "notification_delivery_duration"},
			sdkmetric.Stream{
				Aggregation: sdkmetric.AggregationExplicitBucketHistogram{
					Boundaries: []float64{0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10},
				},
			},
		)),
	)

	otel.SetMeterProvider(meterProvider)

	// Set text map propagator
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
		return nil, err
	}

	// Return shutdown function
	return func(ctx context.Context) error {
		if err := tracerProvider.Shutdown(ctx); err != nil {
			return err
		}
		return meterProvider.Shutdown(ctx)
	}, nil
}

func initMetrics() error {
	var err error

	// Counters
	NotificationsSentCounter, err = Meter.Int64Counter(
		"notifications_sent_total",
		metric.WithDescription("Total number of notifications sent"),
		metric.WithUnit("1"),
	)
	if err != nil {
		return err
	}

	NotificationErrorsCounter, err = Meter.Int64Counter(
		"notification_errors_total",
		metric.WithDescription("Total number of notification errors"),
		metric.WithUnit("1"),
	)
	if err != nil {
		return err
	}

	// Histograms
	NotificationDeliveryHist, err = Meter.Float64Histogram(
		"notification_delivery_duration",
		metric.WithDescription("Notification delivery duration in seconds"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return err
	}

	EventProcessingDuration, err = Meter.Float64Histogram(
		"event_processing_duration",
		metric.WithDescription("Event processing duration in seconds"),
		metric.WithUnit("s"),
	)
	if err != nil {
		return err
	}

	// Up/Down counters
	ActiveWebSocketConnections, err = Meter.Int64UpDownCounter(
		"active_websocket_connections",
		metric.WithDescription("Number of active WebSocket connections"),
		metric.WithUnit("1"),
	)
	if err != nil {
		return err
	}

	// Observable gauges
	QueueSizeGauge, err = Meter.Int64ObservableGauge(
		"notification_queue_size",
		metric.WithDescription("Current notification queue size"),
		metric.WithUnit("1"),
	)
	if err != nil {
		return err
	}

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