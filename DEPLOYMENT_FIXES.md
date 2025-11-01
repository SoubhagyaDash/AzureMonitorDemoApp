# Deployment Fixes Applied - October 31, 2025

## Summary
This document tracks all fixes applied to ensure reliable AKS deployments for the OpenTelemetry demo.

## Issues Fixed

### 1. Load Balancer IP Assignment Timeout ✅
**Problem**: Services configured as `LoadBalancer` type never received external IPs, causing 180-second timeout during deployment.

**Root Cause**: 
- Services were configured with internal load balancer annotations pointing to `subnet-aks`
- AKS cluster identity lacked permissions to create load balancers in the subnet
- Internal load balancer provisioning requires additional Azure networking configuration

**Solution**:
- Changed all services from `LoadBalancer` to `NodePort` type
- Services now accessible via AKS node IPs on the VNet (10.0.2.x)
- No external load balancer required for VNet-internal communication

**Files Modified**:
- `k8s/order-service.yaml`: Changed to NodePort 30080
- `k8s/payment-service.yaml`: Changed to NodePort 30300
- `k8s/event-processor.yaml`: Changed to NodePort 30800
- `deploy/deploy-environment.ps1`: Updated to get node IPs instead of waiting for load balancer IPs

**Benefits**:
- Faster deployment (no 180s timeout)
- Simpler networking (no load balancer provisioning)
- VNet-internal access from API Gateway VMs works correctly

---

### 2. Order Service CrashLoopBackOff ✅
**Problem**: Order Service pods started successfully but were killed by liveness probes, entering CrashLoopBackOff.

**Root Cause**:
- Spring Boot application takes 72-80 seconds to fully start
- Liveness/readiness probes configured with 30-second initial delay
- Probes hit before application ready, causing container restarts

**Solution**:
- Increased `initialDelaySeconds` to 90 seconds for order-service
- Added `failureThreshold: 5` to allow more grace time
- This gives application ~165 seconds total before being killed (90 + 5*15)

**Files Modified**:
- `k8s/order-service.yaml`:
  ```yaml
  livenessProbe:
    initialDelaySeconds: 90
    periodSeconds: 15
    failureThreshold: 5
  readinessProbe:
    initialDelaySeconds: 90
    periodSeconds: 15
    failureThreshold: 5
  ```

---

### 3. Event Processor Port Mismatch ✅
**Problem**: Event Processor pods running but not becoming ready, health checks failing.

**Root Cause**:
- Application runs on port 8000 (defined in `main.py`: `uvicorn.run(app, host="0.0.0.0", port=8000)`)
- Kubernetes manifest configured for port 8001
- Health probes hitting wrong port, causing connection refused

**Solution**:
- Updated all port references from 8001 to 8000

**Files Modified**:
- `k8s/event-processor.yaml`:
  ```yaml
  ports:
    - containerPort: 8000  # Was 8001
  
  service:
    ports:
      - port: 8000  # Was 8001
        targetPort: 8000  # Was 8001
        nodePort: 30800  # Was 30801
  
  livenessProbe:
    httpGet:
      port: 8000  # Was 8001
  
  readinessProbe:
    httpGet:
      port: 8000  # Was 8001
  ```

**Additional Changes**:
- Increased `initialDelaySeconds` to 60 seconds (Python FastAPI starts faster than Java Spring Boot)
- Added `failureThreshold: 5`

---

### 4. ACR Image Reference Management ✅
**Problem**: Manifests had hardcoded ACR references that wouldn't work across different environments.

**Solution**:
- Replaced hardcoded ACR URLs with `__ACR_LOGIN_SERVER__` placeholder in all manifests
- Deployment script dynamically replaces placeholder with actual ACR login server from Terraform outputs

**Files Modified**:
- `k8s/order-service.yaml`: `image: __ACR_LOGIN_SERVER__/order-service:latest`
- `k8s/payment-service.yaml`: `image: __ACR_LOGIN_SERVER__/payment-service:latest`
- `k8s/event-processor.yaml`: `image: __ACR_LOGIN_SERVER__/event-processor:latest`
- `deploy/deploy-environment.ps1`: Added ACR placeholder replacement logic

---

### 5. Payment Service Probe Hardening ✅
**Problem**: Payment service was healthy but had minimal probe configuration.

**Solution**:
- Increased `initialDelaySeconds` from 30 to 45 seconds for consistency
- Added `failureThreshold: 5` for resilience

**Files Modified**:
- `k8s/payment-service.yaml`: Updated probe configuration

---

## Deployment Script Changes

### Updated Logic in `deploy/deploy-environment.ps1`

1. **NodePort Service Discovery** (Lines ~508-540):
   ```powershell
   # Get AKS node IP for NodePort access
   $aksNodeIp = kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
   
   # Get NodePort for each service
   $orderServicePort = kubectl get service order-service -n otel-demo -o jsonpath='{.spec.ports[0].nodePort}'
   $paymentServicePort = kubectl get service payment-service -n otel-demo -o jsonpath='{.spec.ports[0].nodePort}'
   $eventProcessorPort = kubectl get service event-processor -n otel-demo -o jsonpath='{.spec.ports[0].nodePort}'
   
   # Construct service URLs
   $orderServiceUrl = "http://${aksNodeIp}:${orderServicePort}"
   $paymentServiceUrl = "http://${aksNodeIp}:${paymentServicePort}"
   ```

2. **ACR Placeholder Replacement** (Lines ~493-497):
   ```powershell
   # Read manifest and replace ACR placeholder with actual registry
   $manifestContent = Get-Content $sourceManifest -Raw
   $manifestContent = $manifestContent -replace '__ACR_LOGIN_SERVER__', $acrLoginServer
   ```

3. **Removed Load Balancer Waiting Logic**:
   - Deleted 180-second timeout loop waiting for load balancer IPs
   - Replaced with immediate node IP retrieval

---

## Testing Verification

### Current Status
- ✅ **Order Service**: 2/2 pods running and ready
- ✅ **Payment Service**: 2/2 pods running and ready  
- ✅ **Event Processor**: 2/2 pods running and ready
- ✅ **VM Services**: API Gateway and Inventory Service running

### Service Endpoints
- Order Service: `http://10.0.2.62:30080`
- Payment Service: `http://10.0.2.62:30300`
- Event Processor: `http://10.0.2.62:30800`

---

## Future Deployment Checklist

When deploying from scratch:

1. ✅ Terraform provisions infrastructure
2. ✅ Docker images built and pushed to ACR
3. ✅ Containers deployed to VMs (API Gateway, Inventory)
4. ✅ K8s manifests applied with correct ACR references
5. ✅ NodePort services created (no load balancer wait)
6. ✅ Services become ready within probe timeouts
7. ✅ API Gateway configured with AKS service URLs via NodePort

**Expected Deployment Time**: ~10-15 minutes (down from 20+ minutes with timeouts)

---

## Lessons Learned

1. **Probe Timing is Critical**: Always set initialDelaySeconds > application startup time
2. **Port Configuration Must Match**: Verify application port matches manifest configuration
3. **NodePort > LoadBalancer for VNet**: When services only need VNet-internal access, NodePort is simpler
4. **Dynamic ACR References**: Use placeholders for environment-agnostic manifests
5. **Failure Thresholds**: Add failureThreshold to prevent premature pod kills during startup variations

---

*Document created: October 31, 2025*
*Last updated: October 31, 2025*
