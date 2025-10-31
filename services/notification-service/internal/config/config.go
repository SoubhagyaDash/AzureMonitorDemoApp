package config

import (
	"os"
	"strconv"
)

type Config struct {
	// Server configuration
	Port        string
	Environment string

	// OpenTelemetry configuration
	OTLPEndpoint string
	ServiceName  string

	// Redis configuration
	RedisURL string

	// Event Hub configuration
	EventHubConnectionString string
	EventHubName             string

	// Database configuration
	DatabaseURL string

	// Email service configuration
	SMTPHost     string
	SMTPPort     int
	SMTPUsername string
	SMTPPassword string
	FromEmail    string

	// SMS service configuration
	TwilioAccountSID  string
	TwilioAuthToken   string
	TwilioPhoneNumber string

	// Push notification configuration
	FCMServerKey string
	APNSKeyID    string
	APNSTeamID   string

	// Webhook configuration
	WebhookRetries int
	WebhookTimeout int

	// Failure injection configuration
	FailureInjectionEnabled bool
	LatencyProbability      float64
	ErrorProbability        float64
	LatencyMinMs            int
	LatencyMaxMs            int
}

func Load() *Config {
	return &Config{
		// Server
		Port:        getEnv("PORT", "9000"),
		Environment: getEnv("ENVIRONMENT", "development"),

		// OpenTelemetry
		OTLPEndpoint: getEnv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4317"),
		ServiceName:  getEnv("OTEL_SERVICE_NAME", "notification-service"),

		// Redis
		RedisURL: getEnv("REDIS_URL", "redis://localhost:6379"),

		// Event Hub
		EventHubConnectionString: getEnv("EVENT_HUB_CONNECTION_STRING", ""),
		EventHubName:             getEnv("EVENT_HUB_NAME", "orders"),

		// Database
		DatabaseURL: getEnv("DATABASE_URL", "postgres://localhost/notifications?sslmode=disable"),

		// Email
		SMTPHost:     getEnv("SMTP_HOST", "smtp.gmail.com"),
		SMTPPort:     getEnvAsInt("SMTP_PORT", 587),
		SMTPUsername: getEnv("SMTP_USERNAME", ""),
		SMTPPassword: getEnv("SMTP_PASSWORD", ""),
		FromEmail:    getEnv("FROM_EMAIL", "noreply@example.com"),

		// SMS
		TwilioAccountSID:  getEnv("TWILIO_ACCOUNT_SID", ""),
		TwilioAuthToken:   getEnv("TWILIO_AUTH_TOKEN", ""),
		TwilioPhoneNumber: getEnv("TWILIO_PHONE_NUMBER", ""),

		// Push notifications
		FCMServerKey: getEnv("FCM_SERVER_KEY", ""),
		APNSKeyID:    getEnv("APNS_KEY_ID", ""),
		APNSTeamID:   getEnv("APNS_TEAM_ID", ""),

		// Webhooks
		WebhookRetries: getEnvAsInt("WEBHOOK_RETRIES", 3),
		WebhookTimeout: getEnvAsInt("WEBHOOK_TIMEOUT", 30),

		// Failure injection
		FailureInjectionEnabled: getEnvAsBool("FAILURE_INJECTION_ENABLED", true),
		LatencyProbability:      getEnvAsFloat("LATENCY_PROBABILITY", 0.1),
		ErrorProbability:        getEnvAsFloat("ERROR_PROBABILITY", 0.05),
		LatencyMinMs:            getEnvAsInt("LATENCY_MIN_MS", 100),
		LatencyMaxMs:            getEnvAsInt("LATENCY_MAX_MS", 2000),
	}
}

func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}

func getEnvAsBool(key string, defaultValue bool) bool {
	if value := os.Getenv(key); value != "" {
		if boolValue, err := strconv.ParseBool(value); err == nil {
			return boolValue
		}
	}
	return defaultValue
}

func getEnvAsFloat(key string, defaultValue float64) float64 {
	if value := os.Getenv(key); value != "" {
		if floatValue, err := strconv.ParseFloat(value, 64); err == nil {
			return floatValue
		}
	}
	return defaultValue
}