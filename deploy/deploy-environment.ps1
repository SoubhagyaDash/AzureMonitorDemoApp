<#!
.SYNOPSIS
Deploy the entire OpenTelemetry demo environment (infrastructure + containers + frontend).

.DESCRIPTION
This script orchestrates Terraform, Docker, and Azure CLI to provision the Azure
infrastructure, publish container images to Azure Container Registry, deploy the
runtime services to the demo virtual machines, and update the lightweight Node.js
frontend hosted on Azure App Service.

The script intentionally keeps secrets out of source control. Runtime credentials are
loaded from Terraform outputs at execution time and never written to disk.

.EXAMPLE
./deploy-environment.ps1 -VarFile ..\infrastructure\terraform\terraform.tfvars
#>

[CmdletBinding()]
param(
    [string]$VarFile,
    [string]$DockerTag = "latest",
    [switch]$SkipInfrastructure,
    [switch]$SkipContainers,
    [switch]$SkipVmDeployment,
    [switch]$SkipFrontend,
    [switch]$IncludeNotificationService,
    [ValidateRange(60, 3600)]
    [int]$FrontendDeployTimeoutSeconds = 600,
    [ValidateRange(30, 900)]
    [int]$FrontendWarmupTimeoutSeconds = 180,
    [ValidateRange(5, 60)]
    [int]$FrontendWarmupPollSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")
$terraformDir = Join-Path $repoRoot "infrastructure/terraform"
$frontendSource = Join-Path $repoRoot "services/frontend-simple"

function Write-Step {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Require-Tool {
    param([string]$Tool)
    if (-not (Get-Command $Tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$Tool' was not found on the PATH."
    }
}

function ConvertTo-ShellLiteral {
    param([AllowNull()][string]$Value)
    if ([string]::IsNullOrEmpty($Value)) {
        return "''"
    }
    $replacement = "'" + [char]34 + "'" + [char]34 + "'"
    $escaped = $Value -replace "'", $replacement
    return "'$escaped'"
}

function ConvertTo-ConnectionHashtable {
    param([string]$ConnectionString)
    $result = @{}
    if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
        return $result
    }

    foreach ($segment in $ConnectionString.Split(';')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $pair = $segment.Split('=', 2)
        if ($pair.Count -eq 2) {
            $result[$pair[0]] = $pair[1]
        }
    }
    return $result
}

function Wait-AppServiceReady {
    param(
        [string]$ResourceGroup,
        [string]$WebAppName,
        [int]$TimeoutSeconds,
        [int]$PollIntervalSeconds = 5
    )

    if ($TimeoutSeconds -le 0) { return }

    Write-Host "  Waiting for App Service '$WebAppName' to respond (timeout: $TimeoutSeconds s)..." -ForegroundColor Yellow
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)

    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $site = az webapp show --resource-group $ResourceGroup --name $WebAppName | ConvertFrom-Json
            if ($site -and $site.state -eq "Running") {
                $hostName = $site.defaultHostName
                if ($hostName) {
                    $uri = "https://$hostName"
                    try {
                        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 15
                        if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500) {
                            Write-Host "  App Service is responding at $uri" -ForegroundColor Green
                            return
                        }
                    } catch {
                        # App Service may still be recycling; retry until timeout.
                    }
                }
            }
        } catch {
            # Transient Azure API errors during warmup can be ignored.
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    throw "Timed out waiting for App Service '$WebAppName' to respond after $TimeoutSeconds seconds."
}

Require-Tool -Tool "az"
Require-Tool -Tool "terraform"
Require-Tool -Tool "docker"

try {
    az account show --output none | Out-Null
} catch {
    throw "Azure CLI is not authenticated. Run 'az login' (and 'az account set') before executing this script."
}

if (-not $VarFile) {
    $defaultVarFile = Join-Path $terraformDir "terraform.tfvars"
    if (Test-Path $defaultVarFile) {
        $VarFile = $defaultVarFile
    }
}

if ($VarFile -and -not (Test-Path $VarFile)) {
    throw "Terraform variables file not found: $VarFile"
}

if ($VarFile) {
    $VarFile = (Resolve-Path $VarFile).Path
}

if (-not $SkipInfrastructure) {
    Write-Step "Provisioning Azure infrastructure with Terraform"
    Push-Location $terraformDir
    try {
        terraform init -upgrade
        $applyArgs = @("apply", "-auto-approve")
        if ($VarFile) { $applyArgs += @("-var-file", $VarFile) }
        terraform @applyArgs
    } finally {
        Pop-Location
    }
} else {
    Write-Step "Skipping Terraform apply (using existing infrastructure)"
}

Write-Step "Retrieving Terraform outputs"
Push-Location $terraformDir
try {
    $terraformOutput = terraform output -json | ConvertFrom-Json
} finally {
    Pop-Location
}

$resourceGroup = $terraformOutput.resource_group_name.value
$acrName = $terraformOutput.acr_name.value
$acrLoginServer = $terraformOutput.acr_login_server.value
$acrAdminUsername = $terraformOutput.acr_admin_username.value
$acrAdminPassword = $terraformOutput.acr_admin_password.value
$appInsightsConnectionString = $terraformOutput.application_insights_connection_string.value
$connectionStrings = $terraformOutput.connection_strings.value
$serviceEndpoints = $terraformOutput.service_endpoints.value
$vmNames = @($terraformOutput.vm_names.value)
$vmPublicIps = @($terraformOutput.vm_public_ips.value)
$vmPrivateIps = @($terraformOutput.vm_private_ips.value)
$frontendWebAppName = $terraformOutput.frontend_web_app_name.value
$frontendUrls = $terraformOutput.frontend_urls.value

$inventoryVmIndex = 0
$backendVmIndexDefault = if ($vmNames.Count -gt 1) { 1 } else { 0 }
$inventoryVmPrivateIp = if ($vmPrivateIps.Count -gt $inventoryVmIndex) { $vmPrivateIps[$inventoryVmIndex] } else { $null }
$backendVmPrivateIp = if ($vmPrivateIps.Count -gt $backendVmIndexDefault) { $vmPrivateIps[$backendVmIndexDefault] } elseif ($inventoryVmPrivateIp) { $inventoryVmPrivateIp } else { $null }

$loadBalancerGatewayUrl = if ($serviceEndpoints.api_gateway_public_url -and $serviceEndpoints.api_gateway_public_url.Trim()) { $serviceEndpoints.api_gateway_public_url }
elseif ($serviceEndpoints.api_gateway_url -and $serviceEndpoints.api_gateway_url.Trim()) { $serviceEndpoints.api_gateway_url }
else { $null }

$inventoryServiceUrl = if ($serviceEndpoints.inventory_service_private_url -and $serviceEndpoints.inventory_service_private_url.Trim()) {
    $serviceEndpoints.inventory_service_private_url
} elseif ($inventoryVmPrivateIp -and $inventoryVmPrivateIp.Trim()) {
    "http://${inventoryVmPrivateIp}:3001"
} else { $null }

$orderServiceUrl = if ($serviceEndpoints.order_service_private_url -and $serviceEndpoints.order_service_private_url.Trim()) {
    $serviceEndpoints.order_service_private_url
} elseif ($backendVmPrivateIp -and $backendVmPrivateIp.Trim()) {
    "http://${backendVmPrivateIp}:8080"
} else { $null }

$paymentServiceUrl = if ($serviceEndpoints.payment_service_private_url -and $serviceEndpoints.payment_service_private_url.Trim()) {
    $serviceEndpoints.payment_service_private_url
} elseif ($backendVmPrivateIp -and $backendVmPrivateIp.Trim()) {
    "http://${backendVmPrivateIp}:3000"
} else { $null }

$eventProcessorUrl = if ($serviceEndpoints.event_processor_private_url -and $serviceEndpoints.event_processor_private_url.Trim()) {
    $serviceEndpoints.event_processor_private_url
} elseif ($backendVmPrivateIp -and $backendVmPrivateIp.Trim()) {
    "http://${backendVmPrivateIp}:8001"
} else { $null }

$apiGatewayUrl = if ($serviceEndpoints.api_gateway_private_url -and $serviceEndpoints.api_gateway_private_url.Trim()) {
    $serviceEndpoints.api_gateway_private_url
} elseif ($backendVmPrivateIp -and $backendVmPrivateIp.Trim()) {
    "http://${backendVmPrivateIp}:5000"
} elseif ($loadBalancerGatewayUrl) {
    $loadBalancerGatewayUrl
} else { $null }
$acrPasswordBase64 = if ($acrAdminPassword) { [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($acrAdminPassword)) } else { $null }

$instrumentationKey = ""
if ($appInsightsConnectionString -match "InstrumentationKey=([^;]+)") {
    $instrumentationKey = $Matches[1]
}

$sqlParts = ConvertTo-ConnectionHashtable -ConnectionString $connectionStrings.sql_database
$cosmosParts = ConvertTo-ConnectionHashtable -ConnectionString $connectionStrings.cosmos_db

$redisSegments = $connectionStrings.redis.Split(',')
$redisEndpoint = $redisSegments[0]
$redisPassword = ($redisSegments | Where-Object { $_ -like 'password=*' }) -replace '^password=', ''
$redisScheme = ($redisSegments | Where-Object { $_ -like 'ssl=*' } | Select-Object -First 1)
$redisUrl = if ($redisScheme -and $redisScheme.EndsWith('true', [System.StringComparison]::OrdinalIgnoreCase)) {
    "rediss://:$redisPassword@$redisEndpoint"
} else {
    "redis://:$redisPassword@$redisEndpoint"
}

function New-ServiceConfig {
    param(
        [string]$Name,
        [string]$Image,
        [hashtable]$Environment,
        [bool]$UseHostNetwork = $false,
        [string[]]$Ports = @()
    )

    return [pscustomobject]@{
        Name = $Name
        Image = $Image
        Environment = $Environment
        UseHostNetwork = $UseHostNetwork
        Ports = $Ports
    }
}

# Frontend App Service settings will be configured after AKS deployment

$containerImagePrefix = "$acrLoginServer"
$servicesToBuild = @(
    @{ Name = "api-gateway"; Path = "services/api-gateway" },
    @{ Name = "order-service"; Path = "services/order-service" },
    @{ Name = "payment-service"; Path = "services/payment-service" },
    @{ Name = "event-processor"; Path = "services/event-processor" },
    @{ Name = "inventory-service"; Path = "services/inventory-service" }
)

if ($IncludeNotificationService) {
    $servicesToBuild += @{ Name = "notification-service"; Path = "services/notification-service" }
}

if (-not $SkipContainers) {
    Write-Step "Building and publishing container images"
    az acr login --name $acrName | Out-Null
    try {
        $null = $acrAdminPassword | docker login $acrLoginServer --username $acrAdminUsername --password-stdin
    } catch {
        throw "Failed to authenticate with ACR '$acrLoginServer'."
    }

    foreach ($service in $servicesToBuild) {
        $imageTag = "$containerImagePrefix/$($service.Name):$DockerTag"
        $servicePath = Join-Path $repoRoot $service.Path
        if (-not (Test-Path $servicePath)) {
            throw "Service path not found: $($service.Path)"
        }

        Write-Host "  → Building $($service.Name)" -ForegroundColor Yellow
        Push-Location $servicePath
        try {
            docker build --pull -t $imageTag .
            docker push $imageTag
        } finally {
            Pop-Location
        }
    }
} else {
    Write-Step "Skipping container build/publish"
}

if (-not $SkipVmDeployment) {
    if ($vmNames.Count -eq 0) {
        throw "No virtual machine outputs were found in Terraform state."
    }

    Write-Step "Deploying containers to virtual machines (API Gateway and Inventory only)"

    $inventoryVmIndex = 0
    $apiGatewayVmIndex = if ($vmNames.Count -gt 1) { 1 } else { 0 }

    # Note: Order, Payment, and Event Processor services will be deployed to AKS

    $vmServiceMap = @{}
    
    # VM1: Inventory Service
    $vmServiceMap[$inventoryVmIndex] = New-Object System.Collections.Generic.List[object]
    $vmServiceMap[$inventoryVmIndex].Add((New-ServiceConfig -Name "inventory-service" -Image "$containerImagePrefix/inventory-service:$DockerTag" -Ports @("3001:3001") -Environment @{
        "NODE_ENV" = "production"
        "PORT" = "3001"
        "SERVICE_NAME" = "inventory-service"
        "SERVICE_VERSION" = "1.0.0"
        "APPLICATIONINSIGHTS_CONNECTION_STRING" = $appInsightsConnectionString
        "REDIS_URL" = $redisUrl
    }))

    # VM2: API Gateway (will connect to AKS-hosted services)
    if (-not $vmServiceMap.ContainsKey($apiGatewayVmIndex)) {
        $vmServiceMap[$apiGatewayVmIndex] = New-Object System.Collections.Generic.List[object]
    }

    # Placeholder URLs - will be updated after AKS deployment
    $aksOrderServiceUrl = "http://order-service.otel-demo.svc.cluster.local:8080"
    $aksPaymentServiceUrl = "http://payment-service.otel-demo.svc.cluster.local:3000"
    $inventoryBaseUrl = if ($inventoryServiceUrl) { $inventoryServiceUrl } else { "http://10.0.1.4:3001" }

    $vmServiceMap[$apiGatewayVmIndex].Add((New-ServiceConfig -Name "api-gateway" -Image "$containerImagePrefix/api-gateway:$DockerTag" -UseHostNetwork $true -Environment @{
        "ASPNETCORE_ENVIRONMENT" = "Production"
        "ASPNETCORE_URLS" = "http://+:5000"
        "ApplicationInsights__ConnectionString" = $appInsightsConnectionString
        "ConnectionStrings__DefaultConnection" = $connectionStrings.sql_database
        "Redis__ConnectionString" = $connectionStrings.redis
        "EventHub__ConnectionString" = $connectionStrings.eventhub_orders
        "EventHub__Name" = "orders"
        "Services__OrderService__BaseUrl" = $aksOrderServiceUrl
        "Services__InventoryService__BaseUrl" = $inventoryBaseUrl
        "Services__PaymentService__BaseUrl" = $aksPaymentServiceUrl
        "FailureInjection__Enabled" = "false"
    }))

    foreach ($vmIndex in $vmServiceMap.Keys) {
        $vmName = $vmNames[$vmIndex]
        $vmIp = if ($vmPublicIps.Count -gt $vmIndex) { $vmPublicIps[$vmIndex] } else { "(private)" }
        Write-Host "  → Deploying services to $vmName ($vmIp)" -ForegroundColor Yellow

        $scriptLines = New-Object System.Collections.Generic.List[string]
        $scriptLines.Add("#!/bin/bash")
        $scriptLines.Add("set -euo pipefail")
        $scriptLines.Add("echo 'Starting container rollout on $vmName'")
        $scriptLines.Add("if ! command -v docker >/dev/null 2>&1; then")
        $scriptLines.Add("  apt-get update -y")
        $scriptLines.Add("  apt-get install -y docker.io")
        $scriptLines.Add("  systemctl enable docker >/dev/null 2>&1 || true")
        $scriptLines.Add("  systemctl start docker >/dev/null 2>&1 || true")
        $scriptLines.Add("fi")
    $scriptLines.Add(': "${acrPasswordBase64:?ACR registry password was not supplied}"')
    $scriptLines.Add("acrPassword=$(printf '%s' \"$acrPasswordBase64\" | base64 --decode)")
    $scriptLines.Add("unset acrPasswordBase64")
    $scriptLines.Add(('printf ''%s'' "$acrPassword" | docker login {0} --username {1} --password-stdin >/dev/null' -f $acrLoginServer, $acrAdminUsername))
    $scriptLines.Add("unset acrPassword")

        foreach ($service in $vmServiceMap[$vmIndex]) {
            $scriptLines.Add("echo 'Deploying $($service.Name)'")
            $scriptLines.Add("docker pull $($service.Image)")
            $scriptLines.Add("if docker ps -a --format '{{.Names}}' | grep -Eq '^$($service.Name)$'; then")
            $scriptLines.Add("  docker stop $($service.Name) >/dev/null 2>&1 || true")
            $scriptLines.Add("  docker rm $($service.Name) >/dev/null 2>&1 || true")
            $scriptLines.Add("fi")

            $runParts = New-Object System.Collections.Generic.List[string]
            $runParts.Add("docker run -d")
            $runParts.Add("--name $($service.Name)")
            $runParts.Add("--restart unless-stopped")

            if ($service.UseHostNetwork) {
                $runParts.Add("--network host")
            }

            foreach ($port in $service.Ports) {
                $runParts.Add("-p $port")
            }

            foreach ($entry in $service.Environment.GetEnumerator()) {
                $runParts.Add("-e $($entry.Key)=$(ConvertTo-ShellLiteral $entry.Value)")
            }

            $runParts.Add($service.Image)
            $scriptLines.Add(($runParts -join ' '))
        }

        $scriptLines.Add("docker ps --format '{{.Names}} {{.Status}} {{.Ports}}'")

        $azArgs = @(
            "vm", "run-command", "invoke",
            "--resource-group", $resourceGroup,
            "--name", $vmName,
            "--command-id", "RunShellScript",
            "--scripts"
        )
        $azArgs += $scriptLines

        $runCommandParameters = @()
        if (-not [string]::IsNullOrEmpty($acrPasswordBase64)) {
            $runCommandParameters += "acrPasswordBase64=$acrPasswordBase64"
        }

        if ($runCommandParameters.Count -gt 0) {
            $azArgs += "--parameters"
            $azArgs += $runCommandParameters
        }

        az @azArgs | Out-Null
    }
} else {
    Write-Step "Skipping VM container deployment"
}

# Deploy Order, Payment, and Event Processor services to AKS
$aksClusterName = $terraformOutput.aks_cluster_name.value
if (-not $aksClusterName) {
    Write-Warning "AKS cluster name not found in Terraform outputs. Skipping AKS deployment."
} else {
    Write-Step "Deploying services to AKS cluster: $aksClusterName"
    
    # Get AKS credentials
    Write-Host "  → Configuring kubectl for AKS cluster" -ForegroundColor Yellow
    az aks get-credentials --resource-group $resourceGroup --name $aksClusterName --overwrite-existing --admin | Out-Null
    
    # Create namespace
    Write-Host "  → Creating otel-demo namespace" -ForegroundColor Yellow
    kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
    
    # Create Kubernetes secret with connection strings
    Write-Host "  → Creating secrets" -ForegroundColor Yellow
    $secretData = @{
        "application-insights-connection-string" = $appInsightsConnectionString
        "spring-datasource-url" = "jdbc:sqlserver://$($sqlParts['Server']):1433;database=$($sqlParts['Database']);encrypt=true;trustServerCertificate=true;"
        "spring-datasource-username" = $sqlParts['User Id']
        "spring-datasource-password" = $sqlParts['Password']
        "eventhub-orders-connection-string" = $connectionStrings.eventhub_orders
        "eventhub-payments-connection-string" = $connectionStrings.eventhub_payments
        "redis-connection-string" = $connectionStrings.redis
        "redis-url" = $redisUrl
        "cosmos-endpoint" = $cosmosParts['AccountEndpoint']
        "cosmos-key" = $cosmosParts['AccountKey']
        "failure-injection-enabled" = "false"
    }
    
    $secretArgs = @("create", "secret", "generic", "otel-demo-shared", "--namespace=otel-demo")
    foreach ($entry in $secretData.GetEnumerator()) {
        $secretArgs += "--from-literal=$($entry.Key)=$($entry.Value)"
    }
    $secretArgs += "--dry-run=client"
    $secretArgs += "-o"
    $secretArgs += "yaml"
    
    kubectl @secretArgs | kubectl apply -f -
    
    # Update K8s manifests with correct ACR reference and apply
    $k8sDir = Join-Path $repoRoot "k8s"
    $tempManifestsDir = Join-Path ([System.IO.Path]::GetTempPath()) ("k8s-manifests-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempManifestsDir | Out-Null
    
    try {
        $servicesToDeploy = @("order-service", "payment-service", "event-processor")
        if ($IncludeNotificationService) {
            $servicesToDeploy += "notification-service"
        }
        
        foreach ($serviceName in $servicesToDeploy) {
            $sourceManifest = Join-Path $k8sDir "$serviceName.yaml"
            if (-not (Test-Path $sourceManifest)) {
                Write-Warning "Manifest not found: $sourceManifest"
                continue
            }
            
            Write-Host "  → Deploying $serviceName to AKS" -ForegroundColor Yellow
            
            # Read manifest and replace image reference
            $manifestContent = Get-Content $sourceManifest -Raw
            $manifestContent = $manifestContent -replace 'image:\s*acroteldemodev1l009e\.azurecr\.io/[^:]+:latest', "image: $containerImagePrefix/$($serviceName):$DockerTag"
            
            $tempManifest = Join-Path $tempManifestsDir "$serviceName.yaml"
            $manifestContent | Set-Content -Path $tempManifest -NoNewline
            
            kubectl apply -f $tempManifest
        }
        
        Write-Host "  → Waiting for services to be ready..." -ForegroundColor Yellow
        Start-Sleep -Seconds 10
        
        # Get service IPs
        Write-Host "  → Retrieving AKS service endpoints" -ForegroundColor Yellow
        $orderServiceIp = kubectl get service order-service -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        $paymentServiceIp = kubectl get service payment-service -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        $eventProcessorIp = kubectl get service event-processor -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
        
        # Wait for load balancer IPs to be assigned (up to 3 minutes)
        $maxWaitSeconds = 180
        $waitInterval = 10
        $elapsed = 0
        
        while ((-not $orderServiceIp -or -not $paymentServiceIp) -and $elapsed -lt $maxWaitSeconds) {
            Write-Host "    Waiting for load balancer IPs to be assigned... ($elapsed/$maxWaitSeconds seconds)" -ForegroundColor Yellow
            Start-Sleep -Seconds $waitInterval
            $elapsed += $waitInterval
            
            if (-not $orderServiceIp) {
                $orderServiceIp = kubectl get service order-service -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
            }
            if (-not $paymentServiceIp) {
                $paymentServiceIp = kubectl get service payment-service -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
            }
            if (-not $eventProcessorIp) {
                $eventProcessorIp = kubectl get service event-processor -n otel-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>$null
            }
        }
        
        if ($orderServiceIp) { Write-Host "    Order Service: http://${orderServiceIp}:8080" -ForegroundColor Green }
        if ($paymentServiceIp) { Write-Host "    Payment Service: http://${paymentServiceIp}:3000" -ForegroundColor Green }
        if ($eventProcessorIp) { Write-Host "    Event Processor: http://${eventProcessorIp}:8001" -ForegroundColor Green }
        
        # Update API Gateway with actual AKS service IPs
        if ($orderServiceIp -and $paymentServiceIp) {
            Write-Host "  → Updating API Gateway with AKS service endpoints" -ForegroundColor Yellow
            
            $aksOrderServiceUrl = "http://${orderServiceIp}:8080"
            $aksPaymentServiceUrl = "http://${paymentServiceIp}:3000"
            
            $apiGatewayUpdateScript = @"
#!/bin/bash
set -euo pipefail
echo 'Updating API Gateway configuration'
docker stop api-gateway >/dev/null 2>&1 || true
docker rm api-gateway >/dev/null 2>&1 || true
docker run -d \
  --name api-gateway \
  --restart unless-stopped \
  --network host \
  -e ASPNETCORE_ENVIRONMENT='Production' \
  -e ASPNETCORE_URLS='http://+:5000' \
  -e ApplicationInsights__ConnectionString='$appInsightsConnectionString' \
  -e ConnectionStrings__DefaultConnection='$($connectionStrings.sql_database)' \
  -e Redis__ConnectionString='$($connectionStrings.redis)' \
  -e EventHub__ConnectionString='$($connectionStrings.eventhub_orders)' \
  -e EventHub__Name='orders' \
  -e Services__OrderService__BaseUrl='$aksOrderServiceUrl' \
  -e Services__InventoryService__BaseUrl='$inventoryBaseUrl' \
  -e Services__PaymentService__BaseUrl='$aksPaymentServiceUrl' \
  -e FailureInjection__Enabled='false' \
  $containerImagePrefix/api-gateway:$DockerTag
echo 'API Gateway updated with AKS endpoints'
"@
            
            az vm run-command invoke `
                --resource-group $resourceGroup `
                --name $vmNames[$apiGatewayVmIndex] `
                --command-id RunShellScript `
                --scripts $apiGatewayUpdateScript | Out-Null
        } else {
            Write-Warning "Could not retrieve AKS service IPs. API Gateway may not be able to reach AKS services."
        }
        
    } finally {
        if (Test-Path $tempManifestsDir) {
            Remove-Item $tempManifestsDir -Recurse -Force
        }
    }
}

# Update Frontend App Service settings with actual service endpoints
if ($frontendWebAppName) {
    Write-Step "Configuring frontend App Service with service endpoints"
    
    # Use AKS service IPs if available, otherwise fallback to configured URLs
    $finalApiGatewayUrl = $apiGatewayUrl
    $finalInventoryUrl = $inventoryServiceUrl
    $finalOrderUrl = if ($orderServiceIp) { "http://${orderServiceIp}:8080" } else { $orderServiceUrl }
    $finalPaymentUrl = if ($paymentServiceIp) { "http://${paymentServiceIp}:3000" } else { $paymentServiceUrl }
    $finalEventProcessorUrl = if ($eventProcessorIp) { "http://${eventProcessorIp}:8001" } else { $eventProcessorUrl }
    
    $frontendAppSettings = [ordered]@{}
    if ($finalApiGatewayUrl) { 
        $frontendAppSettings["API_GATEWAY_URL"] = $finalApiGatewayUrl 
        $frontendAppSettings["REACT_APP_API_GATEWAY_URL"] = $finalApiGatewayUrl
    }
    if ($finalInventoryUrl) { $frontendAppSettings["INVENTORY_SERVICE_URL"] = $finalInventoryUrl }
    if ($finalOrderUrl) { $frontendAppSettings["ORDER_SERVICE_URL"] = $finalOrderUrl }
    if ($finalPaymentUrl) { $frontendAppSettings["PAYMENT_SERVICE_URL"] = $finalPaymentUrl }
    if ($finalEventProcessorUrl) { $frontendAppSettings["EVENT_PROCESSOR_URL"] = $finalEventProcessorUrl }
    $frontendAppSettings["WEBSITE_VNET_ROUTE_ALL"] = "1"
    $frontendAppSettings["WEBSITE_DNS_SERVER"] = "168.63.129.16"
    
    if ($frontendAppSettings.Count -gt 0) {
        $settingsArgs = @(
            "webapp", "config", "appsettings", "set",
            "--resource-group", $resourceGroup,
            "--name", $frontendWebAppName,
            "--settings"
        )
        
        foreach ($entry in $frontendAppSettings.GetEnumerator()) {
            $settingsArgs += ("{0}={1}" -f $entry.Key, $entry.Value)
        }
        
        az @settingsArgs | Out-Null
        Write-Host "  Frontend configured with service endpoints" -ForegroundColor Green
    }
}

if (-not $SkipFrontend) {
    if (-not $frontendWebAppName) {
        Write-Warning "Terraform outputs did not include a frontend web app name. Skipping App Service deployment."
    } elseif (-not (Test-Path $frontendSource)) {
        Write-Warning "Frontend source directory not found at $frontendSource."
    } else {
        Require-Tool -Tool "npm"
        Write-Step "Updating frontend App Service"
        $stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("frontend-simple-staging-" + [System.Guid]::NewGuid().ToString("N"))
        $tempZip = Join-Path ([System.IO.Path]::GetTempPath()) ("frontend-simple-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
        if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
        if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }

        try {
            New-Item -ItemType Directory -Path $stagingDir | Out-Null
            Copy-Item -Path (Join-Path $frontendSource '*') -Destination $stagingDir -Recurse -Force

            Push-Location $stagingDir
            try {
                Write-Host "  Installing frontend dependencies (production only)" -ForegroundColor Yellow
                if (Test-Path "package-lock.json") {
                    npm ci --omit=dev --no-audit --no-fund
                } else {
                    npm install --production --no-audit --no-fund
                }
            } finally {
                Pop-Location
            }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $tempZip)

            $deployArgs = @(
                "webapp", "deploy",
                "--resource-group", $resourceGroup,
                "--name", $frontendWebAppName,
                "--src-path", $tempZip,
                "--type", "zip",
                "--restart", "true"
            )

            if ($FrontendDeployTimeoutSeconds -gt 0) {
                $deployArgs += @("--timeout", $FrontendDeployTimeoutSeconds)
            }

            az @deployArgs | Out-Null
            try {
                Wait-AppServiceReady -ResourceGroup $resourceGroup -WebAppName $frontendWebAppName -TimeoutSeconds $FrontendWarmupTimeoutSeconds -PollIntervalSeconds $FrontendWarmupPollSeconds
            } catch {
                Write-Warning $_.Exception.Message
            }
        } finally {
            if (Test-Path $tempZip) { Remove-Item $tempZip -Force }
            if (Test-Path $stagingDir) { Remove-Item $stagingDir -Recurse -Force }
        }
    }
} else {
    Write-Step "Skipping frontend deployment"
}

Write-Step "Deployment summary"
Write-Host ("Resource group      : {0}" -f $resourceGroup)
Write-Host ("Container registry  : {0}" -f $acrLoginServer)
Write-Host ("VMs                 : {0}" -f ($vmNames -join ', '))
if ($vmPublicIps.Count -gt 0) {
    for ($i = 0; $i -lt $vmNames.Count; $i++) {
        $ip = if ($vmPublicIps.Count -gt $i) { $vmPublicIps[$i] } else { "(private)" }
        Write-Host ("  - {0} => {1}" -f $vmNames[$i], $ip)
    }
}
if ($frontendUrls) {
    Write-Host "Frontend endpoints:"
    if ($frontendUrls -is [System.Collections.IDictionary]) {
        foreach ($key in $frontendUrls.Keys) {
            Write-Host ("  - {0}: {1}" -f $key, $frontendUrls[$key])
        }
    } elseif ($frontendUrls.PSObject -and $frontendUrls.PSObject.Properties) {
        foreach ($prop in $frontendUrls.PSObject.Properties) {
            Write-Host ("  - {0}: {1}" -f $prop.Name, $prop.Value)
        }
    } else {
        Write-Host ("  - {0}" -f $frontendUrls)
    }
}

Write-Host "`nAll tasks complete." -ForegroundColor Green
