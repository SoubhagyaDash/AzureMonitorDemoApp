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

The demo consists of:

## Services Overview

### Services

| Service              | Language | Hosting        | Notes |- **Frontend (React)** - Web UI with synthetic traffic generation and Application Insights JS SDK

|----------------------|----------|----------------|-------|- **API Gateway (.NET)** - VM-deployed with Azure Monitor OTel Distro

| API Gateway          | .NET 8   | Azure VM (Linux) | Azure Monitor OTel Distro |- **Order Service (Java)** - AKS-deployed, auto-instrumented

| Order Service        | Java 17  | Azure VM (Linux) | Spring Boot + SQL Server |- **Event Processor (Python)** - Processes EventHub messages with OSS OTel SDK

| Payment Service      | .NET 8   | Azure VM (Linux) | OSS OTel SDK + Redis cache |- **Inventory Service (Node.js)** - Uses OSS OTel SDK

| Inventory Service    | Node.js  | Azure VM (Linux) | OSS OTel SDK |- **Notification Service (Golang)** - Real-time notifications with WebSocket support, OSS OTel SDK

| Event Processor      | Python 3 | Azure VM (Linux) | Event Hub → Cosmos DB |

| Notification Service | Go 1.21  | Azure VM (Linux) | Optional (demo skeleton) |### Azure Resources

| Frontend (simple)    | Node.js  | Azure App Service | Static HTML + API proxy |- **Azure VMs** - Host .NET services

- **Azure Kubernetes Service (AKS)** - Container orchestration

## Prerequisites- **Azure Event Hub** - Message streaming

- **Azure SQL Database** - Primary data store

- Azure subscription and permissions to create resource groups- **Azure Cosmos DB** - Document store

- PowerShell 7+- **Azure Redis Cache** - Caching layer

- Terraform (>= 1.6)

- Azure CLI (`az`) authenticated to the target subscription (`az login`)### OpenTelemetry Instrumentation Strategy

- Docker CLI (used to build/push service containers)

| Service | Language | Deployment | Instrumentation |

## Deploy in One Step|---------|----------|------------|----------------|

| API Gateway | .NET | Azure VM | Azure Monitor OTel Distro |

```powershell| Order Service | Java | AKS | Auto-instrumentation (none pre-applied) |

# from the repository root| Payment Service | .NET | AKS | Auto-instrumentation (none pre-applied) |

Copy-Item infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars| Event Processor | Python | AKS | OSS OTel SDK |

# edit the new terraform.tfvars with your chosen names/regions| Inventory Service | Node.js | AKS | OSS OTel SDK |

| Notification Service | Golang | AKS | OSS OTel SDK |

pwsh ./deploy/deploy-environment.ps1| Frontend | React/JavaScript | CDN/Static | Application Insights JS SDK |

```

## Features

The script will:

### Observability

1. Initialise and apply the Terraform configuration (unless `-SkipInfrastructure` is used)- Distributed tracing across all services

2. Build Docker images for all services, tag them with `:latest` (override via `-DockerTag`)- Custom metrics and logs

3. Push images to the Terraform-provisioned Azure Container Registry- Performance monitoring

4. Use `az vm run-command` to roll out containers on both VMs- Error tracking

5. Zip and deploy the `frontend-simple` Node.js application to the App Service- Real-time notifications via WebSocket

- Frontend user interaction tracking

All runtime secrets are pulled dynamically from Terraform outputs and never

persisted to disk. Generated artefacts (`*.tfstate`, `*.tfplan`, `node_modules`,### Failure Injection

`build/`, `.env*`, etc.) are ignored via the repository-wide `.gitignore`.- Configurable latency injection

- Random error generation

### Useful script switches- Infrastructure issues (OOMKill, network problems)

- Database connection failures

- `-VarFile <path>` – Explicit Terraform variables file

- `-SkipInfrastructure` – Reuse existing resources, skip Terraform### Synthetic Traffic & User Interactions

- `-SkipContainers` – Skip Docker build/push (images already in ACR)- Automated load generation

- `-SkipVmDeployment` – Build/push images but leave running containers untouched- Realistic user scenarios

- `-SkipFrontend` – Skip the App Service deployment- Configurable traffic patterns

- `-IncludeNotificationService` – Deploy the Go notification service skeleton- Interactive eCommerce store with real shopping flows



## Terraform Layout## Getting Started



`infrastructure/terraform` defines all Azure resources:1. Deploy Azure infrastructure: `./deploy/terraform/`

2. Build and deploy services: `./deploy/scripts/`

- Resource group, networking, and public IPs3. Configure monitoring: `./monitoring/`

- Azure Container Registry4. Start traffic generation: Access the frontend

- Linux virtual machines for the service tier

- Azure SQL Database, Redis Cache, and Cosmos DB## Directory Structure

- Event Hub namespace with `orders`, `payment-events`, and `notifications` hubs

- Static Web App + Linux App Service for frontend hosting```

- Application Insights + Log Analytics├── services/

│   ├── frontend/          # React application

Only example variable files (`*.tfvars.example`) are committed. Create your own│   ├── api-gateway/       # .NET Core API (Azure VM)

`terraform.tfvars` (ignored by git) for environment-specific settings.│   ├── order-service/     # Java Spring Boot (AKS)

│   ├── payment-service/   # .NET Core Payment API (AKS)

## Frontend Configuration│   ├── event-processor/   # Python service (AKS)

│   ├── inventory-service/ # Node.js service (AKS)

The React frontend in `services/frontend` now references environment variables│   └── notification-service/ # Golang service (AKS)

for service health checks. Copy `.env.production.example` to `.env.production`├── infrastructure/

and populate it as needed. The simplified frontend used in production (served by│   ├── terraform/         # Infrastructure as Code

`frontend-simple`) runs without additional build steps and is deployed automatically│   └── scripts/          # Deployment scripts

by the main script.├── monitoring/

│   ├── dashboards/       # Azure Monitor dashboards

## Observability│   └── alerts/          # Alert configurations

├── deploy/

- Azure Monitor connection strings are injected at runtime via Terraform outputs│   ├── k8s/             # Kubernetes manifests

- Traces flow from the API Gateway, Order Service, Payment Service, and Event Processor│   ├── docker/          # Docker configurations

- Redis and Event Hub clients are instrumented where supported│   └── vm/              # VM deployment scripts

- Synthetic traffic tooling lives under `load-testing/` (optional)└── load-testing/        # Synthetic traffic generators

```

## Cleanup

## License

Destroy the environment with Terraform:

MIT License
```powershell
Push-Location infrastructure/terraform
terraform destroy
Pop-Location
```

## License

MIT