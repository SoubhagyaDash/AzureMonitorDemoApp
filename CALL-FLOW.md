# OpenTelemetry Demo Application - Component Call Graph

This document describes the component interactions and data flow in the OpenTelemetry demo application.

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              END USERS                                    │
│                          (Browser/Mobile)                                 │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                         FRONTEND (React)                                  │
│                     Azure App Service / CDN                               │
│  • Service Health Dashboard                                              │
│  • Order Management UI                                                   │
│  • Inventory Viewer                                                      │
└───────────────┬───────────────────────────┬──────────────────────────────┘
                │                           │
                │ All requests go through   │ Direct calls (when configured)
                │ API Gateway               │
                ▼                           ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                    API GATEWAY (.NET 8)                                   │
│                      Azure VM (VM2)                                       │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │ Controllers:                                                     │    │
│  │  • /api/orders         → OrdersController                       │    │
│  │  • /api/payments       → PaymentsController                     │    │
│  │  • /api/inventory      → InventoryController                    │    │
│  │  • /api/health/all     → HealthController                       │    │
│  │  • /api/health/{name}  → HealthController                       │    │
│  └─────────────────────────────────────────────────────────────────┘    │
└─┬────────┬────────┬─────────┬─────────┬──────────┬────────────────────┬─┘
  │        │        │         │         │          │                    │
  │        │        │         │         │          │                    │
  ▼        ▼        ▼         ▼         ▼          ▼                    ▼
┌────┐  ┌────┐  ┌─────┐   ┌─────┐  ┌─────┐    ┌──────┐          ┌──────────┐
│SQL │  │Redis│ │Event│   │Order│  │Pay- │    │Inven-│          │Notifica- │
│DB  │  │Cache│ │Hub  │   │Svc  │  │ment │    │tory  │          │tion Svc  │
│    │  │     │ │     │   │     │  │Svc  │    │Svc   │          │          │
└────┘  └────┘  └──┬──┘   └──┬──┘  └──┬──┘    └──┬───┘          └────┬─────┘
                   │         │        │           │                    │
                   │         │        │           │                    │
        ┌──────────┴─────────┴────────┴───────────┴────────────────────┤
        │                                                               │
        ▼                                                               ▼
┌────────────────┐
│ ORDER SERVICE  │
│   (Java 17)    │
│   AKS Pod      │
│                │
│ • REST API     │
│ • SQL Access   │
│ • EventHub     │
│   Publisher    │
└────────┬───────┘
         │
         │ Publishes "OrderCreated"
         │ events
         │
         ▼
┌────────────────────────────────────────────────────────────────────────────┐
│                         AZURE EVENT HUB                                    │
│  Topics: "orders", "payment-events", "notifications"                      │
└──────────┬──────────────────────────────────────┬──────────────────────────┘
           │                                      │
           │ Consumes "orders",                   │ Consumes "notifications"
           │ "payment-events"                     │ events
           │                                      │
           ▼                                      ▼
┌──────────────────────────────────┐   ┌─────────────────────────────┐
│   EVENT PROCESSOR (Python)       │   │  NOTIFICATION SERVICE       │
│        AKS Pod                   │   │      (Golang)               │
│                                  │   │      AKS Pod                │
│  • Consumes from EventHub        │   │                             │
│  • Processes order events        │   │  • Consumes from EventHub   │
│  • Stores in Cosmos DB           │   │  • WebSocket Hub            │
│  • Updates Redis cache           │   │  • Email/SMS/Push           │
│  • Publishes to notifications    │   │  • Real-time Broadcasts     │
│    topic                         │   │                             │
└──┬────────────────────┬──────────┘   └─────────────────────────────┘
   │                    │
   │                    │
   ▼                    ▼
┌──────────┐     ┌──────────────┐
│  COSMOS  │     │  REDIS CACHE │
│    DB    │     │              │
│          │     │  (Shared)    │
│ Event    │     │              │
│ Store    │     │              │
└──────────┘     └──────────────┘


┌──────────────────────────────────────────────────────────────────────────┐
│                    PAYMENT SERVICE (.NET 8)                               │
│                         AKS Pod                                           │
│                                                                           │
│  • Payment Processing                                                    │
│  • Redis Cache                                                           │
│  • EventHub Publisher                                                    │
│  • In-Memory DB (EF Core)                                                │
└───────────────────────────────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────────────┐
│                 INVENTORY SERVICE (Node.js 18)                            │
│                      Azure VM (VM1)                                       │
│                                                                           │
│  • Product Inventory API                                                 │
│  • Stock Management                                                      │
│  • MongoDB/In-Memory                                                     │
└───────────────────────────────────────────────────────────────────────────┘


┌──────────────────────────────────────────────────────────────────────────┐
│              SYNTHETIC TRAFFIC FUNCTION (.NET)                            │
│                   Azure Function (Timer)                                  │
│                                                                           │
│  • Generates test traffic                                                │
│  • Calls API Gateway                                                     │
│  • Creates random orders                                                 │
└───────────────────────┬───────────────────────────────────────────────────┘
                        │
                        └──────► API Gateway (periodic calls)
```

---

## Detailed Call Flows

### 1. Create Order Flow

**Complete transaction from frontend to all backend services:**

```
Frontend
  └─► API Gateway POST /api/orders
      │
      ├─► Cache Check (Redis)
      │   └─► Skip for POST requests
      │
      ├─► Order Service POST /api/orders/process
      │   ├─► Validate order data
      │   ├─► Save to SQL Database
      │   ├─► Generate order ID
      │   └─► Publish "OrderCreated" event → EventHub
      │       └─► Event data: { orderId, customerId, items, timestamp }
      │
      ├─► Payment Service POST /api/payments
      │   ├─► Process payment
      │   ├─► Save to In-Memory DB
      │   ├─► Update Redis Cache
      │   └─► Publish "PaymentCompleted" event → EventHub
      │       └─► Event data: { paymentId, orderId, amount, status }
      │
      ├─► Cache Result (Redis)
      │   └─► Store order with 5min TTL
      │
      └─► Return Response to Frontend
          └─► { orderId, status, paymentStatus, totalAmount }

Event Processing (Asynchronous):
  EventHub
    └─► Event Processor (Consumer)
        ├─► Receive "OrderCreated" event
        ├─► Store event in Cosmos DB
        │   └─► Container: Events, Partition: /orderId
        │
        ├─► Update Redis Cache
        │   └─► Cache key: order:{orderId}
        │
        └─► Publish to Notification EventHub
            └─► Notification Service
                ├─► Send Email Notification
                ├─► Send SMS (Twilio)
                ├─► Send Push Notification (FCM)
                └─► Broadcast via WebSocket
                    └─► Real-time updates to connected clients
```

**Key Points:**
- Order creation is synchronous through API Gateway
- Event processing is asynchronous via EventHub
- Multiple data stores updated (SQL, Redis, Cosmos)
- Notifications sent through multiple channels

---

### 2. Get Orders Flow

**Retrieve orders with caching:**

```
Frontend
  └─► API Gateway GET /api/orders
      │
      ├─► Redis Cache Check
      │   ├─► Key: "orders:all"
      │   │
      │   ├─► CACHE HIT
      │   │   └─► Return cached orders (5min TTL)
      │   │       └─► Response time: ~10-50ms
      │   │
      │   └─► CACHE MISS
      │       └─► Continue to Order Service ↓
      │
      ├─► Order Service GET /api/orders
      │   ├─► Query SQL Database
      │   │   └─► SELECT * FROM Orders
      │   │       ORDER BY CreatedAt DESC
      │   │
      │   └─► Return order list
      │       └─► Response time: ~100-500ms
      │
      ├─► Cache Result (Redis)
      │   └─► SET "orders:all" WITH EXPIRE 300
      │
      └─► Return to Frontend
          └─► Format: [{ orderId, customerId, status, ... }]
```

**Performance Optimization:**
- First request: ~100-500ms (database query)
- Subsequent requests: ~10-50ms (cache hit)
- Cache automatically refreshes every 5 minutes

---

### 3. Get Single Order Flow

**Retrieve specific order by ID:**

```
Frontend
  └─► API Gateway GET /api/orders/{id}
      │
      ├─► Redis Cache Check
      │   └─► Key: "order:{id}"
      │
      ├─► CACHE HIT → Return
      │
      ├─► CACHE MISS
      │   └─► Order Service GET /api/orders/{id}/status
      │       ├─► Query SQL Database
      │       │   └─► SELECT * FROM Orders WHERE Id = {id}
      │       │
      │       └─► Return order details
      │
      ├─► Update Cache
      │   └─► Store with 5min TTL
      │
      └─► Response: { orderId, status, customer, items, total }
```

---

### 4. Get Inventory Flow

**Retrieve product inventory:**

```
Frontend
  └─► API Gateway GET /api/inventory
      │
      └─► Inventory Service (VM1) GET /api/inventory
          ├─► Query MongoDB / In-Memory Store
          │   └─► Find all products with stock levels
          │
          └─► Return product list
              └─► Response time: ~50-200ms

Response Format:
[
  { id: 1, name: "Product A", price: 29.99, quantity: 100 },
  { id: 2, name: "Product B", price: 49.99, quantity: 50 },
  ...
]
```

**Notes:**
- Direct proxy from API Gateway to Inventory Service
- No caching currently implemented
- Runs on dedicated VM (VM1) on port 3001

---

### 5. Get Single Product Flow

```
Frontend
  └─► API Gateway GET /api/inventory/{id}
      │
      └─► Inventory Service GET /api/inventory/{id}
          ├─► Query for specific product
          │   └─► Find product by ID
          │
          └─► Return: { id, name, price, quantity, lastUpdated }
```

---

### 6. Health Check Flow

**Centralized health monitoring:**

```
Frontend
  └─► API Gateway GET /api/health/all
      │
      ├─► Self Health Check
      │   └─► Status: Healthy (always)
      │       Response time: 0ms
      │
      ├─► Parallel Health Checks (5s timeout each):
      │   │
      │   ├─► Order Service GET /actuator/health
      │   │   └─► Spring Boot Actuator endpoint
      │   │       └─► Checks: DB connection, disk space
      │   │
      │   ├─► Payment Service GET /health
      │   │   └─► ASP.NET Core health endpoint
      │   │       └─► Checks: Memory, DB context
      │   │
      │   ├─► Inventory Service GET /health
      │   │   └─► Express.js health endpoint
      │   │       └─► Checks: MongoDB connection
      │   │
      │   ├─► Event Processor GET /health
      │   │   └─► FastAPI health endpoint
      │   │       └─► Checks: EventHub, Cosmos, Redis
      │   │
      │   └─► Notification Service GET /health
      │       └─► Gin health endpoint (optional)
      │           └─► Checks: EventHub, Redis, Email service
      │
      └─► Aggregate Response
          └─► {
                overallStatus: "Healthy|Degraded",
                totalServices: 6,
                healthyServices: 5,
                unhealthyServices: 1,
                services: [
                  { name: "API Gateway", isHealthy: true, responseTimeMs: 0 },
                  { name: "Order Service", isHealthy: true, responseTimeMs: 145 },
                  { name: "Payment Service", isHealthy: true, responseTimeMs: 89 },
                  { name: "Inventory Service", isHealthy: false, responseTimeMs: 5000, error: "timeout" },
                  { name: "Event Processor", isHealthy: true, responseTimeMs: 234 },
                  { name: "Notification Service", isHealthy: true, responseTimeMs: 167 }
                ],
                checkedAt: "2025-11-06T10:30:00Z",
                responseTimeMs: 234
              }
```

**Individual Service Health Check:**

```
Frontend
  └─► API Gateway GET /api/health/{serviceName}
      │
      └─► Target Service GET /health
          │
          └─► Return: { name, isHealthy, status, responseTimeMs, error? }
```

---

### 7. Event Processing Flow

**Asynchronous event-driven processing:**

```
Order Service
  └─► EventHub Producer
      ├─► Topic: "orders"
      └─► Publish Event
          └─► {
                eventType: "OrderCreated",
                orderId: "12345",
                customerId: "cust-001",
                items: [...],
                totalAmount: 199.99,
                timestamp: "2025-11-06T10:30:00Z"
              }

EventHub
  └─► Event Processor (Consumer)
      ├─► Consumer Group: "event-processor"
      ├─► Partition: Auto-assigned
      │
      ├─► Receive Event
      │   └─► Process in order per partition
      │
      ├─► Store in Cosmos DB
      │   ├─► Database: EventStore
      │   ├─► Container: Events
      │   ├─► Partition Key: /orderId
      │   └─► Document: { id, eventType, data, timestamp, processed }
      │
      ├─► Update Redis Cache
      │   ├─► Key: order:{orderId}
      │   └─► Value: Full order object
      │       └─► TTL: 1 hour
      │
      └─► Publish Notification Event
          └─► EventHub Topic: "notifications"
              └─► Notification Service
                  ├─► Determine notification channels
                  │   ├─► Email: order confirmation
                  │   ├─► SMS: order number
                  │   └─► Push: mobile notification
                  │
                  ├─► Send Notifications
                  │   ├─► Email Service (SMTP)
                  │   ├─► SMS Service (Twilio)
                  │   └─► Push Service (FCM)
                  │
                  └─► Broadcast via WebSocket
                      └─► Connected clients receive real-time update
```

**Event Processing Guarantees:**
- At-least-once delivery (EventHub guarantee)
- Idempotent processing (check Cosmos DB for duplicates)
- Ordered processing per partition
- Automatic retry with exponential backoff

---

### 8. Payment Processing Flow

```
API Gateway
  └─► Payment Service POST /api/payments
      │
      ├─► Validate Payment Request
      │   ├─► Check: orderId, amount, currency
      │   └─► Validate: customer data
      │
      ├─► Process Payment (Simulated)
      │   ├─► Random success/failure (95% success)
      │   └─► Generate transaction ID
      │
      ├─► Store in Database
      │   ├─► In-Memory EF Core DbContext
      │   └─► Entity: Payment { Id, OrderId, Amount, Status, Timestamp }
      │
      ├─► Update Redis Cache
      │   └─► Key: payment:{orderId}
      │       Value: { transactionId, status, amount }
      │
      ├─► Publish Event
      │   └─► EventHub: "payment-events"
      │       └─► Event: { type: "PaymentCompleted", orderId, transactionId, amount }
      │
      └─► Return Response
          └─► { transactionId, status, amount, currency, timestamp }
```

---

### 9. Synthetic Traffic Flow

**Automated load generation:**

```
Azure Function (Timer Trigger: Every 5 minutes)
  └─► Traffic Generator
      │
      ├─► Generate Random Requests (5-40 requests per run)
      │   ├─► 95% successful requests
      │   └─► 5% with intentional errors
      │
      └─► For each request:
          └─► API Gateway POST /api/orders
              ├─► Random customer ID
              ├─► Random product (1-5)
              ├─► Random quantity (1-10)
              └─► Current timestamp
```

**Traffic Pattern:**
- 5-40 orders per 5 minutes
- ~1-8 orders per minute average
- Sufficient to generate telemetry without overwhelming system

---

## Component Integration Points

### API Gateway Integration

| Downstream Service | Endpoint | Method | Purpose |
|-------------------|----------|--------|---------|
| Order Service | `/api/orders` | GET, POST | Order management |
| Order Service | `/api/orders/{id}` | GET | Get order details |
| Payment Service | `/api/payments` | POST | Process payment |
| Inventory Service | `/api/inventory` | GET | Get all products |
| Inventory Service | `/api/inventory/{id}` | GET | Get product details |
| Event Processor | `/health` | GET | Health check |
| Notification Service | `/health` | GET | Health check |

### Data Store Access Patterns

| Service | Reads From | Writes To | Pattern |
|---------|-----------|-----------|---------|
| **API Gateway** | Redis | Redis, EventHub | Cache-aside |
| **Order Service** | SQL Database | SQL, EventHub | Write-through |
| **Payment Service** | In-Memory DB, Redis | In-Memory, Redis, EventHub | Cache-aside |
| **Inventory Service** | MongoDB/Memory | MongoDB/Memory | Direct access |
| **Event Processor** | EventHub | Cosmos DB, Redis | Event-driven |
| **Notification Service** | EventHub, Redis | External APIs | Event-driven |

### Message Flow

```
Producer Services:
  Order Service ──────────► EventHub (orders topic)
  Payment Service ────────► EventHub (payment-events topic)
  Event Processor ────────► EventHub (notifications topic)

Consumer Services:
  Event Processor ◄──────── EventHub (orders, payment-events topics)
  Notification Service ◄──── EventHub (notifications topic)

Event Flow:
  Order Service → EventHub (orders) → Event Processor → EventHub (notifications) → Notification Service
  Payment Service → EventHub (payment-events) → Event Processor
```

---

## Performance Characteristics

### Response Times (Typical)

| Operation | Cached | Uncached | Notes |
|-----------|--------|----------|-------|
| GET /api/orders | 10-50ms | 100-500ms | Cache hit vs DB query |
| POST /api/orders | N/A | 200-800ms | Multi-service orchestration |
| GET /api/inventory | N/A | 50-200ms | Direct VM call |
| GET /api/health/all | N/A | 200-500ms | Parallel health checks |
| Event Processing | N/A | 100-300ms | EventHub → Cosmos → Redis |

### Scalability

- **API Gateway**: Single VM (can scale to multiple with load balancer)
- **AKS Services**: Horizontal pod autoscaling (2-10 replicas)
- **EventHub**: Auto-scale based on throughput units
- **Cosmos DB**: Provisioned throughput (400 RU/s default)
- **Redis**: Standard tier with 1GB cache

---

## Error Handling

### Retry Patterns

```
API Gateway → Downstream Service
  ├─► Initial attempt
  ├─► Retry 1: After 1s (if 5xx error)
  ├─► Retry 2: After 2s (if 5xx error)
  └─► Retry 3: After 4s (if 5xx error)
      └─► Return error to client if all fail

Event Processor
  ├─► EventHub: Built-in retry
  ├─► Cosmos DB: Retry on 429 (rate limit)
  └─► Redis: Retry on connection failure
```

### Circuit Breaker

- Implemented in API Gateway for downstream services
- Threshold: 5 failures in 30 seconds
- Break duration: 60 seconds
- Half-open: Test with single request

---

## Security

### Authentication Flow

```
User → Frontend
  └─► API Gateway (Optional: API key validation)
      └─► Downstream Services (Internal network)
          └─► Data Stores (Connection string auth)
```

### Network Security

- **Frontend**: Public (HTTPS)
- **API Gateway**: Public (HTTP - VM public IP)
- **AKS Services**: Private (ClusterIP/NodePort)
- **Data Stores**: Private (VNet integrated)
- **VMs**: NSG rules (SSH: 22, HTTP: 3001, 5000)

---

## Observability

### Telemetry Collection

```
Services → OpenTelemetry SDK
  ├─► Traces → Azure Monitor
  ├─► Metrics → Azure Monitor
  └─► Logs → Azure Monitor

Application Insights
  ├─► Distributed Tracing
  ├─► Application Map
  ├─► Performance Metrics
  └─► Failure Analysis
```

### Correlation

- **Trace ID**: Propagated through all services
- **Span ID**: Unique per operation
- **Parent Span**: Links child operations
- **Baggage**: Custom context propagation

---

## Deployment Architecture

### Azure Resources

```
Resource Group
├─► AKS Cluster (3 nodes, Standard_D2s_v3)
│   ├─► order-service (2 replicas)
│   ├─► payment-service (2 replicas)
│   ├─► event-processor (2 replicas)
│   └─► notification-service (2 replicas)
│
├─► Azure VMs (2x Standard_D2s_v3)
│   ├─► VM1: inventory-service (port 3001)
│   └─► VM2: api-gateway (port 5000)
│
├─► Azure SQL Database (S1 tier)
├─► Azure Cosmos DB (400 RU/s)
├─► Azure Redis Cache (Standard, 1GB)
├─► Azure EventHub (Standard tier)
├─► Azure App Service (Frontend)
├─► Azure Function (Synthetic Traffic)
├─► Application Insights
└─► Log Analytics Workspace
```

---

## Conclusion

This call flow demonstrates a modern, cloud-native, microservices architecture with:

✅ **API Gateway pattern** for centralized entry point  
✅ **Event-driven architecture** with EventHub  
✅ **Caching strategy** with Redis  
✅ **Multiple data stores** (SQL, Cosmos, MongoDB, In-Memory)  
✅ **Asynchronous processing** for scalability  
✅ **Health monitoring** across all services  
✅ **Distributed tracing** with OpenTelemetry  
✅ **Real-time notifications** via WebSocket  

The architecture supports both synchronous request/response and asynchronous event-driven communication patterns, providing a robust foundation for observable, scalable cloud applications.
