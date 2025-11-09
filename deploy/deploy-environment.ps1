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
    [string]$AppInsightsConnectionString,
    [string]$AksAppInsightsConnectionString,
    [switch]$SkipInfrastructure,
    [switch]$SkipContainers,
    [switch]$SkipAKS,
    [switch]$SkipVmDeployment,
    [switch]$SkipFrontend,
    [switch]$SkipFunctionApp,
    [switch]$SkipNotificationService,
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
$frontendSource = Join-Path $repoRoot "services/frontend"

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

# Frontend: Full connection string for Browser SDK
$frontendAppInsightsConnectionString = if ($AppInsightsConnectionString) { $AppInsightsConnectionString } else { $terraformOutput.application_insights_connection_string.value }

# VM Services: Extract Application ID for microsoft.applicationId resource attribute (telemetry goes through OTLP->AMA->DCR)
$vmAppInsightsApplicationId = if ($frontendAppInsightsConnectionString -match 'ApplicationId=([a-f0-9\-]+)') {
    $matches[1]
} else {
    Write-Warning "Could not extract VM Application ID from connection string. Falling back to Terraform output."
    $terraformOutput.application_insights_application_id.value
}

# AKS Services: Full connection string for Instrumentation CR (Java auto-instrumentation), and extract Application ID for other services
$aksAppInsightsConnectionString = if ($AksAppInsightsConnectionString) { $AksAppInsightsConnectionString } else { $frontendAppInsightsConnectionString }
$aksAppInsightsApplicationId = if ($aksAppInsightsConnectionString -match 'ApplicationId=([a-f0-9\-]+)') {
    $matches[1]
} else {
    Write-Warning "Could not extract AKS Application ID from connection string. Using VM Application ID."
    $vmAppInsightsApplicationId
}

Write-Host "Frontend App Insights (full connection string): $($frontendAppInsightsConnectionString.Substring(0, 50))..." -ForegroundColor Green
Write-Host "VM Services Application ID (for resource attribute): $vmAppInsightsApplicationId" -ForegroundColor Green
Write-Host "AKS Instrumentation CR (full connection string): $($aksAppInsightsConnectionString.Substring(0, 50))..." -ForegroundColor Green
Write-Host "AKS Services Application ID (for resource attribute): $aksAppInsightsApplicationId" -ForegroundColor Green

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

# Include notification service by default (unless explicitly skipped)
if (-not $SkipNotificationService) {
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

# Deploy Order, Payment, and Event Processor services to AKS FIRST (to get NodePort URLs)
if (-not $SkipAKS) {
    $aksClusterName = $terraformOutput.aks_cluster_name.value
    $aksNodeIp = $null
    $orderServicePort = $null
    $paymentServicePort = $null
    $eventProcessorPort = $null

    if (-not $aksClusterName) {
        Write-Warning "AKS cluster name not found in Terraform outputs. Will use placeholder URLs for VM deployment."
    } else {
        Write-Step "Deploying services to AKS cluster: $aksClusterName"
    
    # Get AKS credentials
    Write-Host "  → Configuring kubectl for AKS cluster" -ForegroundColor Yellow
    az aks get-credentials --resource-group $resourceGroup --name $aksClusterName --overwrite-existing --admin | Out-Null
    
    # Create namespace
    Write-Host "  → Creating otel-demo namespace" -ForegroundColor Yellow
    kubectl create namespace otel-demo --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply Instrumentation Custom Resource for Azure Monitor app monitoring
    Write-Host "  → Applying Azure Monitor Instrumentation CR for Order Service (Java auto-instrumentation)" -ForegroundColor Yellow
    $instrumentationManifest = Join-Path $repoRoot "k8s/instrumentation-otel-demo.yaml"
    if (Test-Path $instrumentationManifest) {
        # Read manifest and replace connection string placeholder
        $instrumentationContent = Get-Content $instrumentationManifest -Raw
        $instrumentationContent = $instrumentationContent -replace '__APP_INSIGHTS_CONNECTION_STRING__', $aksAppInsightsConnectionString
        
        $tempInstrumentationFile = Join-Path ([System.IO.Path]::GetTempPath()) "instrumentation-otel-demo-$([System.Guid]::NewGuid().ToString('N')).yaml"
        $instrumentationContent | Set-Content -Path $tempInstrumentationFile -NoNewline
        
        kubectl apply -f $tempInstrumentationFile
        Remove-Item $tempInstrumentationFile -Force -ErrorAction SilentlyContinue
    } else {
        Write-Warning "Instrumentation manifest not found: $instrumentationManifest. Skipping Azure Monitor app monitoring setup."
    }

    # Associate managed DCR with AKS cluster for OTLP collection
    Write-Host "  → Associating managed DCR with AKS cluster for OTLP collection" -ForegroundColor Yellow
    try {
        # Get the Application Insights resource to find the managed DCR
        $aksAppInsightsResourceId = az monitor app-insights component show --app $aksAppInsightsApplicationId --query id -o tsv 2>$null
        
        if ($aksAppInsightsResourceId) {
            Write-Host "    Discovering managed resource group and DCR for Application Insights..." -ForegroundColor Gray
            
            # Query all resource groups to find the one managed by this App Insights
            # Managed resource groups typically have the App Insights resource ID in their tags or properties
            $allResourceGroups = az group list -o json 2>$null | ConvertFrom-Json
            $managedResourceGroup = $null
            
            foreach ($rg in $allResourceGroups) {
                # Check if this RG is managed (has managedBy property pointing to the App Insights resource)
                if ($rg.managedBy -eq $aksAppInsightsResourceId) {
                    $managedResourceGroup = $rg.name
                    Write-Host "    Found managed resource group: $managedResourceGroup" -ForegroundColor Gray
                    break
                }
            }
            
            $managedDcrId = $null
            
            if ($managedResourceGroup) {
                # Find the managed DCR in the managed resource group
                $managedDcrId = az monitor data-collection rule list --resource-group $managedResourceGroup --query "[?contains(name, 'managed')].id" -o tsv 2>$null
                if ($managedDcrId) {
                    Write-Host "    Found managed DCR in resource group: $managedDcrId" -ForegroundColor Gray
                }
            }
            
            # Fallback: If we didn't find it via managed RG, search all DCRs for one with this App Insights as destination
            if (-not $managedDcrId) {
                Write-Host "    Searching all DCRs for managed DCR..." -ForegroundColor Gray
                $allDcrs = az monitor data-collection rule list -o json 2>$null | ConvertFrom-Json
                
                foreach ($dcr in $allDcrs) {
                    # Look for DCR with "managed" in name and associated with this App Insights
                    if ($dcr.name -match 'managed' -and $dcr.destinations.applicationInsights) {
                        foreach ($aiDest in $dcr.destinations.applicationInsights.PSObject.Properties) {
                            if ($aiDest.Value.applicationInsightsId -eq $aksAppInsightsResourceId) {
                                $managedDcrId = $dcr.id
                                Write-Host "    Found managed DCR: $($dcr.name)" -ForegroundColor Gray
                                break
                            }
                        }
                        if ($managedDcrId) { break }
                    }
                }
            }
            
            if ($managedDcrId) {
                # Get AKS cluster resource ID
                $aksResourceId = az aks show --name $aksClusterName --resource-group $resourceGroup --query id -o tsv
                
                # Check if association already exists
                $existingAssociation = az monitor data-collection rule association list --resource $aksResourceId --query "[?dataCollectionRuleId=='$managedDcrId'].name" -o tsv 2>$null
                
                if (-not $existingAssociation) {
                    Write-Host "    Creating DCR association: $managedDcrId" -ForegroundColor Gray
                    az monitor data-collection rule association create `
                        --name "ManagedBackendServicesDCRAssociation" `
                        --resource $aksResourceId `
                        --rule-id $managedDcrId `
                        --output none
                    Write-Host "    ✓ DCR association created successfully" -ForegroundColor Green
                    
                    # Restart ama-logs to pick up the DCR configuration
                    Write-Host "    Restarting ama-logs daemonset to enable OTLP receivers..." -ForegroundColor Gray
                    kubectl rollout restart daemonset/ama-logs -n kube-system | Out-Null
                    Write-Host "    ✓ ama-logs restarted" -ForegroundColor Green
                } else {
                    Write-Host "    DCR association already exists, skipping" -ForegroundColor Gray
                }
            } else {
                Write-Warning "  Could not find managed DCR for Application Insights. OTLP collection may not work."
            }
        } else {
            Write-Warning "  Could not find Application Insights resource. OTLP collection may not work."
        }
    } catch {
        Write-Warning "  Failed to associate managed DCR with AKS cluster: $_"
    }
    
    # Create Kubernetes secret with connection strings
    Write-Host "  → Creating secrets" -ForegroundColor Yellow
    # Note: Most AKS services only need ApplicationId for resource attribute (not full connection string)
    # Order Service is an exception - it needs full connection string for Java auto-instrumentation
    $secretData = @{
        "application-insights-application-id" = $aksAppInsightsApplicationId
        "application-insights-connection-string" = $aksAppInsightsConnectionString
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
        
        # Include notification service by default (unless explicitly skipped)
        if (-not $SkipNotificationService) {
            $servicesToDeploy += "notification-service"
        }
        
        foreach ($serviceName in $servicesToDeploy) {
            $sourceManifest = Join-Path $k8sDir "$serviceName.yaml"
            if (-not (Test-Path $sourceManifest)) {
                Write-Warning "Manifest not found: $sourceManifest"
                continue
            }
            
            Write-Host "  → Deploying $serviceName to AKS" -ForegroundColor Yellow
            
            # Read manifest and replace ACR placeholder with actual registry
            $manifestContent = Get-Content $sourceManifest -Raw
            $manifestContent = $manifestContent -replace '__ACR_LOGIN_SERVER__', $acrLoginServer
            
            $tempManifest = Join-Path $tempManifestsDir "$serviceName.yaml"
            $manifestContent | Set-Content -Path $tempManifest -NoNewline
            
            kubectl apply -f $tempManifest
            
            # Force rollout restart to ensure latest image is pulled
            kubectl rollout restart deployment/$serviceName -n otel-demo 2>$null
        }
        
        Write-Host "  → Waiting for deployments to roll out..." -ForegroundColor Yellow
        
        # Wait for rollouts to complete
        $servicesToWait = @("order-service", "payment-service", "event-processor")
        if (-not $SkipNotificationService) {
            $servicesToWait += "notification-service"
        }
        
        foreach ($serviceName in $servicesToWait) {
            Write-Host "    Waiting for $serviceName..." -ForegroundColor Gray
            kubectl rollout status deployment/$serviceName -n otel-demo --timeout=5m 2>$null
        }
        
        Start-Sleep -Seconds 5
        
        # Get AKS node IP for NodePort access (services are exposed via NodePort, not LoadBalancer)
        Write-Host "  → Retrieving AKS node IP for service access" -ForegroundColor Yellow
        $aksNodeIp = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>$null
        
        if ($aksNodeIp) {
            Write-Host "    AKS Node IP: $aksNodeIp" -ForegroundColor Green
            
            # Services are exposed via NodePort (defined in manifests)
            $orderServicePort = kubectl get service order-service -n otel-demo -o jsonpath='{.spec.ports[0].nodePort}' 2>$null
            $paymentServicePort = kubectl get service payment-service -n otel-demo -o jsonpath='{.spec.ports[0].nodePort}' 2>$null
            $eventProcessorPort = kubectl get service event-processor -n otel-demo -o jsonpath='{.spec.ports[0].nodePort}' 2>$null
            $notificationServicePort = if (-not $SkipNotificationService) { 
                kubectl get service notification-service -n otel-demo -o jsonpath='{.spec.ports[0].nodePort}' 2>$null 
            } else { $null }
            
            $orderServiceUrl = "http://${aksNodeIp}:${orderServicePort}"
            $paymentServiceUrl = "http://${aksNodeIp}:${paymentServicePort}"
            $eventProcessorUrl = "http://${aksNodeIp}:${eventProcessorPort}"
            $notificationServiceUrl = if ($notificationServicePort) { "http://${aksNodeIp}:${notificationServicePort}" } else { $null }
            
            Write-Host "    Order Service: $orderServiceUrl" -ForegroundColor Green
            Write-Host "    Payment Service: $paymentServiceUrl" -ForegroundColor Green
            Write-Host "    Event Processor: $eventProcessorUrl" -ForegroundColor Green
            if ($notificationServiceUrl) {
                Write-Host "    Notification Service: $notificationServiceUrl" -ForegroundColor Green
            }
        } else {
            Write-Warning "Could not retrieve AKS node IP. API Gateway will use placeholder URLs."
        }
        
    } finally {
        if (Test-Path $tempManifestsDir) {
            Remove-Item $tempManifestsDir -Recurse -Force
        }
    }
    }
} else {
    Write-Step "Skipping AKS deployment"
    # Set variables to null so VM deployment knows AKS was skipped
    $aksNodeIp = $null
    $orderServicePort = $null
    $paymentServicePort = $null
    $eventProcessorPort = $null
    $notificationServicePort = $null
    $notificationServiceUrl = $null
}

# Now deploy to VMs with the actual AKS NodePort URLs
if (-not $SkipVmDeployment) {
    if ($vmNames.Count -eq 0) {
        throw "No virtual machine outputs were found in Terraform state."
    }

    Write-Step "Deploying containers to virtual machines (API Gateway and Inventory only)"

    $inventoryVmIndex = 0
    $apiGatewayVmIndex = if ($vmNames.Count -gt 1) { 1 } else { 0 }

    # Note: Order, Payment, and Event Processor services are deployed to AKS

    $vmServiceMap = @{}
    
    # VM1: Inventory Service
    $vmServiceMap[$inventoryVmIndex] = New-Object System.Collections.Generic.List[object]
    $vmServiceMap[$inventoryVmIndex].Add((New-ServiceConfig -Name "inventory-service" -Image "$containerImagePrefix/inventory-service:$DockerTag" -Ports @("3001:3001") -Environment @{
        "NODE_ENV" = "production"
        "PORT" = "3001"
        "SERVICE_NAME" = "inventory-service"
        "SERVICE_VERSION" = "1.0.0"
        "APPLICATION_INSIGHTS_APPLICATION_ID" = $vmAppInsightsApplicationId
        "REDIS_URL" = $redisUrl
        "OTEL_EXPORTER_OTLP_ENDPOINT" = "http://localhost:4319"
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" = "http://localhost:4319"
        "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" = "http://localhost:4317"
        "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT" = "http://localhost:4319"
    }))

    # VM2: API Gateway (will connect to AKS-hosted services)
    if (-not $vmServiceMap.ContainsKey($apiGatewayVmIndex)) {
        $vmServiceMap[$apiGatewayVmIndex] = New-Object System.Collections.Generic.List[object]
    }

    # Use actual NodePort URLs from AKS deployment above, fallback to Kubernetes DNS if not available
    $aksOrderServiceUrl = if ($orderServiceUrl) { $orderServiceUrl } else { "http://order-service.otel-demo.svc.cluster.local:8080" }
    $aksPaymentServiceUrl = if ($paymentServiceUrl) { $paymentServiceUrl } else { "http://payment-service.otel-demo.svc.cluster.local:3000" }
    $aksEventProcessorUrl = if ($eventProcessorUrl) { $eventProcessorUrl } else { "http://event-processor.otel-demo.svc.cluster.local:8000" }
    $aksNotificationServiceUrl = if ($notificationServiceUrl) { $notificationServiceUrl } else { "http://notification-service.otel-demo.svc.cluster.local:8080" }
    # Use inventory service URL from service discovery, fallback to VM1 private IP
    $inventoryBaseUrl = if ($inventoryServiceUrl) { $inventoryServiceUrl } else { "http://${inventoryVmPrivateIp}:3001" }

    # API Gateway Configuration - Acts as orchestrator calling downstream services
    # NO direct database access - calls Order Service for order operations
    $apiGatewayEnv = @{
        "ASPNETCORE_ENVIRONMENT" = "Production"
        "ASPNETCORE_URLS" = "http://+:5000"
        "APPLICATION_INSIGHTS_APPLICATION_ID" = $vmAppInsightsApplicationId
        "Redis__ConnectionString" = $connectionStrings.redis
        "EventHub__ConnectionString" = $connectionStrings.eventhub_orders
        "EventHub__Name" = "orders"
        "Services__OrderService__BaseUrl" = $aksOrderServiceUrl
        "Services__InventoryService__BaseUrl" = $inventoryBaseUrl
        "Services__PaymentService__BaseUrl" = $aksPaymentServiceUrl
        "Services__EventProcessor__BaseUrl" = $aksEventProcessorUrl
        "FailureInjection__Enabled" = "false"
        "OTEL_EXPORTER_OTLP_ENDPOINT" = "http://localhost:4319"
        "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" = "http://localhost:4319"
        "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" = "http://localhost:4317"
        "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT" = "http://localhost:4319"
    }
    
    # Add notification service URL if enabled
    if (-not $SkipNotificationService) {
        $apiGatewayEnv["Services__NotificationService__BaseUrl"] = $aksNotificationServiceUrl
    }
    
    $vmServiceMap[$apiGatewayVmIndex].Add((New-ServiceConfig -Name "api-gateway" -Image "$containerImagePrefix/api-gateway:$DockerTag" -UseHostNetwork $true -Environment $apiGatewayEnv))

    # SSH key path for passwordless authentication
    $sshKeyPath = Join-Path $env:USERPROFILE ".ssh\azure_vm_key"
    $sshOptions = @("-o", "StrictHostKeyChecking=no")
    if (Test-Path $sshKeyPath) {
        $sshOptions += @("-i", $sshKeyPath)
        Write-Host "  Using SSH key: $sshKeyPath" -ForegroundColor Gray
    } else {
        Write-Host "  ⚠ SSH key not found at $sshKeyPath, will use password authentication" -ForegroundColor Yellow
    }

    foreach ($vmIndex in $vmServiceMap.Keys) {
        $vmName = $vmNames[$vmIndex]
        $vmIp = if ($vmPublicIps.Count -gt $vmIndex) { $vmPublicIps[$vmIndex] } else { "(private)" }
        Write-Host "  → Deploying services to $vmName ($vmIp)" -ForegroundColor Yellow

        try {
            # Step 1: Verify Docker is installed and running
            Write-Host "    → Checking Docker status..." -ForegroundColor Cyan
            $dockerCheck = ssh @sshOptions azureuser@$vmIp "docker --version && systemctl is-active docker" 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Host "    ✗ Docker not ready on $vmName" -ForegroundColor Red
                throw "Docker is not running on $vmName. Please ensure VM initialization completed successfully."
            }
            Write-Host "    ✓ Docker is running" -ForegroundColor Green

            # Step 2: Login to ACR
            Write-Host "    → Logging into ACR..." -ForegroundColor Cyan
            $loginCmd = "echo '$acrPasswordBase64' | base64 -d | docker login $acrLoginServer --username $acrAdminUsername --password-stdin 2>&1"
            $loginResult = ssh @sshOptions azureuser@$vmIp $loginCmd
            if ($LASTEXITCODE -ne 0) {
                Write-Host "    ✗ ACR login failed:" -ForegroundColor Red
                Write-Host "      $loginResult" -ForegroundColor Red
                throw "Failed to login to ACR from $vmName"
            }
            Write-Host "    ✓ ACR login successful" -ForegroundColor Green

            # Step 3: Deploy each service
            foreach ($service in $vmServiceMap[$vmIndex]) {
                Write-Host "    → Deploying $($service.Name)..." -ForegroundColor Cyan
                
                # Pull image
                Write-Host "      Pulling image..." -ForegroundColor Gray
                $pullResult = ssh @sshOptions azureuser@$vmIp "docker pull $($service.Image) 2>&1"
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "    ✗ Failed to pull image:" -ForegroundColor Red
                    Write-Host "      $pullResult" -ForegroundColor Red
                    throw "Failed to pull $($service.Image) on $vmName"
                }
                Write-Host "      ✓ Image pulled" -ForegroundColor Green

                # Stop and remove existing container if it exists
                Write-Host "      Stopping existing container..." -ForegroundColor Gray
                ssh @sshOptions azureuser@$vmIp "docker stop $($service.Name) 2>/dev/null || true; docker rm $($service.Name) 2>/dev/null || true" | Out-Null

                # Build docker run command
                $runParts = @("docker run -d")
                $runParts += "--name $($service.Name)"
                $runParts += "--restart unless-stopped"

                if ($service.UseHostNetwork) {
                    $runParts += "--network host"
                }

                foreach ($port in $service.Ports) {
                    $runParts += "-p $port"
                }

                foreach ($entry in $service.Environment.GetEnumerator()) {
                    $envValue = $entry.Value -replace "'", "'\''"  # Escape single quotes
                    $runParts += "-e '$($entry.Key)=$envValue'"
                }

                $runParts += $($service.Image)
                $dockerRunCmd = $runParts -join ' '

                # Start container
                Write-Host "      Starting container..." -ForegroundColor Gray
                $runResult = ssh @sshOptions azureuser@$vmIp $dockerRunCmd 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Host "    ✗ Failed to start container:" -ForegroundColor Red
                    Write-Host "      $runResult" -ForegroundColor Red
                    throw "Failed to start $($service.Name) on $vmName"
                }
                
                # Verify container is running
                Start-Sleep -Seconds 2
                $containerStatus = ssh @sshOptions azureuser@$vmIp "docker ps --filter name=$($service.Name) --format '{{.Status}}'" 2>&1
                if ($containerStatus -match "Up") {
                    Write-Host "    ✓ $($service.Name) is running" -ForegroundColor Green
                } else {
                    Write-Host "    ⚠ $($service.Name) may not be healthy. Status: $containerStatus" -ForegroundColor Yellow
                    # Get logs for debugging
                    $logs = ssh @sshOptions azureuser@$vmIp "docker logs $($service.Name) --tail 20 2>&1"
                    Write-Host "      Recent logs:" -ForegroundColor Gray
                    $logs | ForEach-Object { Write-Host "        $_" -ForegroundColor Gray }
                }
            }

            # Step 4: Show final container status
            Write-Host "    → Final container status:" -ForegroundColor Cyan
            $finalStatus = ssh @sshOptions azureuser@$vmIp "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>&1
            $finalStatus | ForEach-Object { Write-Host "      $_" -ForegroundColor White }

        }
        catch {
            Write-Host "    ✗ Error deploying to $vmName`: $_" -ForegroundColor Red
            throw
        }
    }
} else {
    Write-Step "Skipping VM container deployment"
}

# Update Frontend App Service settings with actual service endpoints
if ($frontendWebAppName) {
    Write-Step "Configuring frontend App Service with service endpoints"
    
    # Frontend should ONLY use API Gateway - not call backend services directly
    # API Gateway orchestrates calls to Order, Payment, Event Processor services
    $finalApiGatewayUrl = $apiGatewayUrl
    $finalInventoryUrl = $inventoryServiceUrl
    
    $frontendAppSettings = [ordered]@{}
    if ($finalApiGatewayUrl) { 
        $frontendAppSettings["API_GATEWAY_URL"] = $finalApiGatewayUrl 
        $frontendAppSettings["REACT_APP_API_GATEWAY_URL"] = $finalApiGatewayUrl
    }
    # Only set Inventory Service URL if frontend needs direct inventory queries
    if ($finalInventoryUrl) { 
        $frontendAppSettings["INVENTORY_SERVICE_URL"] = $finalInventoryUrl 
        $frontendAppSettings["REACT_APP_INVENTORY_SERVICE_URL"] = $finalInventoryUrl
    }
    # DO NOT set ORDER_SERVICE_URL, PAYMENT_SERVICE_URL, EVENT_PROCESSOR_URL
    # Frontend should route all order/payment requests through API Gateway
    
    # Add Application Insights for frontend telemetry
    if ($appInsightsConnectionString) {
        $frontendAppSettings["APPLICATIONINSIGHTS_CONNECTION_STRING"] = $appInsightsConnectionString
    }
    
    # VNet integration settings
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
            # Build the React app first
            Push-Location $frontendSource
            try {
                Write-Host "  Installing frontend dependencies and building React app" -ForegroundColor Yellow
                npm install --no-audit --no-fund
                Write-Host "  Building React production bundle" -ForegroundColor Yellow
                npm run build
            } finally {
                Pop-Location
            }

            # Create staging directory and copy build output + server files
            New-Item -ItemType Directory -Path $stagingDir | Out-Null
            
            # Copy the build output
            $buildDir = Join-Path $frontendSource "build"
            if (-not (Test-Path $buildDir)) {
                throw "React build directory not found at $buildDir. Build may have failed."
            }
            Copy-Item -Path (Join-Path $buildDir '*') -Destination $stagingDir -Recurse -Force
            
            # Copy server files with minimal package.json (only server dependencies)
            Copy-Item -Path (Join-Path $frontendSource "server.js") -Destination $stagingDir -Force
            Copy-Item -Path (Join-Path $frontendSource "server-package.json") -Destination (Join-Path $stagingDir "package.json") -Force

            # Install minimal server dependencies
            Push-Location $stagingDir
            try {
                Write-Host "  Installing minimal server dependencies" -ForegroundColor Yellow
                npm install --production --no-audit --no-fund
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

# Deploy Synthetic Traffic Function App
if (-not $SkipFunctionApp) {
    $trafficFunctionAppName = $terraformOutput.traffic_function_app_name.value
    if ($trafficFunctionAppName) {
    Require-Tool -Tool "dotnet"
    Write-Step "Deploying Synthetic Traffic Function App"
    
    $functionSource = Join-Path $repoRoot "services/synthetic-traffic-function"
    if (-not (Test-Path $functionSource)) {
        Write-Warning "Synthetic traffic function source not found at $functionSource. Skipping."
    } else {
        $functionPublishDir = Join-Path ([System.IO.Path]::GetTempPath()) ("function-publish-" + [System.Guid]::NewGuid().ToString("N"))
        $functionZip = Join-Path ([System.IO.Path]::GetTempPath()) ("function-deploy-" + [System.Guid]::NewGuid().ToString("N") + ".zip")
        
        if (Test-Path $functionZip) { Remove-Item $functionZip -Force }
        if (Test-Path $functionPublishDir) { Remove-Item $functionPublishDir -Recurse -Force }
        
        try {
            Write-Host "  Building and publishing .NET function app..." -ForegroundColor Yellow
            Push-Location $functionSource
            try {
                # Publish the function app to a temporary directory
                dotnet publish --configuration Release --output $functionPublishDir | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    throw "dotnet publish failed with exit code $LASTEXITCODE"
                }
            } finally {
                Pop-Location
            }
            
            Write-Host "  Creating deployment package..." -ForegroundColor Yellow
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($functionPublishDir, $functionZip)
            
            Write-Host "  Deploying to Azure Function App '$trafficFunctionAppName'..." -ForegroundColor Yellow
            az functionapp deployment source config-zip `
                --resource-group $resourceGroup `
                --name $trafficFunctionAppName `
                --src $functionZip `
                --timeout 600 | Out-Null
            
            Write-Host "  Function app deployed successfully" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to deploy synthetic traffic function: $($_.Exception.Message)"
        } finally {
            if (Test-Path $functionZip) { Remove-Item $functionZip -Force }
            if (Test-Path $functionPublishDir) { Remove-Item $functionPublishDir -Recurse -Force }
        }
    }
    } else {
        Write-Host "Synthetic traffic function app not found in Terraform outputs. Skipping." -ForegroundColor Yellow
    }
} else {
    Write-Step "Skipping function app deployment"
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

# Configure kubectl and AKS RBAC permissions
Write-Step "Configuring kubectl and AKS RBAC permissions"

Write-Host "  → Getting AKS admin credentials for kubectl" -ForegroundColor Yellow
az aks get-credentials `
    --resource-group $resourceGroupName `
    --name $aksClusterName `
    --overwrite-existing `
    --admin 2>&1 | Out-Null

if ($LASTEXITCODE -eq 0) {
    Write-Host "    ✓ kubectl configured with admin credentials" -ForegroundColor Green
} else {
    Write-Warning "Failed to configure kubectl credentials"
}

Write-Host "  → Granting Azure Kubernetes Service Cluster User Role for portal access" -ForegroundColor Yellow
try {
    $currentUserId = az ad signed-in-user show --query id -o tsv
    if ($currentUserId) {
        $aksScope = "/subscriptions/$((az account show --query id -o tsv))/resourceGroups/$resourceGroupName/providers/Microsoft.ContainerService/managedClusters/$aksClusterName"
        
        az role assignment create `
            --role "Azure Kubernetes Service Cluster User Role" `
            --assignee $currentUserId `
            --scope $aksScope 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ AKS Cluster User Role assigned (you can now view namespaces in Azure Portal)" -ForegroundColor Green
        } else {
            Write-Warning "Role may already be assigned or failed to assign"
        }
    }
} catch {
    Write-Warning "Failed to assign AKS role: $_"
}

Write-Host "`nAll tasks complete." -ForegroundColor Green
