# Traffic Generator Configuration
# This file contains configuration for the always-on synthetic traffic system

# API Gateway Configuration
API_GATEWAY_URL="http://localhost:5000"
# For Azure deployment, use:
# API_GATEWAY_URL="https://your-api-gateway.azurewebsites.net"

# Traffic Patterns to Run
# Available patterns: business, peak, evening, night
TRAFFIC_PATTERNS="business,peak,evening,night"

# Monitoring Configuration
ENABLE_HEALTH_MONITORING="true"
RESTART_ON_FAILURE="true"
MAX_RESTART_ATTEMPTS="3"
HEALTH_CHECK_INTERVAL="60"  # seconds

# Logging Configuration
DEBUG="false"
LOG_LEVEL="Information"

# Traffic Generation Settings
ENABLE_REALISTIC_PATTERNS="true"
ENABLE_ERROR_INJECTION="true"
BASE_ERROR_RATE="0.02"
MAX_ERROR_RATE="0.05"

# Instance Configuration
INSTANCES_PER_PATTERN="2"
STARTUP_DELAY="2"  # seconds between instance starts

# Environment-specific overrides
if [[ "$ENVIRONMENT" == "Development" ]]; then
    API_GATEWAY_URL="http://localhost:5000"
    TRAFFIC_PATTERNS="business,evening"
    INSTANCES_PER_PATTERN="1"
    DEBUG="true"
    BASE_ERROR_RATE="0.01"
elif [[ "$ENVIRONMENT" == "Production" ]]; then
    # Override with your production API Gateway URL
    # API_GATEWAY_URL="https://your-production-gateway.azurewebsites.net"
    TRAFFIC_PATTERNS="business,peak,evening,night"
    INSTANCES_PER_PATTERN="3"
    BASE_ERROR_RATE="0.025"
    MAX_ERROR_RATE="0.08"
fi

# Export variables for use in other scripts
export API_GATEWAY_URL
export TRAFFIC_PATTERNS
export ENABLE_HEALTH_MONITORING
export RESTART_ON_FAILURE
export MAX_RESTART_ATTEMPTS
export HEALTH_CHECK_INTERVAL
export DEBUG
export ENABLE_REALISTIC_PATTERNS
export ENABLE_ERROR_INJECTION
export BASE_ERROR_RATE
export MAX_ERROR_RATE
export INSTANCES_PER_PATTERN
export STARTUP_DELAY