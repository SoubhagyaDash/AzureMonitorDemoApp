# Payment Service

A .NET Core 8.0 payment processing service designed for AKS deployment with auto-instrumentation capabilities.

## Overview

The Payment Service handles all payment processing operations for the eCommerce platform, including:
- Credit card, PayPal, and bank transfer processing
- Payment status tracking and management
- Refund and cancellation operations
- Real-time payment event publishing

## Key Features

- **Payment Processing**: Support for multiple payment methods with realistic failure simulation
- **Refund Management**: Full and partial refund capabilities
- **Event Publishing**: Real-time payment events via Azure EventHub
- **Caching**: Redis-based caching for improved performance
- **Failure Injection**: Configurable latency, error, and timeout injection for demo purposes
- **Health Checks**: Built-in health monitoring endpoints

## Architecture

- **Framework**: .NET Core 8.0 Web API
- **Database**: Entity Framework with In-Memory provider
- **Caching**: Redis distributed cache
- **Messaging**: Azure EventHub for event publishing
- **Resilience**: Polly for HTTP client resilience patterns

## OpenTelemetry Strategy

**Uninstrumented by Design**: This service is intentionally not instrumented with OpenTelemetry SDK to demonstrate **AKS auto-instrumentation** capabilities. When deployed to Azure Kubernetes Service, telemetry will be automatically collected through:

- Auto-instrumentation agents
- Service mesh integration
- Platform-level observability

## API Endpoints

### Payment Operations
- `POST /api/payments` - Process a new payment
- `GET /api/payments/{id}` - Get payment details
- `GET /api/payments/order/{orderId}` - Get payments for an order
- `GET /api/payments/customer/{customerId}` - Get customer payments

### Payment Management
- `POST /api/payments/{id}/refund` - Process refund
- `POST /api/payments/{id}/cancel` - Cancel payment

### Health & Monitoring
- `GET /health` - Health check endpoint

## Configuration

### Environment Variables
- `ConnectionStrings__EventHub`: Azure EventHub connection string
- `ConnectionStrings__Redis`: Redis connection string
- `EventHub__PaymentEvents`: EventHub name for payment events

### Failure Injection
```json
{
  "FailureInjection": {
    "Enabled": true,
    "LatencyMs": 500,
    "ErrorRate": 0.05,
    "TimeoutRate": 0.01
  }
}
```

## Development

### Prerequisites
- .NET 8.0 SDK
- Redis (for caching)
- Azure EventHub (for event publishing)

### Running Locally
```bash
cd services/payment-service
dotnet restore
dotnet run
```

### Docker Build
```bash
docker build -t payment-service .
```

## Integration

The Payment Service integrates with:
- **API Gateway**: Receives payment requests from the main API
- **Order Service**: Validates order details before processing
- **Event Processor**: Publishes payment events for downstream processing
- **Notification Service**: Sends payment status updates via WebSocket

## Demo Scenarios

1. **Successful Payment Flow**: Complete payment processing with event publishing
2. **Payment Failures**: Simulated card declines, insufficient funds, etc.
3. **Refund Processing**: Full and partial refund operations
4. **High Load**: Performance testing with concurrent payment processing
5. **Failure Recovery**: Resilience patterns with retry and circuit breaker

## Deployment

Designed for Azure Kubernetes Service (AKS) deployment with:
- Horizontal Pod Autoscaling
- Service mesh integration
- Auto-instrumentation for observability
- Blue-green deployment capabilities