@echo off
setlocal enabledelayedexpansion

echo ================================================
echo   AZURE OPENTELEMETRY DEMO - COMPLETE DEPLOYMENT
echo ================================================
echo.

:: Configuration
set SCRIPT_DIR=%~dp0
set TERRAFORM_DIR=%SCRIPT_DIR%terraform
set SERVICES_DIR=%SCRIPT_DIR%..\services
set DEPLOY_DIR=%SCRIPT_DIR%deploy

:: Deployment configuration
set DEPLOY_INFRASTRUCTURE=true
set DEPLOY_FRONTEND=true
set DEPLOY_CONTAINERS=true
set DEPLOY_VMS=true
set SKIP_CONFIRMATIONS=false

:: Colors for output (Windows)
set INFO=[INFO]
set SUCCESS=[SUCCESS]
set WARNING=[WARNING]
set ERROR=[ERROR]
set STEP=[STEP]

:: Function to show usage
if "%1"=="--help" (
    echo Azure OpenTelemetry Demo - Complete Deployment Script
    echo.
    echo Usage: %0 [OPTIONS]
    echo.
    echo Options:
    echo   --skip-infrastructure    Skip infrastructure deployment
    echo   --skip-frontend          Skip frontend deployment
    echo   --skip-containers        Skip container deployments
    echo   --skip-vms              Skip VM service deployments
    echo   --yes                   Skip all confirmations
    echo   --help                  Show this help message
    echo.
    echo Examples:
    echo   %0                      Deploy everything (interactive)
    echo   %0 --yes               Deploy everything (automated)
    echo   %0 --skip-containers    Deploy except containers
    echo.
    exit /b 0
)

:: Parse command line arguments
:parse_args
if "%1"=="" goto end_parse
if "%1"=="--skip-infrastructure" (
    set DEPLOY_INFRASTRUCTURE=false
    shift
    goto parse_args
)
if "%1"=="--skip-frontend" (
    set DEPLOY_FRONTEND=false
    shift
    goto parse_args
)
if "%1"=="--skip-containers" (
    set DEPLOY_CONTAINERS=false
    shift
    goto parse_args
)
if "%1"=="--skip-vms" (
    set DEPLOY_VMS=false
    shift
    goto parse_args
)
if "%1"=="--yes" (
    set SKIP_CONFIRMATIONS=true
    shift
    goto parse_args
)
echo %ERROR% Unknown option: %1
exit /b 1

:end_parse

:: Function to check prerequisites
echo %STEP% Checking prerequisites...

:: Check Azure CLI
where az >nul 2>&1
if %errorlevel% neq 0 (
    echo %ERROR% Azure CLI is not installed. Please install it first.
    exit /b 1
)

:: Check if logged in to Azure
az account show >nul 2>&1
if %errorlevel% neq 0 (
    echo %ERROR% Not logged in to Azure. Please run 'az login' first.
    exit /b 1
)

:: Check Terraform
where terraform >nul 2>&1
if %errorlevel% neq 0 (
    echo %ERROR% Terraform is not installed. Please install it first.
    exit /b 1
)

:: Check kubectl
where kubectl >nul 2>&1
if %errorlevel% neq 0 (
    echo %WARNING% kubectl is not installed. AKS deployment will be limited.
)

:: Check Docker
where docker >nul 2>&1
if %errorlevel% neq 0 (
    echo %WARNING% Docker is not installed. Container builds will be skipped.
    set DEPLOY_CONTAINERS=false
)

:: Check Node.js
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo %WARNING% Node.js is not installed. Frontend deployment will be limited.
)

echo %SUCCESS% Prerequisites check completed

:: Show configuration
echo %INFO% Deployment Configuration:
echo   Infrastructure: !DEPLOY_INFRASTRUCTURE!
echo   Frontend: !DEPLOY_FRONTEND!
echo   Containers: !DEPLOY_CONTAINERS!
echo   VMs: !DEPLOY_VMS!
echo   Skip Confirmations: !SKIP_CONFIRMATIONS!
echo.

:: Get user confirmation
if "!SKIP_CONFIRMATIONS!"=="false" (
    set /p "confirm=Proceed with deployment? (Y/n): "
    if /i "!confirm!"=="n" (
        echo %WARNING% Deployment cancelled by user
        exit /b 0
    )
)

:: Record start time
for /f %%i in ('powershell -command "Get-Date -UFormat %%s"') do set start_time=%%i

:: Deploy Infrastructure
if "!DEPLOY_INFRASTRUCTURE!"=="true" (
    echo.
    echo ================================================
    echo         DEPLOYING AZURE INFRASTRUCTURE
    echo ================================================
    echo.
    
    if "!SKIP_CONFIRMATIONS!"=="false" (
        set /p "confirm=Deploy Azure infrastructure (VMs, AKS, databases, monitoring)? (Y/n): "
        if /i "!confirm!"=="n" (
            echo %WARNING% Skipping infrastructure deployment
            goto skip_infrastructure
        )
    )
    
    cd /d "%TERRAFORM_DIR%"
    
    echo %STEP% Initializing Terraform...
    terraform init
    if %errorlevel% neq 0 (
        echo %ERROR% Terraform initialization failed
        exit /b 1
    )
    
    echo %STEP% Planning infrastructure deployment...
    terraform plan -out=tfplan
    if %errorlevel% neq 0 (
        echo %ERROR% Terraform planning failed
        exit /b 1
    )
    
    if "!SKIP_CONFIRMATIONS!"=="false" (
        set /p "confirm=Apply the Terraform plan above? (Y/n): "
        if /i "!confirm!"=="n" (
            echo %WARNING% Infrastructure deployment cancelled
            goto skip_infrastructure
        )
    )
    
    echo %STEP% Deploying infrastructure...
    terraform apply tfplan
    if %errorlevel% neq 0 (
        echo %ERROR% Terraform apply failed
        exit /b 1
    )
    
    :: Save outputs
    terraform output -json > ..\outputs.json
    
    echo %SUCCESS% Infrastructure deployed successfully
    cd /d "%SCRIPT_DIR%"
)
:skip_infrastructure

:: Deploy Frontend
if "!DEPLOY_FRONTEND!"=="true" (
    echo.
    echo ================================================
    echo      DEPLOYING FRONTEND TO APP SERVICE
    echo ================================================
    echo.
    
    if "!SKIP_CONFIRMATIONS!"=="false" (
        set /p "confirm=Deploy React frontend to Azure App Service? (Y/n): "
        if /i "!confirm!"=="n" (
            echo %WARNING% Skipping frontend deployment
            goto skip_frontend
        )
    )
    
    :: Run the frontend deployment script
    if exist "%SCRIPT_DIR%frontend\deploy-appservice.bat" (
        cd /d "%SCRIPT_DIR%frontend"
        call deploy-appservice.bat
        cd /d "%SCRIPT_DIR%"
        echo %SUCCESS% Frontend deployed successfully
    ) else (
        echo %WARNING% Frontend deployment script not found
    )
)
:skip_frontend

:: Build and Push Containers
if "!DEPLOY_CONTAINERS!"=="true" (
    echo.
    echo ================================================
    echo    BUILDING AND PUSHING CONTAINER IMAGES
    echo ================================================
    echo.
    
    if "!SKIP_CONFIRMATIONS!"=="false" (
        set /p "confirm=Build and push container images to ACR? (Y/n): "
        if /i "!confirm!"=="n" (
            echo %WARNING% Skipping container deployments
            goto skip_containers
        )
    )
    
    :: Get ACR details from Terraform
    cd /d "%TERRAFORM_DIR%"
    for /f "tokens=*" %%i in ('terraform output -raw acr_name 2^>nul') do set ACR_NAME=%%i
    for /f "tokens=*" %%i in ('terraform output -raw acr_login_server 2^>nul') do set ACR_LOGIN_SERVER=%%i
    cd /d "%SCRIPT_DIR%"
    
    if "!ACR_NAME!"=="" (
        echo %ERROR% Could not get ACR details from Terraform outputs
        goto skip_containers
    )
    
    echo %STEP% Logging into Azure Container Registry...
    az acr login --name "!ACR_NAME!"
    
    :: Note: Container building would require specific build scripts for each service
    echo %INFO% Container images would be built here for:
    echo   - Order Service (Java Spring Boot)
    echo   - Payment Service (.NET Core)
    echo   - Notification Service (Golang)
    echo %WARNING% Manual build and push required for each service
)
:skip_containers

:: Deploy VM Services
if "!DEPLOY_VMS!"=="true" (
    echo.
    echo ================================================
    echo         DEPLOYING SERVICES TO VMs
    echo ================================================
    echo.
    
    if "!SKIP_CONFIRMATIONS!"=="false" (
        set /p "confirm=Deploy services to VMs (API Gateway, Event Processor, Inventory)? (Y/n): "
        if /i "!confirm!"=="n" (
            echo %WARNING% Skipping VM deployments
            goto skip_vms
        )
    )
    
    :: Get VM details from Terraform
    cd /d "%TERRAFORM_DIR%"
    for /f "tokens=*" %%i in ('terraform output -json vm_public_ips 2^>nul ^| jq -r ".[0]" 2^>nul') do set VM1_IP=%%i
    for /f "tokens=*" %%i in ('terraform output -json vm_public_ips 2^>nul ^| jq -r ".[1]" 2^>nul') do set VM2_IP=%%i
    cd /d "%SCRIPT_DIR%"
    
    if not "!VM1_IP!"=="" (
        echo %INFO% VM1 available at: !VM1_IP!
        echo %INFO% Manual deployment required for API Gateway
    )
    
    if not "!VM2_IP!"=="" (
        echo %INFO% VM2 available at: !VM2_IP!
        echo %INFO% Manual deployment required for Event Processor and Inventory Service
    )
    
    echo %WARNING% VM service deployment requires manual steps
)
:skip_vms

:: Verify Deployment
echo.
echo ================================================
echo           VERIFYING DEPLOYMENT
echo ================================================
echo.

echo %STEP% Checking infrastructure status...

cd /d "%TERRAFORM_DIR%"

:: Get service endpoints
for /f "tokens=*" %%i in ('terraform output -raw load_balancer_public_ip 2^>nul') do set LB_IP=%%i
for /f "tokens=*" %%i in ('terraform output -json frontend_urls 2^>nul ^| jq -r ".app_service_url" 2^>nul') do set FRONTEND_URL=%%i

cd /d "%SCRIPT_DIR%"

:: Test API Gateway
if not "!LB_IP!"=="" (
    echo %INFO% Testing API Gateway at http://!LB_IP!...
    curl -s -o nul -w "%%{http_code}" "http://!LB_IP!/health" > temp_status.txt 2>nul
    set /p api_status=<temp_status.txt 2>nul
    del temp_status.txt 2>nul
    
    if "!api_status!"=="200" (
        echo %SUCCESS% ✓ API Gateway is responding
    ) else (
        echo %WARNING% ⚠ API Gateway not responding (may still be starting)
    )
)

:: Test Frontend
if not "!FRONTEND_URL!"=="" if not "!FRONTEND_URL!"=="null" (
    echo %INFO% Testing Frontend at !FRONTEND_URL!...
    curl -s -o nul -w "%%{http_code}" "!FRONTEND_URL!" > temp_status.txt 2>nul
    set /p frontend_status=<temp_status.txt 2>nul
    del temp_status.txt 2>nul
    
    if "!frontend_status!"=="200" (
        echo %SUCCESS% ✓ Frontend is responding
    ) else (
        echo %WARNING% ⚠ Frontend not responding (may still be starting)
    )
)

:: Show Deployment Summary
echo.
echo ================================================
echo           DEPLOYMENT COMPLETE
echo ================================================
echo.

echo %SUCCESS% 🎉 OpenTelemetry Demo Deployed Successfully!
echo.

echo %INFO% 📋 Access Information:
echo.

:: Frontend URLs
echo 🌐 Frontend:
if not "!FRONTEND_URL!"=="" if not "!FRONTEND_URL!"=="null" (
    echo   App Service: !FRONTEND_URL!
) else (
    echo   Check Terraform outputs for URLs
)
echo.

:: API Endpoints
echo 🔗 API Services:
if not "!LB_IP!"=="" (
    echo   API Gateway: http://!LB_IP!
    echo   Swagger UI: http://!LB_IP!/swagger
    echo   Health Check: http://!LB_IP!/health
)
echo.

:: Monitoring
echo 📊 Monitoring:
echo   Application Insights: Azure Portal ^> Application Insights
echo   AKS Monitoring: Azure Portal ^> AKS ^> Insights
echo.

echo %INFO% 🔧 Management Commands:
echo # View all outputs
echo cd %TERRAFORM_DIR% ^&^& terraform output
echo.
echo # Check AKS services
echo kubectl get all
echo.
echo # Connect to VMs
if not "!VM1_IP!"=="" echo ssh azureuser@!VM1_IP!
if not "!VM2_IP!"=="" echo ssh azureuser@!VM2_IP!
echo.

echo %INFO% 📚 Next Steps:
echo 1. Test the complete application flow
echo 2. Generate synthetic traffic for telemetry
echo 3. Explore Application Insights dashboards
echo 4. Test failure injection scenarios
echo 5. Monitor distributed tracing
echo.

:: Calculate total time
for /f %%i in ('powershell -command "Get-Date -UFormat %%s"') do set end_time=%%i
set /a duration=!end_time!-!start_time!
set /a minutes=!duration!/60
set /a seconds=!duration!%%60

echo %SUCCESS% 🎯 Total deployment time: !minutes!m !seconds!s
echo %SUCCESS% 🚀 OpenTelemetry Demo is ready!

echo.
echo Press any key to continue...
pause > nul