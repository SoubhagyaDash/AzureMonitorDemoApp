@echo off
setlocal enabledelayedexpansion

echo ================================================
echo    Azure App Service Frontend Deployment
echo ================================================
echo.

:: Configuration
set TERRAFORM_DIR=..\..\terraform
set FRONTEND_DIR=..\..\..\services\frontend
set BUILD_DIR=build
set DEPLOY_ZIP=frontend-deploy.zip

:: Colors for output (Windows)
set INFO=[INFO]
set SUCCESS=[SUCCESS]
set WARNING=[WARNING]
set ERROR=[ERROR]

:: Function to check prerequisites
echo %INFO% Checking prerequisites...

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

:: Check Node.js
where node >nul 2>&1
if %errorlevel% neq 0 (
    echo %ERROR% Node.js is not installed. Please install it first.
    exit /b 1
)

:: Check npm
where npm >nul 2>&1
if %errorlevel% neq 0 (
    echo %ERROR% npm is not installed. Please install it first.
    exit /b 1
)

:: Check if Terraform state exists
if not exist "%TERRAFORM_DIR%\terraform.tfstate" (
    echo %ERROR% Terraform state not found. Please deploy infrastructure first.
    echo %WARNING% Run: cd %TERRAFORM_DIR% ^&^& terraform apply
    exit /b 1
)

:: Check if frontend directory exists
if not exist "%FRONTEND_DIR%" (
    echo %ERROR% Frontend directory not found: %FRONTEND_DIR%
    exit /b 1
)

echo %SUCCESS% Prerequisites check completed

:: Get infrastructure details
echo %INFO% Getting infrastructure details...

cd /d "%TERRAFORM_DIR%"

:: Get resource group name
for /f "tokens=*" %%i in ('terraform output -raw resource_group_name 2^>nul') do set RESOURCE_GROUP=%%i
if "!RESOURCE_GROUP!"=="" (
    echo %ERROR% Could not get resource group name from Terraform output
    exit /b 1
)

:: Get App Service name
for /f "tokens=*" %%i in ('terraform output -json frontend_urls 2^>nul ^| jq -r ".app_service_url" ^| sed "s|https://||" ^| sed "s|\..*||"') do set APP_SERVICE_NAME=%%i
if "!APP_SERVICE_NAME!"=="" (
    echo %ERROR% Could not get App Service name from Terraform output
    echo %WARNING% Make sure the frontend infrastructure is deployed with App Service
    exit /b 1
)

:: Get other infrastructure details
for /f "tokens=*" %%i in ('terraform output -raw load_balancer_public_ip 2^>nul') do set LOAD_BALANCER_IP=%%i
for /f "tokens=*" %%i in ('terraform output -raw aks_cluster_name 2^>nul') do set AKS_FQDN=%%i
for /f "tokens=*" %%i in ('terraform output -json vm_public_ips 2^>nul ^| jq -r ".[1]" 2^>nul') do set VM_IPS=%%i
for /f "tokens=*" %%i in ('terraform output -raw application_insights_instrumentation_key 2^>nul') do set APP_INSIGHTS_KEY=%%i
for /f "tokens=*" %%i in ('terraform output -raw application_insights_connection_string 2^>nul') do set APP_INSIGHTS_CONNECTION=%%i

echo %SUCCESS% Infrastructure details retrieved:
echo   Resource Group: !RESOURCE_GROUP!
echo   App Service: !APP_SERVICE_NAME!
echo   Load Balancer IP: !LOAD_BALANCER_IP!
echo   AKS Cluster: !AKS_FQDN!
echo   VM2 IP: !VM_IPS!

cd /d "%~dp0"

:: Prepare environment
echo %INFO% Preparing environment configuration...

cd /d "%FRONTEND_DIR%"

:: Create .env.production file
(
echo # API Service Endpoints
echo REACT_APP_API_GATEWAY_URL=http://!LOAD_BALANCER_IP!
echo REACT_APP_ORDER_SERVICE_URL=http://!AKS_FQDN!/api/orders
echo REACT_APP_PAYMENT_SERVICE_URL=http://!AKS_FQDN!/api/payments
echo REACT_APP_INVENTORY_SERVICE_URL=http://!VM_IPS!:3000
echo REACT_APP_EVENT_PROCESSOR_URL=http://!VM_IPS!:8001
echo REACT_APP_NOTIFICATION_SERVICE_URL=http://!AKS_FQDN!/api/notifications
echo.
echo # Application Insights Configuration
echo REACT_APP_APPINSIGHTS_INSTRUMENTATIONKEY=!APP_INSIGHTS_KEY!
echo REACT_APP_APPINSIGHTS_CONNECTION_STRING=!APP_INSIGHTS_CONNECTION!
echo.
echo # Build Configuration
echo GENERATE_SOURCEMAP=false
echo SKIP_PREFLIGHT_CHECK=true
) > .env.production

echo %SUCCESS% Environment configuration created

:: Build React application
echo %INFO% Building React application...

echo %INFO% Installing npm dependencies...
call npm install
if %errorlevel% neq 0 (
    echo %ERROR% npm install failed
    exit /b 1
)

echo %INFO% Building for production...
call npm run build
if %errorlevel% neq 0 (
    echo %ERROR% npm build failed
    exit /b 1
)

if not exist "%BUILD_DIR%" (
    echo %ERROR% Build directory not found after build
    exit /b 1
)

echo %SUCCESS% React application built successfully

:: Create deployment package
echo %INFO% Creating deployment package...

:: Remove existing zip if it exists
if exist "%DEPLOY_ZIP%" del "%DEPLOY_ZIP%"

:: Create web.config for App Service
(
echo ^<?xml version="1.0" encoding="utf-8"?^>
echo ^<configuration^>
echo   ^<system.webServer^>
echo     ^<rewrite^>
echo       ^<rules^>
echo         ^<rule name="React Routes" stopProcessing="true"^>
echo           ^<match url=".*" /^>
echo           ^<conditions logicalGrouping="MatchAll"^>
echo             ^<add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" /^>
echo             ^<add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" /^>
echo           ^</conditions^>
echo           ^<action type="Rewrite" url="/index.html" /^>
echo         ^</rule^>
echo       ^</rules^>
echo     ^</rewrite^>
echo     ^<staticContent^>
echo       ^<mimeMap fileExtension=".json" mimeType="application/json" /^>
echo     ^</staticContent^>
echo   ^</system.webServer^>
echo ^</configuration^>
) > build\web.config

:: Create package.json for App Service
(
echo {
echo   "name": "otel-demo-frontend",
echo   "version": "1.0.0",
echo   "description": "OpenTelemetry Demo Frontend",
echo   "main": "index.html",
echo   "scripts": {
echo     "start": "node server.js"
echo   },
echo   "dependencies": {
echo     "express": "^4.18.2",
echo     "path": "^0.12.7"
echo   }
echo }
) > build\package.json

:: Create simple Express server for App Service
(
echo const express = require('express'^);
echo const path = require('path'^);
echo const app = express(^);
echo const port = process.env.PORT ^|^| 3000;
echo.
echo // Serve static files from the build directory
echo app.use(express.static(path.join(__dirname^)^)^);
echo.
echo // Handle React Router - send all requests to index.html
echo app.get('*', (req, res^) =^> {
echo   res.sendFile(path.join(__dirname, 'index.html'^)^);
echo }^);
echo.
echo app.listen(port, (^) =^> {
echo   console.log(`Frontend server running on port ${port}`^);
echo }^);
) > build\server.js

:: Create zip file using PowerShell
powershell -command "Compress-Archive -Path '.\build\*' -DestinationPath '.\%DEPLOY_ZIP%' -Force"

if not exist "%DEPLOY_ZIP%" (
    echo %ERROR% Failed to create deployment package
    exit /b 1
)

echo %SUCCESS% Deployment package created: %DEPLOY_ZIP%

:: Deploy to App Service
echo %INFO% Deploying to Azure App Service...

echo %INFO% Uploading deployment package...
call az webapp deployment source config-zip --resource-group "!RESOURCE_GROUP!" --name "!APP_SERVICE_NAME!" --src "%DEPLOY_ZIP%"

if %errorlevel% neq 0 (
    echo %ERROR% Deployment to App Service failed
    exit /b 1
)

echo %SUCCESS% Deployment completed successfully

:: Verify deployment
echo %INFO% Verifying deployment...

set APP_SERVICE_URL=https://!APP_SERVICE_NAME!.azurewebsites.net

echo %INFO% Waiting for App Service to start...
timeout /t 30 /nobreak > nul

echo %INFO% Testing application response...
curl -s -o nul -w "%%{http_code}" "!APP_SERVICE_URL!" > temp_http_code.txt
set /p HTTP_CODE=<temp_http_code.txt
del temp_http_code.txt

if "!HTTP_CODE!"=="200" (
    echo %SUCCESS% Application is responding successfully
    echo %SUCCESS% Frontend URL: !APP_SERVICE_URL!
) else (
    echo %WARNING% Application may still be starting (HTTP: !HTTP_CODE!^)
    echo %WARNING% Frontend URL: !APP_SERVICE_URL!
    echo %WARNING% Please wait a few minutes and check the URL manually
)

:: Show post-deployment information
echo %INFO% Post-Deployment Information
echo ==================================
echo.
echo %SUCCESS% 🌐 Frontend Access:
echo   Primary URL: !APP_SERVICE_URL!
echo   App Service: !APP_SERVICE_NAME!
echo   Resource Group: !RESOURCE_GROUP!
echo.
echo %INFO% 🔗 Backend Services:
echo   API Gateway: http://!LOAD_BALANCER_IP!
echo   Swagger UI: http://!LOAD_BALANCER_IP!/swagger
echo   AKS Services: http://!AKS_FQDN! (requires ingress^)
echo   VM Services: http://!VM_IPS! (Event Processor, Inventory^)
echo.
echo %INFO% 📊 Monitoring:
echo   Application Insights: Azure Portal ^> Application Insights
echo   Logs: Azure Portal ^> App Service ^> Log stream
echo.
echo %INFO% 🔧 Management Commands:
echo # View App Service logs
echo az webapp log tail --resource-group !RESOURCE_GROUP! --name !APP_SERVICE_NAME!
echo.
echo # Restart App Service
echo az webapp restart --resource-group !RESOURCE_GROUP! --name !APP_SERVICE_NAME!
echo.
echo # Open in browser
echo start !APP_SERVICE_URL!
echo.

:: Cleanup
echo %INFO% Cleaning up temporary files...

if exist "%DEPLOY_ZIP%" (
    del "%DEPLOY_ZIP%"
    echo %SUCCESS% Removed deployment package
)

if exist ".env.production" (
    del ".env.production"
    echo %SUCCESS% Removed temporary environment file
)

echo %SUCCESS% ✅ Deployment completed successfully!
echo %INFO% Frontend is now available at: !APP_SERVICE_URL!

cd /d "%~dp0"

echo.
echo Press any key to continue...
pause > nul