# Notification Service

A Go-based microservice that handles real-time customer notifications via Event Hub consumption and WebSocket delivery.

## Features

### ✅ Implemented
- **Event Hub Consumer**: Real-time processing of order events from Azure Event Hub
- **WebSocket Server**: Real-time bidirectional communication with frontend clients
- **Multi-Partition Support**: Concurrent processing of all Event Hub partitions
- **OpenTelemetry Integration**: Full instrumentation for traces, metrics, and logs
- **Health Checks**: Kubernetes-ready liveness and readiness endpoints
- **Failure Injection**: Built-in chaos engineering for testing resilience

### ⚠️ Stub Implementations
- **Email Service**: Structure ready, requires SMTP configuration
- **SMS Service**: Structure ready, requires Twilio configuration
- **Push Notifications**: Structure ready, requires FCM/APNs configuration
- **Database Persistence**: Structure ready, requires PostgreSQL setup

## Event Processing

The service consumes events from Azure Event Hub and processes the following event types:

### OrderCreated
```json
{
  "EventType": "OrderCreated",
  "OrderId": "550e8400-e29b-41d4-a716-446655440000",
  "CustomerId": "customer-001",
  "ProductId": 1,
  "Quantity": 2,
  "TotalAmount": 59.98,
  "Timestamp": "2025-11-04T20:30:00Z"
}
```
**Notification**: "Your order #550e8400 has been confirmed! Total: $59.98"

### OrderStatusUpdated
```json
{
  "EventType": "OrderStatusUpdated",
  "OrderId": "550e8400-e29b-41d4-a716-446655440000",
  "CustomerId": "customer-001",
  "Status": "Shipped",
  "Timestamp": "2025-11-04T21:00:00Z"
}
```
**Notification**: "Order #550e8400 status: Shipped"

### PaymentProcessed
```json
{
  "EventType": "PaymentProcessed",
  "OrderId": "550e8400-e29b-41d4-a716-446655440000",
  "CustomerId": "customer-001",
  "TotalAmount": 59.98,
  "Timestamp": "2025-11-04T20:31:00Z"
}
```
**Notification**: "Payment of $59.98 processed for order #550e8400"

## WebSocket Protocol

### Connection
```javascript
const ws = new WebSocket('ws://notification-service:8080/ws?customerId=customer-001');
```

### Message Format
```json
{
  "type": "notification",
  "timestamp": "2025-11-04T20:30:00Z",
  "data": {
    "type": "order_created",
    "orderId": "550e8400-e29b-41d4-a716-446655440000",
    "customerId": "customer-001",
    "subject": "Order Confirmed",
    "message": "Your order #550e8400 has been confirmed! Total: $59.98",
    "totalAmount": 59.98,
    "productId": 1,
    "quantity": 2
  }
}
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | HTTP server port |
| `ENVIRONMENT` | `development` | Environment name |
| `EVENT_HUB_CONNECTION_STRING` | *(required)* | Azure Event Hub connection string |
| `EVENT_HUB_NAME` | `orders` | Event Hub name to consume from |
| `REDIS_URL` | `redis://localhost:6379` | Redis connection URL |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4317` | OpenTelemetry collector endpoint |
| `OTEL_SERVICE_NAME` | `notification-service` | Service name in telemetry |

### Kubernetes Deployment

```bash
kubectl apply -f k8s/notification-service.yaml
```

The service requires secrets to be configured:
- `shared-secrets`: Contains `eventhub-connection-string` and `redis-connection-string`
- `appinsights-connection`: Contains Application Insights connection string

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│ Order       │────>│ Event Hub    │────>│ Notification    │
│ Service     │     │ (orders)     │     │ Service         │
└─────────────┘     └──────────────┘     └────────┬────────┘
                                                   │
                                                   │ WebSocket
                                                   │
                                          ┌────────▼────────┐
                                          │ Frontend        │
                                          │ (ECommerceStore)│
                                          └─────────────────┘
```

## Event Processing Flow

1. **Event Hub Consumption**:
   - Service connects to all partitions on startup
   - Processes events from earliest available (for demo)
   - Each partition processed in separate goroutine

2. **Event Parsing**:
   - JSON deserialization with validation
   - Event type routing

3. **Notification Creation**:
   - Builds WebSocket message based on event type
   - Includes all relevant order/payment details

4. **WebSocket Delivery**:
   - Sends to specific customer by ID
   - Non-blocking (failures don't fail event processing)
   - Frontend displays Material-UI snackbar

## API Endpoints

| Endpoint | Method | Description | Status |
|----------|--------|-------------|--------|
| `/health` | GET | Basic health check | ✅ Implemented |
| `/health/ready` | GET | Readiness probe | ✅ Implemented |
| `/health/live` | GET | Liveness probe | ✅ Implemented |
| `/ws` | GET | WebSocket connection | ✅ Implemented |
| `/api/v1/notifications` | POST | Create notification | ⚠️ Stub |
| `/api/v1/notifications` | GET | List notifications | ⚠️ Stub |
| `/api/v1/notifications/:id` | GET | Get notification | ⚠️ Stub |
| `/api/v1/analytics/delivery-stats` | GET | Delivery statistics | ⚠️ Stub |

## Development

### Prerequisites
- Go 1.21+
- Azure Event Hub instance
- Redis instance (optional)
- Docker (for containerization)

### Local Development
```bash
# Set environment variables
export EVENT_HUB_CONNECTION_STRING="Endpoint=sb://..."
export EVENT_HUB_NAME="orders"
export PORT="8080"

# Run locally
cd services/notification-service
go run main.go
```

### Build Docker Image
```bash
docker build -t notification-service:latest .
```

### Testing Event Hub Integration
```bash
# The service will log received events:
# INFO: Received event from partition 0: 256 bytes
# INFO: Processing OrderCreated event for Order ID: 550e8400, Customer ID: customer-001
# INFO: Sent OrderCreated notification to customer customer-001 via WebSocket
```

## Deployment

Deploy with notification service enabled:
```powershell
cd deploy
.\deploy-environment.ps1 -IncludeNotificationService
```

This will:
1. Build the notification-service Docker image
2. Push to Azure Container Registry
3. Deploy to AKS with 2 replicas
4. Configure Event Hub and Redis connections
5. Frontend automatically connects via WebSocket

## Monitoring

The service is fully instrumented with OpenTelemetry:
- **Traces**: HTTP requests, Event Hub consumption, WebSocket operations
- **Metrics**: Request counts, latencies, active connections
- **Logs**: Structured logging with context

View in Azure Application Insights:
- Transaction search for distributed traces
- Live metrics for real-time monitoring
- Application map for service topology

## Future Enhancements

To make this production-ready:
1. **Implement Email Service**: Configure SMTP and implement actual email sending
2. **Implement SMS Service**: Integrate Twilio or Azure Communication Services
3. **Add Database Persistence**: Store notifications in PostgreSQL
4. **Implement Checkpointing**: Use Azure Blob Storage for Event Hub checkpoints
5. **Add Retry Logic**: Implement exponential backoff for failed deliveries
6. **Customer Preferences**: Honor customer notification preferences
7. **Template Engine**: Use templates for notification content
8. **Rate Limiting**: Prevent notification spam

## License

Part of the Azure Monitor OpenTelemetry Demo Application.
