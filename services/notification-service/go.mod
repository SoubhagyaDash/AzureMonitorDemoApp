module notification-service

go 1.22

require (
	github.com/gin-gonic/gin v1.10.0
	github.com/gorilla/websocket v1.5.1
	
	// OpenTelemetry Core - Latest stable v1.31.0
	go.opentelemetry.io/otel v1.31.0
	go.opentelemetry.io/otel/metric v1.31.0
	go.opentelemetry.io/otel/sdk v1.31.0
	go.opentelemetry.io/otel/sdk/metric v1.31.0
	go.opentelemetry.io/otel/trace v1.31.0
	
	// OTLP Exporters
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp v1.31.0
	go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp v1.31.0
	go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc v1.31.0
	go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploghttp v0.7.0
	go.opentelemetry.io/otel/exporters/stdout/stdouttrace v1.31.0
	go.opentelemetry.io/otel/exporters/stdout/stdoutmetric v1.31.0
	go.opentelemetry.io/otel/log v0.7.0
	go.opentelemetry.io/otel/sdk/log v0.7.0
	
	// Instrumentation Libraries
	go.opentelemetry.io/contrib/instrumentation/github.com/gin-gonic/gin/otelgin v0.56.0
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.56.0
	
	// Azure SDKs
	github.com/Azure/azure-sdk-for-go/sdk/messaging/azservicebus v1.7.1
	github.com/Azure/azure-sdk-for-go/sdk/messaging/azeventhubs v1.2.1
	github.com/Azure/azure-sdk-for-go/sdk/azcore v1.13.0
	
	// Other dependencies
	github.com/go-redis/redis/v8 v8.11.5
	github.com/lib/pq v1.10.9
	github.com/golang-migrate/migrate/v4 v4.17.1
	github.com/prometheus/client_golang v1.19.1
	github.com/sirupsen/logrus v1.9.3
)