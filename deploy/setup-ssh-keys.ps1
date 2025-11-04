#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Sets up SSH keys for passwordless VM access

.DESCRIPTION
    This script generates SSH keys and configures them for Azure VM access.
    Run this ONCE during initial setup or when setting up a new machine.

.EXAMPLE
    .\setup-ssh-keys.ps1
#>

param(
    [string]$KeyPath = "$env:USERPROFILE\.ssh\azure_vm_key"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "`n=== SSH Key Setup for Azure VMs ===" -ForegroundColor Cyan

# Step 1: Create .ssh directory if it doesn't exist
$sshDir = Split-Path -Parent $KeyPath
if (!(Test-Path $sshDir)) {
    Write-Host "Creating SSH directory: $sshDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

# Step 2: Generate SSH key if it doesn't exist
if (Test-Path $KeyPath) {
    Write-Host "✓ SSH key already exists at: $KeyPath" -ForegroundColor Green
    $response = Read-Host "Do you want to regenerate it? This will require reconfiguring all VMs (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Using existing key" -ForegroundColor Gray
    } else {
        Write-Host "Removing old key..." -ForegroundColor Yellow
        Remove-Item $KeyPath, "$KeyPath.pub" -ErrorAction SilentlyContinue
    }
}

if (!(Test-Path $KeyPath)) {
    Write-Host "Generating new SSH key pair..." -ForegroundColor Yellow
    Write-Host "  Key path: $KeyPath" -ForegroundColor Gray
    ssh-keygen -t rsa -b 4096 -f $KeyPath -N "" -C "azure-vm-deployment"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "✗ Failed to generate SSH key" -ForegroundColor Red
        exit 1
    }
    Write-Host "✓ SSH key generated successfully" -ForegroundColor Green
}

# Step 3: Display public key
$publicKey = Get-Content "$KeyPath.pub"
Write-Host "`n=== Public Key ===" -ForegroundColor Cyan
Write-Host $publicKey -ForegroundColor White

# Step 4: Create/Update SSH config
$configPath = Join-Path $sshDir "config"
$configEntry = @"

# Azure VM Deployment Configuration
Host 4.154.189.199 4.155.58.234 10.0.1.*
    User azureuser
    IdentityFile ~/.ssh/azure_vm_key
    StrictHostKeyChecking no
    PubkeyAuthentication yes
"@

if (Test-Path $configPath) {
    $existingConfig = Get-Content $configPath -Raw
    if ($existingConfig -notmatch "azure_vm_key") {
        Write-Host "`nAppending to existing SSH config..." -ForegroundColor Yellow
        $configEntry | Out-File -FilePath $configPath -Encoding ASCII -Append
        Write-Host "✓ SSH config updated" -ForegroundColor Green
    } else {
        Write-Host "`n✓ SSH config already contains azure_vm_key entry" -ForegroundColor Green
    }
} else {
    Write-Host "`nCreating SSH config..." -ForegroundColor Yellow
    $configEntry | Out-File -FilePath $configPath -Encoding ASCII
    Write-Host "✓ SSH config created" -ForegroundColor Green
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. If VMs already exist, run:" -ForegroundColor Yellow
Write-Host "   .\deploy-ssh-key-to-vms.ps1" -ForegroundColor White
Write-Host "`n2. For NEW deployments, the public key will be automatically" -ForegroundColor Yellow
Write-Host "   configured during Terraform provisioning" -ForegroundColor Yellow
Write-Host "`n✓ SSH key setup complete!" -ForegroundColor Green
