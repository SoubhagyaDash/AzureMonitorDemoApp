@echo off
setlocal enabledelayedexpansion

REM Synthetic Traffic Generator Deployment Script for Windows
REM This script builds and runs the synthetic traffic generator

echo === OpenTelemetry Demo - Synthetic Traffic Deployment ===

REM Configuration
set SERVICE_NAME=synthetic-traffic
set BUILD_DIR=%cd%\services\%SERVICE_NAME%
set LOG_DIR=%cd%\logs
set PID_FILE=%LOG_DIR%\%SERVICE_NAME%.pid
set LOG_FILE=%LOG_DIR%\%SERVICE_NAME%.log

REM Create log directory if it doesn't exist
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM Function to check if service is running
:check_service_status
if exist "%PID_FILE%" (
    set /p SERVICE_PID=<"%PID_FILE%"
    tasklist /FI "PID eq !SERVICE_PID!" 2>nul | find /I "dotnet.exe" >nul
    if !errorlevel! equ 0 (
        echo [INFO] Synthetic traffic generator is running (PID: !SERVICE_PID!)
        exit /b 0
    ) else (
        echo [WARNING] PID file exists but process is not running. Cleaning up...
        del "%PID_FILE%" 2>nul
        exit /b 1
    )
) else (
    exit /b 1
)

REM Function to stop the service
:stop_service
if exist "%PID_FILE%" (
    set /p SERVICE_PID=<"%PID_FILE%"
    echo [INFO] Stopping synthetic traffic generator (PID: !SERVICE_PID!)...
    
    taskkill /PID !SERVICE_PID! /F >nul 2>&1
    timeout /t 3 >nul
    
    del "%PID_FILE%" 2>nul
    echo [SUCCESS] Synthetic traffic generator stopped
) else (
    echo [WARNING] Service is not running
)
goto :eof

REM Function to build the service
:build_service
echo [INFO] Building synthetic traffic generator...

cd /d "%BUILD_DIR%"

where dotnet >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] .NET SDK not found. Please install .NET 8.0 SDK
    exit /b 1
)

dotnet restore
if %errorlevel% neq 0 (
    echo [ERROR] Failed to restore packages
    exit /b 1
)

dotnet build -c Release
if %errorlevel% neq 0 (
    echo [ERROR] Build failed
    exit /b 1
)

echo [SUCCESS] Build completed successfully
goto :eof

REM Function to start the service
:start_service
echo [INFO] Starting synthetic traffic generator...

cd /d "%BUILD_DIR%"

REM Set environment variables
set ASPNETCORE_ENVIRONMENT=Production
set DOTNET_ENVIRONMENT=Production

REM Start the service in background
start /B dotnet run -c Release > "%LOG_FILE%" 2>&1

REM Get the PID (this is a simplified approach for Windows)
timeout /t 2 >nul

REM Find the dotnet process (simplified - in production you'd want a more robust method)
for /f "tokens=2" %%i in ('tasklist /FI "IMAGENAME eq dotnet.exe" /FO CSV ^| find "dotnet.exe"') do (
    set "SERVICE_PID=%%i"
    set "SERVICE_PID=!SERVICE_PID:"=!"
    goto :found_pid
)

:found_pid
echo !SERVICE_PID! > "%PID_FILE%"

timeout /t 3 >nul

REM Check if process is still running
tasklist /FI "PID eq !SERVICE_PID!" 2>nul | find /I "dotnet.exe" >nul
if !errorlevel! equ 0 (
    echo [SUCCESS] Synthetic traffic generator started successfully (PID: !SERVICE_PID!)
    echo [INFO] Log file: %LOG_FILE%
    echo [INFO] PID file: %PID_FILE%
) else (
    echo [ERROR] Failed to start synthetic traffic generator
    del "%PID_FILE%" 2>nul
    exit /b 1
)
goto :eof

REM Function to show logs
:show_logs
if exist "%LOG_FILE%" (
    echo [INFO] Showing last 50 lines of log file...
    echo ----------------------------------------
    REM Show last 50 lines (Windows doesn't have tail, so we use powershell)
    powershell -Command "Get-Content '%LOG_FILE%' -Tail 50"
    echo ----------------------------------------
    echo [INFO] To follow logs: powershell -Command "Get-Content '%LOG_FILE%' -Wait -Tail 10"
) else (
    echo [WARNING] Log file not found: %LOG_FILE%
)
goto :eof

REM Function to show service status
:show_status
echo === Synthetic Traffic Generator Status ===

call :check_service_status
if !errorlevel! equ 0 (
    set /p SERVICE_PID=<"%PID_FILE%"
    echo [SUCCESS] Service is running
    echo [INFO] PID: !SERVICE_PID!
    echo [INFO] Log file: %LOG_FILE%
    
    echo.
    echo [INFO] Recent log entries:
    echo ----------------------------------------
    if exist "%LOG_FILE%" (
        powershell -Command "Get-Content '%LOG_FILE%' -Tail 10" 2>nul
    ) else (
        echo No logs available
    )
    echo ----------------------------------------
) else (
    echo [WARNING] Service is not running
)

echo.
echo [INFO] Available commands:
echo   %~nx0 start    - Start the traffic generator
echo   %~nx0 stop     - Stop the traffic generator
echo   %~nx0 restart  - Restart the traffic generator
echo   %~nx0 build    - Build the service
echo   %~nx0 logs     - Show logs
echo   %~nx0 status   - Show service status
goto :eof

REM Main script logic
set COMMAND=%1
if "%COMMAND%"=="" set COMMAND=status

if "%COMMAND%"=="start" (
    call :check_service_status
    if !errorlevel! equ 0 (
        echo [WARNING] Service is already running
        call :show_status
    ) else (
        call :build_service
        if !errorlevel! equ 0 call :start_service
    )
) else if "%COMMAND%"=="stop" (
    call :stop_service
) else if "%COMMAND%"=="restart" (
    call :stop_service
    timeout /t 2 >nul
    call :build_service
    if !errorlevel! equ 0 call :start_service
) else if "%COMMAND%"=="build" (
    call :build_service
) else if "%COMMAND%"=="logs" (
    call :show_logs
) else if "%COMMAND%"=="status" (
    call :show_status
) else (
    echo [ERROR] Invalid command: %COMMAND%
    echo [INFO] Usage: %~nx0 {start^|stop^|restart^|build^|logs^|status}
    exit /b 1
)

endlocal