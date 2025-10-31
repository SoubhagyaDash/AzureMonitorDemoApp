#!/bin/bash
set -e

# Update system
apt-get update
apt-get upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
usermod -aG docker ${admin_username}

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/download/v2.21.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install .NET 8.0 Runtime
wget https://packages.microsoft.com/config/ubuntu/20.04/packages-microsoft-prod.deb -O packages-microsoft-prod.deb
dpkg -i packages-microsoft-prod.deb
apt-get update
apt-get install -y aspnetcore-runtime-8.0

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt-get install -y nodejs

# Install Python 3.9 and pip
apt-get install -y python3.9 python3.9-pip python3.9-venv

# Install Azure CLI
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Install Azure Monitor Agent
wget https://aka.ms/azcmagent -O ~/install_linux_azcmagent.sh
bash ~/install_linux_azcmagent.sh

# Create application directory
mkdir -p /opt/otel-demo
chown ${admin_username}:${admin_username} /opt/otel-demo

# Create systemd service files directory
mkdir -p /etc/systemd/system

# Set environment variables for Application Insights
cat > /etc/environment << EOF
APPLICATIONINSIGHTS_CONNECTION_STRING="${application_insights_connection_string}"
OTEL_SERVICE_NAME="vm-${vm_index}"
OTEL_RESOURCE_ATTRIBUTES="service.name=vm-${vm_index},service.version=1.0.0"
EOF

# Create startup script for demo services
cat > /opt/otel-demo/start-services.sh << 'EOF'
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
EOF

chmod +x /opt/otel-demo/start-services.sh

# Install performance monitoring tools
apt-get install -y htop iotop nethogs

# Configure log rotation
cat > /etc/logrotate.d/otel-demo << EOF
/opt/otel-demo/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 644 ${admin_username} ${admin_username}
}
EOF

# Create logs directory
mkdir -p /opt/otel-demo/logs
chown ${admin_username}:${admin_username} /opt/otel-demo/logs

echo "VM initialization completed successfully" >> /opt/otel-demo/init.log