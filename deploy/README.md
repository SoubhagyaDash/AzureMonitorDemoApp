# Deployment Automation

The `deploy` folder contains automation utilities that provision Azure resources,
build container images, and deploy the demo workloads. The new entry point is
`deploy-environment.ps1`, which orchestrates Terraform, Docker, and the Azure CLI
without persisting secrets to source control.

## Prerequisites

- PowerShell 7+
- Azure CLI (`az`) authenticated to the target subscription (`az login`)
- Terraform >= 1.6
- Docker CLI (for local image builds)

## Quick Start

1. Copy the sample Terraform variables file and customise it for your environment:
   ```powershell
   Copy-Item infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars
   # Edit the new terraform.tfvars with your values (resource group, region, etc.)
   ```
2. Run the deployment script from the repository root:
   ```powershell
   pwsh ./deploy/deploy-environment.ps1
   ```

The script will:

- Run `terraform init` and `terraform apply` (unless `-SkipInfrastructure` is supplied)
- Build Docker images for each service and push them to the provisioned ACR
- Deploy containers to the demo VMs using `az vm run-command`
- Zip and deploy the lightweight Node.js frontend to the App Service

## Useful Switches

- `-VarFile <path>` — Explicit path to a Terraform variable file
- `-DockerTag <tag>` — Override the image tag used when pushing to ACR (default `latest`)
- `-SkipInfrastructure` — Reuse existing Azure resources without running Terraform
- `-SkipContainers` — Skip image build/push (assumes artifacts already exist in ACR)
- `-SkipVmDeployment` — Build/push images but skip the remote container rollout
- `-SkipFrontend` — Skip the App Service deployment step
- `-IncludeNotificationService` — Deploy the Go notification service container (disabled by default)

## Secrets Hygiene

All sensitive values are pulled dynamically from Terraform outputs at runtime. The
script avoids printing credentials and ensures that generated files such as
`terraform.tfstate`, `*.tfplan`, `node_modules`, build artefacts, and `.env*`
files stay outside of source control via the repository-wide `.gitignore`.

## Cleanup

To tear everything down, run Terraform from the infrastructure directory:

```powershell
Push-Location infrastructure/terraform
terraform destroy
Pop-Location
```