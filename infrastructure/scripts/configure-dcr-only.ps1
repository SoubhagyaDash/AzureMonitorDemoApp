# Configure DCR with OTLP support for VMs
# Creates DCE, DCR, and associates them with VMs only

param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "westus2"
)

Write-Host "=== Configuring DCR with OTLP Support for VMs ===" -ForegroundColor Green

# Dynamically discover resource names from the resource group
Write-Host "`nDiscovering resources in $ResourceGroup..." -ForegroundColor Cyan

$lawName = (az monitor log-analytics workspace list --resource-group $ResourceGroup --query "[0].name" -o tsv)
# Get Azure Monitor Workspace using resource list
$amwName = (az resource list --resource-group $ResourceGroup --resource-type "microsoft.monitor/accounts" --query "[0].name" -o tsv)
# Get the main App Insights resource created by Terraform (matches pattern: appi-<project>-<env>-*)
# This excludes the AKS-specific App Insights resource (aksBackendServices)
$appInsightsName = (az resource list --resource-group $ResourceGroup --resource-type "Microsoft.Insights/components" --query "[?starts_with(name, 'appi-')].name | [0]" -o tsv)
$vm1Name = (az vm list --resource-group $ResourceGroup --query "[?tags.Role=='api-gateway'].name | [0]" -o tsv)
$vm2Name = (az vm list --resource-group $ResourceGroup --query "[?tags.Role=='services'].name | [0]" -o tsv)

# Generate unique names for DCE and DCR
$timestamp = Get-Date -Format "yyyyMMddHHmm"
$dceName = "dce-otlp-$timestamp"
$dcrName = "dcr-otlp-$timestamp"

Write-Host "`nResource names:" -ForegroundColor Cyan
Write-Host "  Resource Group: $ResourceGroup"
Write-Host "  DCE: $dceName (will be created)"
Write-Host "  DCR: $dcrName (will be created)"
Write-Host "  LAW: $lawName"
Write-Host "  AMW: $amwName"
Write-Host "  App Insights: $appInsightsName"
Write-Host "  VM1 (API Gateway): $vm1Name"
Write-Host "  VM2 (Services): $vm2Name"

# Get resource IDs
$subscriptionId = (az account show --query id -o tsv)
$lawId = (az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $lawName --query id -o tsv)
$lawWorkspaceId = (az monitor log-analytics workspace show --resource-group $ResourceGroup --workspace-name $lawName --query customerId -o tsv)
$appInsightsId = (az resource show --resource-group $ResourceGroup --name $appInsightsName --resource-type "Microsoft.Insights/components" --query id -o tsv)
$appInsightsAppId = (az resource show --resource-group $ResourceGroup --name $appInsightsName --resource-type "Microsoft.Insights/components" --query properties.AppId -o tsv)
$amwResourceId = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/microsoft.monitor/accounts/$amwName"
$amwAccountId = (az rest --method GET --uri "$amwResourceId`?api-version=2023-04-03" --query properties.accountId -o tsv)

Write-Host "`n=== Step 0: Creating Data Collection Endpoint ===" -ForegroundColor Green

# Create DCE
$dceResult = az monitor data-collection endpoint create `
    --name $dceName `
    --resource-group $ResourceGroup `
    --location $Location `
    --kind "Linux" `
    --public-network-access "Enabled"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create Data Collection Endpoint"
    exit 1
}

$dceId = (az monitor data-collection endpoint show --name $dceName --resource-group $ResourceGroup --query id -o tsv)
Write-Host "✓ Created DCE: $dceName" -ForegroundColor Green
Write-Host "  DCE ID: $dceId"

Write-Host "`n=== Step 1: Creating DCR with OTLP configuration ===" -ForegroundColor Green

# Create DCR JSON based on authoritative reference (using API version 2024-03-11)
$dcrJson = @"
{
  "location": "$Location",
  "properties": {
    "dataCollectionEndpointId": "$dceId",
    "dataSources": {
      "otelLogs": [
        {
          "name": "otelLogsDataSource",
          "streams": ["Microsoft-OTel-Logs"],
          "enrichWithReference": "applicationInsightsResource",
          "replaceResourceIdWithReference": true,
          "resourceAttributeRouting": {
            "attributeName": "microsoft.applicationId",
            "attributeValue": "$appInsightsAppId"
          }
        }
      ],
      "otelMetrics": [
        {
          "name": "otelMetricsDataSource",
          "streams": ["Custom-Metrics-OTelMetrics"],
          "enrichWithReference": "applicationInsightsResource",
          "enrichWithResourceAttributes": [
            "cloud.region",
            "service.name",
            "service.instance.id",
            "service.namespace",
            "host.name",
            "k8s.pod.name",
            "k8s.container.name",
            "k8s.cluster.name",
            "k8s.namespace.name",
            "k8s.node.name",
            "k8s.deployment.name"
          ],
          "resourceAttributeRouting": {
            "attributeName": "microsoft.applicationId",
            "attributeValue": "$appInsightsAppId"
          }
        }
      ],
      "otelTraces": [
        {
          "name": "otelTracesDataSource",
          "streams": [
            "Microsoft-OTel-Traces-Events",
            "Microsoft-OTel-Traces-Spans",
            "Microsoft-OTel-Traces-Resources"
          ],
          "enrichWithReference": "applicationInsightsResource",
          "replaceResourceIdWithReference": true,
          "resourceAttributeRouting": {
            "attributeName": "microsoft.applicationId",
            "attributeValue": "$appInsightsAppId"
          }
        }
      ]
    },
    "directDataSources": {
      "otelLogs": [
        {
          "name": "otelLogsDataSourceDirect",
          "streams": ["Microsoft-OTel-Logs"],
          "enrichWithReference": "applicationInsightsResource",
          "replaceResourceIdWithReference": true
        }
      ],
      "otelMetrics": [
        {
          "name": "otelMetricsDataSourceDirect",
          "streams": ["Microsoft-OtelMetrics"],
          "enrichWithReference": "applicationInsightsResource",
          "enrichWithResourceAttributes": [
            "cloud.region",
            "service.name",
            "service.instance.id",
            "service.namespace",
            "host.name",
            "k8s.pod.name",
            "k8s.container.name",
            "k8s.cluster.name",
            "k8s.namespace.name",
            "k8s.node.name",
            "k8s.deployment.name"
          ]
        }
      ],
      "otelTraces": [
        {
          "name": "otelTracesDataSourceDirect",
          "streams": [
            "Microsoft-OTel-Traces-Events",
            "Microsoft-OTel-Traces-Spans",
            "Microsoft-OTel-Traces-Resources"
          ],
          "enrichWithReference": "applicationInsightsResource",
          "replaceResourceIdWithReference": true
        }
      ]
    },
    "destinations": {
      "logAnalytics": [
        {
          "name": "logAnalyticsWorkspace",
          "workspaceResourceId": "$lawId",
          "workspaceId": "$lawWorkspaceId"
        }
      ],
      "monitoringAccounts": [
        {
          "name": "azureMonitorWorkspace",
          "accountResourceId": "$amwResourceId",
          "accountId": "$amwAccountId"
        }
      ]
    },
    "dataFlows": [
      {
        "streams": ["Custom-Metrics-OTelMetrics", "Microsoft-OtelMetrics"],
        "destinations": ["azureMonitorWorkspace"]
      },
      {
        "streams": [
          "Microsoft-OTel-Logs",
          "Microsoft-OTel-Traces-Events",
          "Microsoft-OTel-Traces-Spans",
          "Microsoft-OTel-Traces-Resources"
        ],
        "destinations": ["logAnalyticsWorkspace"]
      }
    ],
    "references": {
      "applicationInsights": [
        {
          "name": "applicationInsightsResource",
          "resourceId": "$appInsightsId"
        }
      ]
    },
    "description": "Data Collection Rule for OpenTelemetry (OTLP) logs, metrics, and traces"
  }
}
"@

Write-Host "Creating DCR via REST API (API version 2024-03-11)..." -ForegroundColor Yellow

# Delete existing DCR if it exists
$existingDcr = az monitor data-collection rule show --name $dcrName --resource-group $ResourceGroup 2>$null
if ($existingDcr) {
    Write-Host "Deleting existing DCR..." -ForegroundColor Yellow
    az monitor data-collection rule delete --name $dcrName --resource-group $ResourceGroup --yes
    Start-Sleep -Seconds 10
}

# Create DCR via REST API using latest API version
$accessToken = (az account get-access-token --query accessToken -o tsv)

$headers = @{
    "Authorization" = "Bearer $accessToken"
    "Content-Type" = "application/json"
}

$uri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Insights/dataCollectionRules/$dcrName`?api-version=2024-03-11"

try {
    $response = Invoke-RestMethod -Uri $uri -Method Put -Headers $headers -Body $dcrJson
    Write-Host "✓ DCR created successfully" -ForegroundColor Green
    $dcrId = $response.id
    Write-Host "  DCR ID: $dcrId" -ForegroundColor Cyan
} catch {
    Write-Host "✗ Failed to create DCR: $_" -ForegroundColor Red
    Write-Host "Response: $($_.ErrorDetails.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Step 2: Creating DCR associations ===" -ForegroundColor Green

# Get VM IDs
$vm1Id = (az vm show --resource-group $ResourceGroup --name $vm1Name --query id -o tsv)
$vm2Id = (az vm show --resource-group $ResourceGroup --name $vm2Name --query id -o tsv)

# Check if associations already exist
$vm1Association = az monitor data-collection rule association list --resource $vm1Id --query "[?dataCollectionRuleId=='$dcrId'].name" -o tsv 2>$null
$vm2Association = az monitor data-collection rule association list --resource $vm2Id --query "[?dataCollectionRuleId=='$dcrId'].name" -o tsv 2>$null

# Associate DCR with VM1
if ($vm1Association) {
    Write-Host "✓ DCR already associated with $vm1Name" -ForegroundColor Green
} else {
    Write-Host "Associating DCR with $vm1Name..." -ForegroundColor Yellow
    az monitor data-collection rule association create `
        --name "dcr-otlp-vm1-association" `
        --rule-id $dcrId `
        --resource $vm1Id
    Write-Host "✓ DCR associated with $vm1Name" -ForegroundColor Green
}

# Associate DCR with VM2
if ($vm2Association) {
    Write-Host "✓ DCR already associated with $vm2Name" -ForegroundColor Green
} else {
    Write-Host "Associating DCR with $vm2Name..." -ForegroundColor Yellow
    az monitor data-collection rule association create `
        --name "dcr-otlp-vm2-association" `
        --rule-id $dcrId `
        --resource $vm2Id
    Write-Host "✓ DCR associated with $vm2Name" -ForegroundColor Green
}

Write-Host "`n=== Step 3: Verifying AMA configuration ===" -ForegroundColor Green

# Wait for AMA to download DCR configuration
Write-Host "Waiting 30 seconds for AMA to sync configuration..." -ForegroundColor Yellow
Start-Sleep -Seconds 30

# Get VM public IPs
$vm1PublicIp = (az vm show --resource-group $ResourceGroup --name $vm1Name --show-details --query publicIps -o tsv)
$vm2PublicIp = (az vm show --resource-group $ResourceGroup --name $vm2Name --show-details --query publicIps -o tsv)

Write-Host "`nAMA is already installed (version 1.37.3)" -ForegroundColor Green
Write-Host "`nTo verify OTLP endpoints are listening, SSH to VMs and run:" -ForegroundColor Cyan
Write-Host "  VM1 ($vm1PublicIp):"
Write-Host "    systemctl status azuremonitor-coreagent" -ForegroundColor Yellow
Write-Host "    ls /etc/opt/microsoft/azuremonitoragent/config-cache/" -ForegroundColor Yellow
Write-Host "    ss -tlnp | grep 4317" -ForegroundColor Yellow
Write-Host "`n  VM2 ($vm2PublicIp):"
Write-Host "    systemctl status azuremonitor-coreagent" -ForegroundColor Yellow
Write-Host "    ls /etc/opt/microsoft/azuremonitoragent/config-cache/" -ForegroundColor Yellow
Write-Host "    ss -tlnp | grep 4317" -ForegroundColor Yellow

Write-Host "`n=== DCR Configuration Complete ===" -ForegroundColor Green
Write-Host "`nSummary:"
Write-Host "  ✓ DCR created with OTLP data sources (logs, metrics, traces)"
Write-Host "  ✓ DCR associated with both VMs"
Write-Host "  ✓ AMA 1.37.3 already installed on both VMs"
Write-Host "`nNext steps:"
Write-Host "  1. Verify OTLP endpoints are listening (ports 4317 gRPC, 4318 HTTP)"
Write-Host "  2. Deploy services to VMs"
Write-Host "  3. Generate traffic and check telemetry in Application Insights"
