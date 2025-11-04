# SSH Key Setup for Passwordless VM Deployment

This guide explains how to set up SSH keys for passwordless access to Azure VMs during deployment.

## Why SSH Keys?

SSH key-based authentication provides:
- ✅ **No password prompts** during deployment
- ✅ **Faster deployments** (no interactive input needed)
- ✅ **More secure** than password-only authentication
- ✅ **Automation-friendly** for CI/CD pipelines

## Setup Instructions

### For New Deployments (Recommended)

1. **Generate SSH keys** (run ONCE per machine):
   ```powershell
   cd deploy
   .\setup-ssh-keys.ps1
   ```

2. **Deploy infrastructure** with Terraform:
   ```powershell
   cd infrastructure/terraform
   terraform init
   terraform apply
   ```
   
   The SSH public key will be automatically configured on all VMs during provisioning.

3. **Verify passwordless access**:
   ```powershell
   ssh azureuser@<VM-IP> "hostname"
   ```
   
   You should NOT be prompted for a password.

### For Existing Deployments

If you already have VMs deployed without SSH keys:

1. **Generate SSH keys** (if not already done):
   ```powershell
   cd deploy
   .\setup-ssh-keys.ps1
   ```

2. **Deploy keys to existing VMs** (requires password ONE time):
   ```powershell
   cd deploy
   .\deploy-ssh-key-to-vms.ps1
   ```
   
   You'll be prompted for the VM password once per VM. After this, all subsequent connections will be passwordless.

## How It Works

### SSH Key Location
- **Private key**: `~/.ssh/azure_vm_key`
- **Public key**: `~/.ssh/azure_vm_key.pub`
- **SSH config**: `~/.ssh/config` (auto-configured)

### Deployment Script Integration

The `deploy-environment.ps1` script automatically:
1. Checks for SSH key at `~/.ssh/azure_vm_key`
2. Uses the key for all SSH connections if found
3. Falls back to password authentication if key doesn't exist

### Terraform Integration

For new VMs, the `vms.tf` configuration:
1. Looks for `~/.ssh/azure_vm_key.pub`
2. Adds it to `admin_ssh_key` block
3. Configures the VM with the public key during provisioning

## Troubleshooting

### "Permission denied (publickey,password)"

The SSH key may not be properly configured on the VM. Run:
```powershell
cd deploy
.\deploy-ssh-key-to-vms.ps1
```

### "SSH key not found"

Generate the SSH key first:
```powershell
cd deploy
.\setup-ssh-keys.ps1
```

### Still Prompting for Password

1. Verify SSH config is set up:
   ```powershell
   Get-Content ~\.ssh\config
   ```
   
   Should contain an entry for `azure_vm_key`.

2. Test direct SSH with explicit key:
   ```powershell
   ssh -i ~\.ssh\azure_vm_key azureuser@<VM-IP> "hostname"
   ```

3. Check VM has the public key:
   ```powershell
   ssh azureuser@<VM-IP> "cat ~/.ssh/authorized_keys"
   ```

## Security Notes

- The private key (`azure_vm_key`) **should never be committed** to source control
- The public key (`azure_vm_key.pub`) is safe to share but not required in source control
- Password authentication remains enabled as a fallback for emergency access
- The key has **no passphrase** for automation purposes (acceptable for dev/test environments)

## Fresh Setup Checklist

For a completely fresh deployment on a new machine:

- [ ] Clone repository
- [ ] Run `.\deploy\setup-ssh-keys.ps1`
- [ ] Verify key generated at `~\.ssh\azure_vm_key`
- [ ] Run `terraform init && terraform apply`
- [ ] Test SSH: `ssh azureuser@<VM-IP> hostname` (should work without password)
- [ ] Run `.\deploy\deploy-environment.ps1` (should complete without password prompts)

✅ **All done!** Deployments will now work passwordlessly.
