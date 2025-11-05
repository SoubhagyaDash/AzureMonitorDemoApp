# GitHub Actions CI/CD Pipeline Plan

## Overview
This document outlines the strategy for automating deployment of the Azure Monitor OpenTelemetry Demo using GitHub Actions.

## Pipeline Architecture

### 1. Infrastructure Pipeline (Terraform)
**Trigger**: Changes to `infrastructure/terraform/**`
**Purpose**: Deploy/update Azure infrastructure

### 2. Application Pipeline (Services)
**Trigger**: Changes to `services/**` or manual workflow dispatch
**Purpose**: Build containers, deploy to AKS and VMs

### 3. End-to-End Test Pipeline
**Trigger**: After successful deployment
**Purpose**: Run test-environment.ps1 validation

---

## Critical Considerations

### 🔐 Security & Secrets Management

#### Required GitHub Secrets
```yaml
# Azure Authentication
AZURE_CREDENTIALS           # Service Principal JSON for authentication
AZURE_SUBSCRIPTION_ID       # Azure subscription ID
AZURE_TENANT_ID            # Azure AD tenant ID

# Terraform State (if using Azure backend)
TF_STATE_STORAGE_ACCOUNT   # Storage account for Terraform state
TF_STATE_CONTAINER         # Container name for state files
TF_STATE_RESOURCE_GROUP    # Resource group for state storage

# SSH Keys
SSH_PRIVATE_KEY            # Private key for VM access (azure_vm_key)
SSH_PUBLIC_KEY             # Public key to configure on VMs

# Container Registry (set by Terraform, or pre-existing)
ACR_USERNAME               # ACR admin username
ACR_PASSWORD               # ACR admin password

# Notifications (optional)
SLACK_WEBHOOK_URL          # For deployment notifications
```

#### Security Best Practices
- ✅ Use **OpenID Connect (OIDC)** for Azure authentication instead of service principal secrets
- ✅ Store **sensitive values** as GitHub encrypted secrets
- ✅ Use **environment protection rules** for production
- ✅ Enable **required reviews** for production deployments
- ✅ **Rotate secrets** regularly (90-day cycle)
- ✅ Use **least-privilege** service principals (Contributor only on resource group)
- ✅ **Never log** secrets or credentials in pipeline output
- ✅ Use **Azure Key Vault** for runtime secrets (connection strings, passwords)

---

### 🏗️ Infrastructure as Code (Terraform)

#### State Management
**Challenge**: Terraform state must be shared across pipeline runs

**Solutions**:
1. **Azure Storage Backend** (Recommended)
   ```hcl
   terraform {
     backend "azurerm" {
       resource_group_name  = "terraform-state-rg"
       storage_account_name = "tfstateaccount"
       container_name       = "tfstate"
       key                  = "otel-demo.tfstate"
     }
   }
   ```

2. **State Locking**: Use Azure Storage blob lease for concurrent access protection

3. **State File Security**: 
   - Enable encryption at rest
   - Restrict access with RBAC
   - Enable versioning for rollback

#### Terraform Execution Strategy
```yaml
# Option 1: Plan on PR, Apply on Merge
- Pull Request → terraform plan → Comment on PR with plan output
- Merge to main → terraform apply -auto-approve

# Option 2: Manual Approval
- Pull Request → terraform plan
- Merge to main → terraform plan (wait for approval) → terraform apply

# Option 3: GitOps with Environments
- PR to dev → deploy to dev environment
- PR to staging → deploy to staging
- PR to main → deploy to production (with approvals)
```

#### Terraform Variables
- Use **terraform.tfvars** template checked into repo
- Override with **environment-specific** values in pipeline
- Use **TF_VAR_** environment variables for sensitive values

---

### 🐳 Container Build & Registry

#### Build Strategy
**Parallel Builds**: Build all 5 services concurrently to save time
```
api-gateway (C#) - ~2 min
order-service (Java) - ~3 min
payment-service (C#) - ~2 min
event-processor (Python) - ~1 min
inventory-service (Node.js) - ~1 min
```

#### Image Tagging Strategy
```bash
# Use Git commit SHA for traceability
IMAGE_TAG="${GITHUB_SHA::7}"  # Short commit SHA

# Or semantic versioning
IMAGE_TAG="${GITHUB_REF##*/}-${GITHUB_RUN_NUMBER}"  # main-42

# Tag both specific version AND latest
docker tag app:$IMAGE_TAG app:latest
```

#### Registry Considerations
- **Push images** only after successful builds
- **Scan images** for vulnerabilities (Trivy, Snyk)
- **Clean up old images** (retention policy)
- **Use multi-stage builds** (already implemented ✅)

---

### 🚀 Deployment Strategy

#### Environment Strategy
**Option 1: Single Environment (Current)**
- One workspace: `fresh-test` or `production`
- Simplest approach
- Good for demos/PoCs

**Option 2: Multi-Environment**
```
dev (ephemeral)      → Auto-deploy on every commit
staging (persistent) → Deploy on PR approval
production           → Deploy on release tag with manual approval
```

**Option 3: Pull Request Environments**
- Create temporary environment per PR
- Destroy after PR merge
- Great for testing without affecting main environment

#### Deployment Orchestration
```mermaid
1. Terraform Apply (Infrastructure)
   ↓
2. Wait for VMs to initialize (Docker ready)
   ↓
3. Build & Push Container Images (parallel)
   ↓
4. Deploy to AKS (Order, Payment, Event Processor)
   ↓
5. Deploy to VMs via SSH (API Gateway, Inventory)
   ↓
6. Deploy Frontend (App Service)
   ↓
7. Deploy Function App (Synthetic Traffic)
   ↓
8. Run End-to-End Tests
   ↓
9. Send Notifications (Slack/Teams)
```

#### SSH Access in Pipeline
**Challenge**: How does GitHub Actions SSH into VMs?

**Solution 1: SSH Key in Secrets** (Recommended)
```yaml
- name: Setup SSH Key
  run: |
    mkdir -p ~/.ssh
    echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/azure_vm_key
    chmod 600 ~/.ssh/azure_vm_key
    echo "${{ secrets.SSH_PUBLIC_KEY }}" > ~/.ssh/azure_vm_key.pub
    # Configure SSH config
```

**Solution 2: Azure Bastion** (More Secure, Complex)
- Use Azure Bastion for SSH tunneling
- No public IPs needed on VMs
- Requires additional setup

**Solution 3: Deploy via Azure VM Run Command** (Fallback)
- Use `az vm run-command` as backup
- Slower and less reliable (as we discovered)

---

### 🧪 Testing Strategy

#### Test Stages
1. **Unit Tests** (in service directories)
   - Run during container builds
   - Fast feedback on code quality

2. **Integration Tests** (pre-deployment)
   - Test service interactions locally
   - Docker Compose for local testing

3. **Smoke Tests** (post-deployment)
   - Basic health checks
   - Quick validation after deployment

4. **End-to-End Tests** (post-deployment)
   - Full workflow validation (`test-environment.ps1`)
   - Order creation → SQL → Event Hub → Cosmos
   - **Critical**: Should run automatically and fail pipeline if tests fail

#### Test Failure Handling
```yaml
- name: Run E2E Tests
  id: e2e-tests
  run: |
    pwsh deploy/test-environment.ps1
  continue-on-error: false  # Fail pipeline if tests fail

- name: Collect Logs on Failure
  if: failure()
  run: |
    # Collect container logs
    # Collect VM logs
    # Upload as artifacts
```

---

### 📊 Monitoring & Notifications

#### Pipeline Monitoring
- **GitHub Actions Dashboard**: Built-in monitoring
- **Deployment frequency**: Track via GitHub insights
- **Mean time to recovery**: Track failed deployments

#### Notifications
**Integration Points**:
- Slack/Teams webhooks for deployment status
- Email notifications for failures
- GitHub Status Checks for PR validation

**What to Notify**:
- ✅ Deployment started
- ✅ Deployment completed (with URLs)
- ❌ Deployment failed (with error details)
- ⚠️ Tests failed (with test results)
- 📊 Resource usage/costs (optional)

---

### 💰 Cost Management

#### Resource Lifecycle
**Challenge**: Keeping demo environment running 24/7 is expensive

**Solutions**:
1. **Scheduled Shutdown**
   ```yaml
   # Destroy environment at night
   schedule:
     - cron: '0 22 * * 1-5'  # 10 PM weekdays
   ```

2. **On-Demand Deployment**
   - Manual workflow dispatch
   - Deploy only when needed
   - Destroy after demo/testing

3. **Auto-Scaling**
   - Scale AKS to 0 nodes when not in use
   - Use Azure Automation to stop VMs

4. **Cost Alerts**
   - Set up Azure Cost Management alerts
   - Daily budget notifications

#### Resource Tagging
```hcl
tags = {
  Environment = "demo"
  ManagedBy   = "github-actions"
  CostCenter  = "engineering"
  Owner       = "team-platform"
  AutoShutdown = "true"
  Workspace   = var.workspace_name
}
```

---

### 🔄 Rollback Strategy

#### Infrastructure Rollback
**Challenge**: Terraform doesn't have built-in rollback

**Solutions**:
1. **State File Versioning**
   - Azure Storage blob versioning enabled
   - Revert to previous state version

2. **Git Revert**
   - Revert infrastructure changes in Git
   - Re-run pipeline with reverted code

3. **Workspace Isolation**
   - Keep previous workspace as backup
   - Switch traffic to old workspace if needed

#### Application Rollback
**Container Images**:
- Keep previous image tags in ACR
- Update deployment to use previous tag
- Deploy script should support `-DockerTag` parameter

**Database Migrations**:
- Use reversible migrations (up/down)
- Test rollback in staging first
- Have database backup before major changes

---

### 🌐 Multi-Region Considerations

#### Current Architecture
- Single region (West US 2)
- Good for demo/dev

#### Production Considerations
1. **Traffic Manager**: Route traffic to nearest region
2. **Geo-Replicated Databases**: SQL geo-replication, Cosmos multi-region
3. **Regional Failover**: Automatic or manual failover
4. **Data Consistency**: Handle eventual consistency

---

### 📝 Pipeline Best Practices

#### Code Organization
```
.github/
  workflows/
    infra-deploy.yml           # Terraform infrastructure
    app-build-deploy.yml       # Build & deploy services
    test-e2e.yml               # End-to-end tests
    cleanup.yml                # Resource cleanup
    pr-validation.yml          # PR checks
    
  actions/                     # Reusable composite actions
    setup-terraform/
    setup-azure-cli/
    deploy-to-vm/
```

#### Workflow Reusability
```yaml
# Reusable workflow for deployments
jobs:
  call-deploy:
    uses: ./.github/workflows/deploy-reusable.yml
    with:
      environment: production
      docker-tag: ${{ github.sha }}
    secrets: inherit
```

#### Caching Strategy
```yaml
# Cache Docker layers
- uses: actions/cache@v3
  with:
    path: /tmp/.buildx-cache
    key: ${{ runner.os }}-buildx-${{ github.sha }}

# Cache Terraform providers
- uses: actions/cache@v3
  with:
    path: ~/.terraform.d/plugin-cache
    key: ${{ runner.os }}-terraform-${{ hashFiles('**/*.tf') }}
```

#### Performance Optimization
- Run tests in **parallel** where possible
- Use **matrix builds** for multi-service builds
- **Cache dependencies** (npm, pip, maven, nuget)
- Use **self-hosted runners** for faster builds (optional)

---

## Recommended Pipeline Structure

### Pipeline 1: Infrastructure (infra-deploy.yml)
```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
    paths: ['infrastructure/**']
  pull_request:
    paths: ['infrastructure/**']
  workflow_dispatch:
    inputs:
      environment:
        description: 'Environment to deploy'
        required: true
        default: 'dev'

jobs:
  terraform:
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - Setup Terraform
      - Setup Azure CLI
      - Terraform init (with backend config)
      - Terraform plan (save plan output)
      - [PR only] Comment plan on PR
      - [Main only] Terraform apply
      - Output infrastructure details
```

### Pipeline 2: Application (app-deploy.yml)
```yaml
name: Build and Deploy Application

on:
  push:
    branches: [main]
    paths: ['services/**']
  workflow_dispatch:

jobs:
  build:
    strategy:
      matrix:
        service: [api-gateway, order-service, payment-service, event-processor, inventory-service]
    steps:
      - Build Docker image
      - Run tests
      - Scan for vulnerabilities
      - Push to ACR

  deploy-aks:
    needs: build
    steps:
      - Deploy to AKS (order, payment, event-processor)
      - Wait for rollout

  deploy-vms:
    needs: build
    steps:
      - Setup SSH keys
      - Deploy via SSH to VMs
      - Verify containers running

  deploy-frontend:
    needs: build
    steps:
      - Build React app
      - Deploy to App Service

  test:
    needs: [deploy-aks, deploy-vms, deploy-frontend]
    steps:
      - Run test-environment.ps1
      - Upload test results
```

### Pipeline 3: End-to-End Tests (test-e2e.yml)
```yaml
name: End-to-End Tests

on:
  workflow_call:  # Can be called by other workflows
  schedule:
    - cron: '0 */4 * * *'  # Every 4 hours

jobs:
  test:
    steps:
      - Run test-environment.ps1
      - Check health endpoints
      - Verify telemetry flow
      - Upload results
      - Notify on failure
```

### Pipeline 4: Cleanup (cleanup.yml)
```yaml
name: Cleanup Resources

on:
  workflow_dispatch:
    inputs:
      workspace:
        description: 'Terraform workspace to destroy'
        required: true
  schedule:
    - cron: '0 22 * * 5'  # Friday 10 PM

jobs:
  destroy:
    steps:
      - Confirm destruction (if manual)
      - Terraform destroy
      - Cleanup ACR images
      - Send notification
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Set up Azure Service Principal with RBAC
- [ ] Configure GitHub Secrets
- [ ] Set up Terraform remote state (Azure Storage)
- [ ] Create basic infrastructure pipeline (plan on PR)
- [ ] Test infrastructure deployment from pipeline

### Phase 2: Application Deployment (Week 2)
- [ ] Create container build pipeline
- [ ] Add ACR push workflow
- [ ] Implement SSH-based VM deployment
- [ ] Add AKS deployment
- [ ] Test full deployment end-to-end

### Phase 3: Testing & Validation (Week 3)
- [ ] Integrate test-environment.ps1 into pipeline
- [ ] Add smoke tests
- [ ] Configure test result reporting
- [ ] Set up failure notifications

### Phase 4: Optimization & Hardening (Week 4)
- [ ] Add caching for faster builds
- [ ] Implement rollback procedures
- [ ] Add vulnerability scanning
- [ ] Configure environment protection rules
- [ ] Document runbooks

### Phase 5: Production Readiness (Ongoing)
- [ ] Set up multi-environment strategy
- [ ] Add manual approval gates
- [ ] Configure cost alerts
- [ ] Implement auto-shutdown schedules
- [ ] Create incident response playbooks

---

## Key Decisions Needed

### 1. Environment Strategy
- **Single environment** vs **Multi-environment** (dev/staging/prod)?
- **Long-running** vs **Ephemeral** environments?
- **Cost tolerance** for keeping resources running?

### 2. Deployment Trigger
- **Automatic** on every commit to main?
- **Manual** workflow dispatch only?
- **Scheduled** deployments (e.g., daily)?

### 3. State Management
- Where to store Terraform state? (Azure Storage recommended)
- State locking strategy?
- Backup and disaster recovery?

### 4. Access Control
- Who can trigger deployments?
- Required approvals for production?
- Branch protection rules?

### 5. Monitoring & Alerting
- Which notifications are critical?
- Where to send alerts? (Slack, Teams, Email)
- On-call rotation for production issues?

---

## Security Checklist

- [ ] Use OIDC federation instead of service principal secrets
- [ ] Enable required reviews for production deployments
- [ ] Scan container images for vulnerabilities
- [ ] Use Azure Key Vault for runtime secrets
- [ ] Implement least-privilege RBAC
- [ ] Enable audit logging for deployments
- [ ] Rotate credentials regularly
- [ ] Scan IaC for security issues (Checkov, Trivy)
- [ ] Enable branch protection on main
- [ ] Require signed commits (optional)

---

## Useful GitHub Actions

### Pre-Built Actions
```yaml
# Azure
- azure/login@v1                    # Azure authentication
- azure/CLI@v1                      # Run Azure CLI commands
- azure/webapps-deploy@v2           # Deploy to App Service

# Terraform
- hashicorp/setup-terraform@v2      # Setup Terraform
- dflook/terraform-plan@v1          # Plan with PR comments

# Docker
- docker/setup-buildx-action@v2     # Setup Docker Buildx
- docker/build-push-action@v4       # Build and push images

# Security
- aquasecurity/trivy-action@master  # Vulnerability scanning
- bridgecrewio/checkov-action@master # IaC security scanning

# Testing
- actions/upload-artifact@v3        # Upload test results
- dorny/test-reporter@v1            # Display test results in PR
```

---

## Next Steps

1. **Review this plan** with the team
2. **Make key decisions** (environment strategy, triggers, etc.)
3. **Set up Azure Service Principal** with appropriate permissions
4. **Configure GitHub repository secrets**
5. **Create Terraform remote state storage**
6. **Start with Phase 1** (Foundation) implementation
7. **Test thoroughly** in dev before production

---

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Azure Login Action](https://github.com/Azure/login)
- [Terraform GitHub Actions](https://learn.hashicorp.com/tutorials/terraform/github-actions)
- [Azure DevOps vs GitHub Actions](https://docs.microsoft.com/en-us/azure/devops/pipelines/migrate/from-github-actions)
- [Cost Management Best Practices](https://docs.microsoft.com/en-us/azure/cost-management-billing/costs/cost-mgt-best-practices)
