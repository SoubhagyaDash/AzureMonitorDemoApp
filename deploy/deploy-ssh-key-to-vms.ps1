#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Deploys SSH public key to existing VMs

.DESCRIPTION
    This script copies the SSH public key to existing VMs for passwordless access.
    Use this ONLY for existing VMs. New VMs will have the key configured automatically.

.EXAMPLE
    .\deploy-ssh-key-to-vms.ps1
#>

param(
    [string]$KeyPath = "$env:USERPROFILE\.ssh\azure_vm_key.pub"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")
$terraformDir = Join-Path $repoRoot "infrastructure/terraform"

Write-Host "`n=== Deploying SSH Key to VMs ===" -ForegroundColor Cyan

# Check if key exists
if (!(Test-Path $KeyPath)) {
    Write-Host "✗ SSH public key not found at: $KeyPath" -ForegroundColor Red
    Write-Host "  Run .\setup-ssh-keys.ps1 first" -ForegroundColor Yellow
    exit 1
}

$publicKey = Get-Content $KeyPath
Write-Host "✓ Found SSH public key" -ForegroundColor Green

# Get VM IPs from Terraform
Push-Location $terraformDir
try {
    $vmIps = terraform output -json vm_public_ips | ConvertFrom-Json
    
    if (!$vmIps -or $vmIps.Count -eq 0) {
        Write-Host "✗ No VMs found in Terraform state" -ForegroundColor Red
        Write-Host "  Make sure you've run terraform apply" -ForegroundColor Yellow
        exit 1
    }
    
    Write-Host "Found $($vmIps.Count) VMs to configure" -ForegroundColor Gray
    
    foreach ($vmIp in $vmIps) {
        Write-Host "`n→ Configuring VM: $vmIp" -ForegroundColor Yellow
        
        # Test if SSH works without password (key already configured)
        $testResult = ssh -o BatchMode=yes -o ConnectTimeout=5 azureuser@$vmIp "echo test" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ SSH key already configured" -ForegroundColor Green
            continue
        }
        
        # Need to add key using password
        Write-Host "  Adding SSH key (password required this one time)..." -ForegroundColor Yellow
        $result = ssh -F none -o StrictHostKeyChecking=no -o PasswordAuthentication=yes azureuser@$vmIp "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$publicKey' > ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && echo 'Success'"
        
        if ($LASTEXITCODE -eq 0 -and $result -match "Success") {
            Write-Host "  ✓ SSH key deployed successfully" -ForegroundColor Green
            
            # Verify passwordless access works
            $verifyResult = ssh -o BatchMode=yes azureuser@$vmIp "hostname" 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  ✓ Passwordless SSH verified: $verifyResult" -ForegroundColor Green
            } else {
                Write-Host "  ⚠ Key deployed but verification failed" -ForegroundColor Yellow
            }
        } else {
            Write-Host "  ✗ Failed to deploy SSH key" -ForegroundColor Red
        }
    }
    
} finally {
    Pop-Location
}

Write-Host "`n✓ SSH key deployment complete!" -ForegroundColor Green
Write-Host "You can now run deployments without entering passwords" -ForegroundColor Gray
