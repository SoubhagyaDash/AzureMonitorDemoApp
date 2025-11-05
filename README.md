# Azure Monitor OpenTelemetry Demo Application

This is a comprehensive demo application showcasing Azure Monitor's OpenTelemetry support across multiple languages and deployment scenarios. The environment is fully automated, with secrets kept out of source control and a single script that can stand up the entire stack on demand.

## ⚠️ Security Notice

**IMPORTANT:** This repository is configured to prevent accidental secret exposure:

- ✅ `.gitignore` excludes all sensitive files (`.env`, `.tfstate`, `.tfvars`, secrets, logs, etc.)
- ✅ Example configuration files are provided (`.env.example`, `terraform.tfvars.example`)
- ✅ Build artifacts and publish folders are excluded from version control
- ❌ **NEVER commit** connection strings, passwords, API keys, or certificates
- ❌ **NEVER commit** Terraform state files or variable files with real values

**Before deploying:**
1. Copy `infrastructure/terraform/terraform.tfvars.example` to `terraform.tfvars`
2. Edit `terraform.tfvars` with your Azure resource names and regions
3. Copy `services/frontend/.env.production.example` to `.env.production` (optional)
4. Run the deployment script - secrets are injected at runtime from Terraform outputs

**All runtime secrets** (connection strings, keys, etc.) are pulled dynamically from Azure and never persisted to disk.

## Architecture Overview

A comprehensive microservices demo showcasing:
- **Frontend (React)** - Modern eCommerce UI with real health checks and WebSocket support
- **API Gateway (.NET)** - VM-deployed with Azure Monitor OTel Distro and centralized health checks
- **Order Service (Java)** - AKS-deployed Spring Boot service with SQL Server
- **Payment Service (.NET)** - AKS-deployed with OSS OTel SDK and Redis cache
- **Event Processor (Python)** - Processes EventHub messages with OSS OTel SDK
- **Inventory Service (Node.js)** - VM-deployed with OSS OTel SDK
- **Notification Service (Golang)** - Real-time notifications via Event Hub and WebSocket

## Services Overview

### Application Services

| Service              | Language | Hosting              | Notes                                      |
|----------------------|----------|----------------------|--------------------------------------------|
| API Gateway          | .NET 8   | Azure VM (Linux)     | Azure Monitor OTel Distro, Health Checks   |
| Order Service        | Java 17  | Azure AKS            | Spring Boot + SQL Server                   |
| Payment Service      | .NET 8   | Azure AKS            | OSS OTel SDK + Redis cache                 |
| Inventory Service    | Node.js  | Azure VM (Linux)     | OSS OTel SDK                               |
| Event Processor      | Python 3 | Azure AKS            | Event Hub → Cosmos DB                      |
| Notification Service | Go 1.21  | Azure AKS            | Event Hub consumer, WebSocket, Real-time   |
| Frontend             | React    | Azure App Service    | Real health checks, WebSocket support      |

### Azure Infrastructure

- **Azure VMs (2x)** - Host API Gateway and Inventory Service
- **Azure Kubernetes Service (AKS)** - Hosts Order, Payment, Event Processor, and Notification Services
- **Azure Event Hub** - Message streaming for order events and notifications
- **Azure SQL Database** - Primary data store for orders
- **Azure Cosmos DB** - Document store for processed events
- **Azure Redis Cache** - Caching layer for payment service
- **Azure App Service** - React frontend with Express.js backend proxy
- **Application Insights** - Centralized observability and telemetry

### OpenTelemetry Instrumentation Strategy

| Service | Language | Deployment | Instrumentation | Status |
|---------|----------|------------|-----------------|--------|
| API Gateway | .NET | Azure VM | Azure Monitor OTel Distro | ✅ Configured |
| Order Service | Java | AKS | Spring Boot Actuator | 🟡 Partial |
| Payment Service | .NET | AKS | OSS OTel + Azure Monitor | ✅ Emitting |
| Event Processor | Python | AKS | OSS OTel SDK | 🟡 Partial |
| Inventory Service | Node.js | Azure VM | OSS OTel SDK | 🟡 Partial |
| Notification Service | Golang | AKS | OSS OTel SDK | ✅ Configured |
| Frontend | React/JavaScript | App Service | Application Insights JS SDK | ✅ Configured |

## Prerequisites

- Azure subscription and permissions to create resource groups
- PowerShell 7+
- Terraform (>= 1.6)
- Azure CLI (`az`) authenticated to the target subscription (`az login`)
- Docker CLI (used to build/push service containers)
- kubectl configured for AKS management

## Deploy in One Step

```powershell
# from the repository root
Copy-Item infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
# edit the new terraform.tfvars with your chosen names/regions

pwsh ./deploy/deploy-environment.ps1
```

The script will:

1. Initialize and apply the Terraform configuration (unless `-SkipInfrastructure` is used)
2. Build Docker images for all services, tag them with `:latest` (override via `-DockerTag`)
3. Push images to the Terraform-provisioned Azure Container Registry
4. Deploy containerized services to Azure Kubernetes Service (AKS)
5. Use `az vm run-command` to deploy containers on VMs (API Gateway, Inventory Service)
6. Deploy the React frontend to Azure App Service
7. Configure secrets and connection strings from Terraform outputs

All runtime secrets are pulled dynamically from Terraform outputs and never persisted to disk.

## Features

### Observability

- Distributed tracing across all services
- Custom metrics and logs
- Performance monitoring
- Error tracking
- Real-time health monitoring via centralized API
- Real-time notifications via WebSocket
- Frontend user interaction tracking

persisted to disk. Generated artefacts (`*.tfstate`, `*.tfplan`, `node_modules`,### Failure Injection

`build/`, `.env*`, etc.) are ignored via the repository-wide `.gitignore`.- Configurable latency injection

- Random error generation

### Failure Injection

- Configurable latency injection
- Random error generation
- Infrastructure issues (OOMKill, network problems)
- Database connection failures

### Synthetic Traffic & User Interactions

- Automated load generation via Azure Functions
- Realistic user scenarios
- Configurable traffic patterns
- Interactive eCommerce store with real shopping flows

### Health Monitoring

- Centralized health checks via API Gateway
- Real-time service status monitoring
- Response time tracking for each service
- Frontend Service Health page with live updates

### Real-time Notifications

- Event Hub integration for order events
- WebSocket delivery to frontend clients
- Go-based notification service
- Material-UI snackbar notifications

## Deployment Options

### Useful script switches

- `-VarFile <path>` – Explicit Terraform variables file
- `-SkipInfrastructure` – Reuse existing resources, skip Terraform
- `-SkipContainers` – Skip Docker build/push (images already in ACR)
- `-SkipAKS` – Skip AKS deployment
- `-SkipVmDeployment` – Build/push images but leave running containers untouched
- `-SkipFrontend` – Skip the App Service deployment
- `-SkipFunctionApp` – Skip synthetic traffic function deployment
- `-SkipNotificationService` – Exclude notification service from deployment

## Getting Started

1. **Deploy Azure infrastructure:**
   ```powershell
   cd infrastructure/terraform
   terraform init
   terraform plan -out=tfplan
   terraform apply tfplan
   ```

2. **Build and deploy services:**
   ```powershell
   .\deploy\deploy-environment.ps1
   ```

3. **Access the frontend:**
   - Frontend URL will be displayed after deployment
   - Default: `https://app-otel-demo-frontend-{workspace}-{random}.azurewebsites.net`

4. **Monitor telemetry:**
   - Open Azure Portal → Application Insights
   - View Application Map, Live Metrics, Transaction Search
   - Check Service Health page in frontend

## Architecture

### Terraform Layout

`infrastructure/terraform` defines all Azure resources:

- Resource group, networking, and public IPs
- Azure Container Registry
- Linux virtual machines for API Gateway and Inventory Service
- Azure Kubernetes Service (AKS) cluster
- Azure SQL Database, Redis Cache, and Cosmos DB
- Event Hub namespace with `orders`, `payment-events`, and `notifications` hubs
- Azure App Service for frontend hosting
- Application Insights + Log Analytics

Only example variable files (`*.tfvars.example`) are committed. Create your own `terraform.tfvars` (ignored by git) for environment-specific settings.

## Directory Structure

```
├── services/
│   ├── frontend/          # React application with real health checks
│   ├── api-gateway/       # .NET Core API (Azure VM)
│   ├── order-service/     # Java Spring Boot (AKS)
│   ├── payment-service/   # .NET Core Payment API (AKS)
│   ├── event-processor/   # Python service (AKS)
│   ├── inventory-service/ # Node.js service (AKS)
│   ├── notification-service/ # Golang service (AKS)
│   └── synthetic-traffic-function/ # Azure Functions traffic generator
├── infrastructure/
│   ├── terraform/         # Infrastructure as Code
│   └── scripts/          # Deployment scripts
├── k8s/                   # Kubernetes manifests
├── deploy/               # PowerShell deployment scripts
├── monitoring/
│   ├── dashboards/       # Azure Monitor dashboards
│   └── alerts/          # Alert configurations
├── .github/
│   └── PIPELINE_PLAN.md  # CI/CD pipeline planning guide
└── load-testing/        # Synthetic traffic generators
```

## Frontend Configuration

The React frontend in `services/frontend` now uses:
- Real health checks from API Gateway
- WebSocket connection to notification service
- Environment variables for service discovery
- Express.js backend for API proxying

Copy `.env.production.example` to `.env.production` and populate as needed.

## Observability

- Azure Monitor connection strings are injected at runtime via Terraform outputs
- Traces flow from API Gateway, Order Service, Payment Service, Event Processor, and Notification Service
- Distributed tracing shows complete request flows across microservices
- Real-time health monitoring via centralized API Gateway endpoint
- Custom metrics, logs, and performance data collected via OpenTelemetry

## Cleanup

Destroy the environment with Terraform:

```powershell
Push-Location infrastructure/terraform
terraform destroy
Pop-Location
```

## Documentation

- **[ObservabilityInstrumentation.md](ObservabilityInstrumentation.md)** - Detailed instrumentation status and configuration
- **[APPLICATION_MAP.md](APPLICATION_MAP.md)** - Application Map topology and service dependencies
- **[DEPLOYMENT_FIXES.md](DEPLOYMENT_FIXES.md)** - Deployment troubleshooting and fixes
- **[.github/PIPELINE_PLAN.md](.github/PIPELINE_PLAN.md)** - GitHub Actions CI/CD pipeline planning
- **[services/notification-service/README.md](services/notification-service/README.md)** - Notification service documentation
- **[services/frontend/FAILURE_INJECTION_GUIDE.md](services/frontend/FAILURE_INJECTION_GUIDE.md)** - Chaos engineering guide

## License

MIT License