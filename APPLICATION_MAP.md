# OpenTelemetry Demo – Application Map

## High-Level Architecture

```
┌───────────────────────────────┐
│       Azure Subscription      │
├─────────────────────────┬─────┤
│ Resource Group          │ demo│
│                         └─────┤
│ • Azure Container Registry (ACR)
│ • Azure SQL Database
│ • Azure Redis Cache
│ • Azure Cosmos DB
│ • Azure Event Hub Namespace (orders, payment-events, notifications)
│ • Azure Virtual Machines (2)
│ • Azure App Service (frontend)
└────────────────────────────────┘
```

- **VM #1** hosts the `inventory-service` container.
- **VM #2** hosts the `api-gateway`, `order-service`, `payment-service`, and `event-processor` containers (plus an optional `notification-service`).
- **App Service** runs the simplified Node.js frontend (`frontend-simple`).

## Deployment Flow

1. `deploy/deploy-environment.ps1`
   - Provisions or updates infrastructure using Terraform
   - Builds and pushes service images to ACR
   - Runs `az vm run-command invoke` to refresh containers on each VM
   - Zips and deploys the frontend to the App Service

2. Service-to-service communication
   - API Gateway communicates with Order, Payment, and Event Processor over `localhost` on VM #2
   - Inventory Service is accessed by API Gateway using the VM #1 private/public IP
   - Event Processor consumes `orders` events and stores processed data in Cosmos DB

3. Data stores and messaging
   - Order Service persists order metadata in Azure SQL Database
   - Payment Service caches results and publishes payment telemetry to Event Hub (`payment-events`)
   - Event Processor reads from Event Hub (`orders`) and writes to Cosmos DB (`EventStore/Events`)

## Observability

- Azure Monitor / Application Insights connection string is injected at runtime via Terraform outputs
- API Gateway and Payment Service use the Azure Monitor OpenTelemetry Distro
- Inventory Service, Event Processor, and Notification Service rely on OSS OpenTelemetry SDKs
- Optional synthetic traffic can be enabled separately via the `load-testing` folder

## Runtime Endpoints (populated at deploy time)

Values are emitted after deployment by `deploy-environment.ps1` using Terraform outputs:

| Endpoint                             | Description                              |
|--------------------------------------|------------------------------------------|
| `frontend_urls.static_web_app_url`   | Static Web App fallback (optional)       |
| `frontend_urls.app_service_url`      | Primary Node.js frontend URL             |
| `service_endpoints.api_gateway_url`  | API Gateway public load balancer endpoint|
| `service_endpoints.vm1_public_ip`    | VM #1 public IP (inventory service)      |
| `service_endpoints.vm2_public_ip`    | VM #2 public IP (core services)          |

> Actual IP addresses and connection strings are deliberately excluded from source
> control. Retrieve them at runtime via Terraform (`terraform output -json`) or by
> checking the summary emitted by `deploy-environment.ps1`.
