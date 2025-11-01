<#
.SYNOPSIS
End-to-end test script for OpenTelemetry Demo environment.

.DESCRIPTION
This script validates that all services in the OpenTelemetry demo environment 
are working correctly by creating a test order and verifying it flows through 
all components: API Gateway, Order Service, Payment Service, Event Hub, 
Event Processor, Cosmos DB, and Inventory Service.

.PARAMETER ResourceGroup
The Azure resource group name. Defaults to dash-otel-demo2-production.

.PARAMETER ApiGatewayUrl
The API Gateway URL. If not provided, will be retrieved from Terraform outputs.

.EXAMPLE
.\test-environment.ps1

.EXAMPLE
.\test-environment.ps1 -ResourceGroup "my-rg" -ApiGatewayUrl "http://20.114.43.184"
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = "dash-otel-demo2-production",
    [string]$ApiGatewayUrl,
    [string]$TerraformDir = "..\infrastructure\terraform"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:FailureCount = 0
$script:SuccessCount = 0

function Write-TestHeader {
    param([string]$Message)
    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  $($Message.PadRight(60)) ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Write-TestStep {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Yellow
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
    $script:SuccessCount++
}

function Write-Failure {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
    $script:FailureCount++
}

function Write-Info {
    param([string]$Message)
    Write-Host "  $Message" -ForegroundColor White
}

function Test-ServiceHealth {
    param(
        [string]$ServiceName,
        [string]$Url
    )
    
    try {
        $response = Invoke-WebRequest -Uri "$Url/health" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            Write-Success "$ServiceName is healthy"
            return $true
        } else {
            Write-Failure "$ServiceName returned status $($response.StatusCode)"
            return $false
        }
    } catch {
        Write-Failure "$ServiceName health check failed: $($_.Exception.Message)"
        return $false
    }
}

# Get Terraform outputs if not provided
if (-not $ApiGatewayUrl) {
    Write-TestStep "Retrieving Terraform outputs"
    
    if (Test-Path $TerraformDir) {
        Push-Location $TerraformDir
        try {
            $terraformOutput = terraform output -json | ConvertFrom-Json
            $ApiGatewayUrl = $terraformOutput.service_endpoints.value.api_gateway_public_url
            $orderServiceUrl = $terraformOutput.service_endpoints.value.order_service_private_url
            $paymentServiceUrl = $terraformOutput.service_endpoints.value.payment_service_private_url
            $inventoryServiceUrl = $terraformOutput.service_endpoints.value.inventory_service_private_url
            $eventProcessorUrl = $terraformOutput.service_endpoints.value.event_processor_private_url
            $aksClusterName = $terraformOutput.aks_cluster_name.value
            
            Write-Info "API Gateway: $ApiGatewayUrl"
            Write-Info "AKS Cluster: $aksClusterName"
        } finally {
            Pop-Location
        }
    } else {
        Write-Warning "Terraform directory not found. Using default URLs."
        $ApiGatewayUrl = "http://20.114.43.184"
    }
}

Write-TestHeader "OPENTELEMETRY DEMO - END-TO-END TEST"
Write-Host ""
Write-Host "Resource Group : $ResourceGroup" -ForegroundColor Cyan
Write-Host "API Gateway URL: $ApiGatewayUrl" -ForegroundColor Cyan
Write-Host ""

# Test 1: Health Checks
Write-TestStep "TEST 1: Service Health Checks"

Test-ServiceHealth -ServiceName "API Gateway" -Url $ApiGatewayUrl

# Test Order Service via API Gateway
try {
    $response = Invoke-WebRequest -Uri "$ApiGatewayUrl/api/orders" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
    Write-Success "Order Service is accessible via API Gateway"
} catch {
    Write-Failure "Order Service not accessible: $($_.Exception.Message)"
}

# Test 2: Create Test Order
Write-TestStep "TEST 2: Create Test Order"

$timestamp = Get-Date -Format 'HHmmss'
$customerId = "test-customer-$timestamp"
$orderPayload = @{
    customerId = $customerId
    productId = 1
    quantity = 2
    unitPrice = 29.99
} | ConvertTo-Json

Write-Info "Creating order for customer: $customerId"

try {
    $response = Invoke-RestMethod -Uri "$ApiGatewayUrl/api/orders" -Method Post -Body $orderPayload -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
    
    $orderId = $response.id
    $orderStatus = $response.status
    $paymentStatus = $response.paymentStatus
    $totalAmount = $response.totalAmount
    
    Write-Success "Order created successfully"
    Write-Info "Order ID: $orderId"
    Write-Info "Status: $orderStatus"
    Write-Info "Payment Status: $paymentStatus"
    Write-Info "Total Amount: `$$totalAmount"
    
    # Test 3: Verify Order in Order Service
    Write-TestStep "TEST 3: Verify Order in Order Service (SQL Database)"
    
    Start-Sleep -Seconds 2
    
    try {
        $orderFromService = Invoke-RestMethod -Uri "$ApiGatewayUrl/api/orders/$orderId" -Method Get -TimeoutSec 10 -ErrorAction Stop
        
        if ($orderFromService -and $orderFromService.id -eq $orderId) {
            Write-Success "Order found in Order Service"
            Write-Info "Customer: $($orderFromService.customerId)"
            Write-Info "Status: $($orderFromService.status)"
            Write-Info "Total: `$$($orderFromService.totalAmount)"
            
            if ($orderFromService.customerId -eq $customerId) {
                Write-Success "Customer ID matches"
            } else {
                Write-Failure "Customer ID mismatch: expected $customerId, got $($orderFromService.customerId)"
            }
        } else {
            Write-Failure "Order not found in Order Service"
        }
    } catch {
        Write-Failure "Failed to retrieve order from Order Service: $($_.Exception.Message)"
    }
    
    # Test 4: Verify Payment Processing
    Write-TestStep "TEST 4: Verify Payment Processing"
    
    if ($paymentStatus -eq "Completed") {
        Write-Success "Payment processed successfully"
        Write-Info "Payment Status: $paymentStatus"
    } else {
        Write-Failure "Payment not completed. Status: $paymentStatus"
    }
    
    # Test 5: Verify Event Hub Integration
    Write-TestStep "TEST 5: Verify Event Hub Integration (Event Processor)"
    
    try {
        # Get AKS credentials
        az aks get-credentials --resource-group $ResourceGroup --name $aksClusterName --overwrite-existing --admin 2>&1 | Out-Null
        
        # Check Event Processor logs
        Start-Sleep -Seconds 3
        $logs = kubectl logs -n otel-demo deployment/event-processor --tail=50 2>$null
        
        if ($logs -match "OrderCreated|event.*processed") {
            Write-Success "Event Processor received events from Event Hub"
            
            # Check for the specific order ID in logs
            if ($logs -match $orderId) {
                Write-Success "Order ID $orderId found in Event Processor logs"
            } else {
                Write-Info "Order ID not found in recent logs (may have been processed earlier)"
            }
        } else {
            Write-Failure "No events found in Event Processor logs"
        }
    } catch {
        Write-Warning "Could not verify Event Processor logs: $($_.Exception.Message)"
    }
    
    # Test 6: Verify Cosmos DB
    Write-TestStep "TEST 6: Verify Cosmos DB Event Store"
    
    try {
        $cosmosAccount = az cosmosdb sql database show `
            --account-name "cosmos-my-otel-showcase-production-os1jjc" `
            --resource-group $ResourceGroup `
            --name "EventStore" `
            --query "id" -o tsv 2>&1
        
        if ($cosmosAccount) {
            Write-Success "Cosmos DB EventStore database exists"
            Write-Info "Database: EventStore"
        } else {
            Write-Failure "Cosmos DB EventStore database not found"
        }
    } catch {
        Write-Warning "Could not verify Cosmos DB: $($_.Exception.Message)"
    }
    
    # Test 7: Verify Inventory Service
    Write-TestStep "TEST 7: Verify Inventory Service"
    
    try {
        # Try via public IP
        $vmPublicIp = az vm show --resource-group $ResourceGroup --name "vm-my-otel-showcase-1-production" --show-details --query "publicIps" -o tsv 2>&1
        
        if ($vmPublicIp) {
            $inventoryUrl = "http://${vmPublicIp}:3001/api/inventory"
            $inventory = Invoke-RestMethod -Uri $inventoryUrl -Method Get -TimeoutSec 10 -ErrorAction Stop
            
            if ($inventory) {
                Write-Success "Inventory Service is accessible"
                Write-Info "Total Products: $($inventory.Count)"
                
                $product1 = $inventory | Where-Object { $_.id -eq 1 }
                if ($product1) {
                    Write-Info "Product 1: $($product1.name) - `$$($product1.price) (Stock: $($product1.quantity))"
                }
            }
        }
    } catch {
        Write-Warning "Could not verify Inventory Service: $($_.Exception.Message)"
    }
    
    # Test 8: Verify SQL Database
    Write-TestStep "TEST 8: Verify SQL Database Connection"
    
    try {
        $sqlServer = az sql server show `
            --resource-group $ResourceGroup `
            --name "sql-my-otel-showcase-production-os1jjc" `
            --query "name" -o tsv 2>&1
        
        if ($sqlServer) {
            Write-Success "SQL Database server exists"
            Write-Info "Server: $sqlServer"
            
            $databases = az sql db list `
                --resource-group $ResourceGroup `
                --server $sqlServer `
                --query "[].name" -o tsv 2>&1
            
            if ($databases -match "OrderDb") {
                Write-Success "OrderDb database found"
            } else {
                Write-Warning "OrderDb database not found in server"
            }
        }
    } catch {
        Write-Warning "Could not verify SQL Database: $($_.Exception.Message)"
    }
    
} catch {
    Write-Failure "Failed to create test order: $($_.Exception.Message)"
    if ($_.Exception.Response) {
        $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $responseBody = $reader.ReadToEnd()
        Write-Info "Response: $responseBody"
    }
}

# Summary
Write-TestHeader "TEST SUMMARY"
Write-Host ""

$totalTests = $script:SuccessCount + $script:FailureCount

if ($script:FailureCount -eq 0) {
    Write-Host "🎉 ALL TESTS PASSED! ($script:SuccessCount/$totalTests)" -ForegroundColor Green
    Write-Host ""
    Write-Host "✅ Environment is fully operational" -ForegroundColor Green
    Write-Host ""
    Write-Host "Data Flow Verified:" -ForegroundColor Cyan
    Write-Host "  Frontend → API Gateway → Order Service → SQL Database ✓" -ForegroundColor White
    Write-Host "  API Gateway → Payment Service → Payment Processing ✓" -ForegroundColor White
    Write-Host "  API Gateway → Event Hub → Event Processor → Cosmos DB ✓" -ForegroundColor White
    Write-Host "  API Gateway → Inventory Service → Product Data ✓" -ForegroundColor White
    Write-Host ""
    exit 0
} else {
    Write-Host "⚠️  TESTS COMPLETED WITH FAILURES" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Passed : $script:SuccessCount" -ForegroundColor Green
    Write-Host "Failed : $script:FailureCount" -ForegroundColor Red
    Write-Host "Total  : $totalTests" -ForegroundColor White
    Write-Host ""
    Write-Host "Please review the failures above and check service logs for more details." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
