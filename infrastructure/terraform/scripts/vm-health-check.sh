#!/bin/bash
# VM Health Check Script
# Usage: ssh azureuser@<vm-ip> 'bash -s' < vm-health-check.sh

echo "=== VM Health Check ==="
echo "Timestamp: $(date)"
echo ""

# Check if initialization completed
echo "1. Checking initialization status..."
if [ -f /opt/otel-demo/init-success.log ]; then
    echo "   ✓ Initialization completed"
    cat /opt/otel-demo/init-success.log
else
    echo "   ✗ Initialization not completed or failed"
    echo "   Check logs: sudo tail -100 /var/log/cloud-init-custom.log"
fi
echo ""

# Check Docker
echo "2. Checking Docker..."
if systemctl is-active --quiet docker; then
    echo "   ✓ Docker service is running"
    docker --version
    if docker ps >/dev/null 2>&1; then
        echo "   ✓ Docker daemon is responsive"
        echo "   Running containers:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    else
        echo "   ✗ Docker daemon not responding"
    fi
else
    echo "   ✗ Docker service is not running"
    systemctl status docker --no-pager
fi
echo ""

# Check disk space
echo "3. Checking disk space..."
df -h / | tail -1 | awk '{if ($5+0 > 80) print "   ⚠ Disk usage high: " $5; else print "   ✓ Disk usage OK: " $5}'
echo ""

# Check memory
echo "4. Checking memory..."
free -h | grep Mem | awk '{print "   Total: " $2 ", Used: " $3 ", Available: " $7}'
echo ""

# Check network
echo "5. Checking network connectivity..."
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
    echo "   ✓ Internet connectivity OK"
else
    echo "   ✗ No internet connectivity"
fi
echo ""

# Check installed tools
echo "6. Checking installed tools..."
command -v docker >/dev/null 2>&1 && echo "   ✓ Docker: $(docker --version)" || echo "   ✗ Docker not found"
command -v docker-compose >/dev/null 2>&1 && echo "   ✓ Docker Compose: $(docker-compose --version)" || echo "   ✗ Docker Compose not found"
command -v dotnet >/dev/null 2>&1 && echo "   ✓ .NET: $(dotnet --version)" || echo "   ✗ .NET not found"
command -v node >/dev/null 2>&1 && echo "   ✓ Node.js: $(node --version)" || echo "   ✗ Node.js not found"
command -v python3.9 >/dev/null 2>&1 && echo "   ✓ Python: $(python3.9 --version)" || echo "   ✗ Python not found"
command -v az >/dev/null 2>&1 && echo "   ✓ Azure CLI installed" || echo "   ✗ Azure CLI not found"
echo ""

# Check recent errors in initialization log
echo "7. Recent errors in initialization (if any)..."
if [ -f /var/log/vm-init-custom.log ]; then
    grep -i "error\|fail" /var/log/vm-init-custom.log | tail -5 || echo "   ✓ No recent errors"
else
    echo "   ! Log file not found at /var/log/vm-init-custom.log"
    echo "   Checking Custom Script Extension status..."
    if command -v az >/dev/null 2>&1; then
        echo "   Run: az vm extension show --resource-group <rg> --vm-name <vm> --name vm-init-script"
    fi
fi
echo ""

echo "=== Health Check Complete ==="
