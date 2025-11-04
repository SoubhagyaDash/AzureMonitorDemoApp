#!/bin/bash
# VM Initialization Script - Run via Custom Script Extension
set -x  # Enable debug logging

# Redirect all output to log file
LOG_FILE="/var/log/vm-init-custom.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Starting VM initialization at $(date) ==="
echo "VM Index: ${vm_index}"
echo "Admin User: ${admin_username}"

# Retry function for network operations
retry_command() {
    local max_attempts=5
    local attempt=1
    local delay=10
    local command="$@"
    
    until $command; do
        if [ $attempt -ge $max_attempts ]; then
            echo "ERROR: Command failed after $max_attempts attempts: $command"
            return 1
        fi
        echo "Attempt $attempt failed. Retrying in $delay seconds..."
        sleep $delay
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
    return 0
}

# Wait for cloud-init and package manager to be ready
wait_for_apt() {
    echo "Waiting for apt/dpkg locks to be released..."
    local max_wait=300
    local waited=0
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        if [ $waited -ge $max_wait ]; then
            echo "ERROR: Timed out waiting for package manager locks"
            return 1
        fi
        echo "Package manager is locked, waiting... ($waited/$max_wait seconds)"
        sleep 5
        waited=$((waited + 5))
    done
    echo "Package manager is ready"
    return 0
}

# Update system with retries
echo "=== Updating system packages ==="
wait_for_apt
retry_command apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

# Install Docker using official repository
echo "=== Installing Docker ==="
# Install prerequisites
retry_command apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
mkdir -p /etc/apt/keyrings
retry_command curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
wait_for_apt
retry_command apt-get update
retry_command apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to docker group
usermod -aG docker ${admin_username}

# Ensure Docker is enabled and started
systemctl enable docker
systemctl start docker

# Wait a moment for Docker to fully initialize
sleep 5

# Verify Docker is running
echo "=== Verifying Docker installation ==="
systemctl status docker --no-pager || true

for i in {1..30}; do
    if systemctl is-active --quiet docker && docker info >/dev/null 2>&1; then
        echo "Docker is running successfully"
        docker --version
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Docker failed to start after 30 attempts"
        echo "Docker service status:"
        systemctl status docker --no-pager || true
        echo "Docker daemon logs:"
        journalctl -u docker -n 50 --no-pager || true
        exit 1
    fi
    echo "Waiting for Docker to start... (attempt $i/30)"
    sleep 2
done

# Verify Docker Compose plugin
echo "=== Verifying Docker Compose ==="
docker compose version

# Install .NET 8.0 Runtime
echo "=== Installing .NET 8.0 Runtime ==="
wait_for_apt
retry_command wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O /tmp/packages-microsoft-prod.deb
dpkg -i /tmp/packages-microsoft-prod.deb || true
wait_for_apt
retry_command apt-get update
retry_command apt-get install -y aspnetcore-runtime-8.0

# Install Node.js 18
echo "=== Installing Node.js 18 ==="
retry_command curl -fsSL https://deb.nodesource.com/setup_18.x -o /tmp/nodesource_setup.sh
bash /tmp/nodesource_setup.sh
wait_for_apt
retry_command apt-get install -y nodejs

# Verify Node.js installation
node --version
npm --version

# Install Python 3.9 and pip
echo "=== Installing Python 3.9 ==="
wait_for_apt
retry_command apt-get install -y python3.9 python3.9-pip python3.9-venv

# Install Azure CLI
echo "=== Installing Azure CLI ==="
retry_command curl -sL https://aka.ms/InstallAzureCLIDeb -o /tmp/install_azure_cli.sh
bash /tmp/install_azure_cli.sh

# Create application directory
echo "=== Setting up application directories ==="
mkdir -p /opt/otel-demo/logs
chown -R ${admin_username}:${admin_username} /opt/otel-demo

# Create systemd service files directory
mkdir -p /etc/systemd/system

# Set environment variables for Application Insights
echo "=== Configuring environment variables ==="
cat > /etc/environment << EOF
APPLICATIONINSIGHTS_CONNECTION_STRING="${application_insights_connection_string}"
OTEL_SERVICE_NAME="vm-${vm_index}"
OTEL_RESOURCE_ATTRIBUTES="service.name=vm-${vm_index},service.version=1.0.0"
EOF

# Create startup script for demo services
cat > /opt/otel-demo/start-services.sh << 'SCRIPT_EOF'
#!/bin/bash
cd /opt/otel-demo

# Start API Gateway (VM 1)
if [ "${vm_index}" = "1" ]; then
    echo "Starting API Gateway..."
    # API Gateway will be deployed via CI/CD
fi

# Start other services on VM 2
if [ "${vm_index}" = "2" ]; then
    echo "Starting Event Processor and Inventory Service..."
    # Services will be deployed via CI/CD
fi
SCRIPT_EOF

chmod +x /opt/otel-demo/start-services.sh

# Install performance monitoring tools
echo "=== Installing monitoring tools ==="
wait_for_apt
retry_command apt-get install -y htop iotop nethogs

# Configure log rotation
cat > /etc/logrotate.d/otel-demo << 'LOGROTATE_EOF'
/opt/otel-demo/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 ${admin_username} ${admin_username}
}
LOGROTATE_EOF

# Final system check
echo "=== Running final verification ==="
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker-compose --version 2>/dev/null || docker compose version)"
echo ".NET version: $(dotnet --version 2>/dev/null || echo 'Not installed')"
echo "Node version: $(node --version)"
echo "Python version: $(python3.9 --version)"
echo "Azure CLI version: $(az --version | head -n1)"

# Verify Docker daemon is running and responding
if ! docker ps >/dev/null 2>&1; then
    echo "ERROR: Docker is not responding to commands"
    systemctl status docker
    exit 1
fi

# Create success marker
echo "VM initialization completed successfully at $(date)" | tee /opt/otel-demo/init-success.log
echo "=== VM initialization completed successfully at $(date) ==="
exit 0