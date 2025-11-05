# AKS Application Monitoring Onboarding Guide

## Introduction

OpenTelemetry provides a standardized way to instrument telemetry signals, making it easier to monitor performance and troubleshooting issues across various environments. Azure Monitor is expanding its support for monitoring AKS-deployed applications by using OTLP for instrumentation and data collection.

Enabling application monitoring for AKS is a two-step process, starting with cluster-level onboarding which adds the Azure Monitor components to route telemetry to Application Insights. This is then followed namespace-wide or per-deployment onboarding where you can choose between auto-instrumentation using Azure Monitor OpenTelemetry distro or auto-configuration for apps already instrumented with the open-source OpenTelemetry SDKs.

Follow the steps below to participate in the Private Preview or app monitoring on AKS. 

**Notes:** This preview is only supported in South Central US and West Europe regions currently and is incompatible with both Windows (any architecture) and Linux Arm64 node pools.

## 1. Pre-requisites

- An AKS cluster running a kubernetes deployment in the Azure public cloud
- Azure CLI 2.78.0 or greater. For more information, see [How to install the Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli), [What version of the Azure CLI is installed?](https://docs.microsoft.com/cli/azure/reference-index#az-version), and [How to update the Azure CLI](https://docs.microsoft.com/cli/azure/update-azure-cli).

## 2. Install the aks-preview Azure CLI extension

```bash
az extension add --name aks-preview
az extension update --name aks-preview
```

Verify that the installed Azure CLI version meets the requirement in the Prerequisites section:

```bash
az version
```

## 3. Register the AzureMonitorAppMonitoringPreview feature flag

```bash
# Log into Azure CLI
az login

# Set the subscription
az account set --subscription "subscription-name"

# Register the feature flag for Azure Monitor App Monitoring in preview
az feature register --namespace "Microsoft.ContainerService" --name "AzureMonitorAppMonitoringPreview"

# List the registration state of the Azure Monitor App Monitoring Preview feature 
az feature list -o table --query "[?contains(name, 'Microsoft.ContainerService/AzureMonitorAppMonitoringPreview')].{Name:name,State:properties.state}"

# Once the feature shows as Registered in the prior step, re-register the Microsoft.ContainerService provider to apply the new feature settings
az provider register --namespace "Microsoft.ContainerService"

# Check the registration state of the Microsoft.ContainerService provider
az provider show --namespace "Microsoft.ContainerService" --query "registrationState"
```

## 4. Prepare the cluster

Ensure the cluster is onboarded to Azure Monitor metrics and logs. Update the cluster if it is not already onboarded and note the Azure Monitor Workspace and Log Analytics workspace used. [Enable monitoring for AKS clusters - Azure Monitor | Microsoft Learn](https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable)

### Enable app monitoring with the Azure Portal feature flag link

- Navigate to your AKS cluster
- Navigate to the Monitor blade
- Select Monitor settings
- Check the box to Enable application monitoring
- Review and enable

## 5. Prepare the Application Insights resource

Register the Application Insights with OTLP preview features for the subscription where your App Insights resource will be created and ensure registration is complete.

```bash
# Register the feature flags for OTLP support in preview, registration will be automatic. 
az feature register --name OtlpApplicationInsights --namespace Microsoft.Insights
az feature list -o table --query "[?contains(name, 'Microsoft.Insights/OtlpApplicationInsights')].{Name:name,State:properties.state}"

az feature register --name testingLogsOtelManagedResourcesEnabled --namespace Microsoft.Insights
az feature list -o table --query "[?contains(name, 'Microsoft.Insights/testingLogsOtelManagedResourcesEnabled')].{Name:name,State:properties.state}"

az provider register -n Microsoft.Insights
```

Use the Azure portal feature flag to create a new AppInsights resource with OTLP support enabled and Use Managed workspaces option set to Yes. Take note of your App Insights resource name.

**Note:** The Azure Monitor workspace associated with the App Insights resource must be different than the one used for the Azure Monitor infrastructure metrics used earlier.

## 6. Onboard applications 

### Enable namespace-wide app monitoring with the Azure Portal feature flag link

- Navigate to the AKS cluster of interest
- Expand Kubernetes resources
- Navigate to the Namespaces blade
- Click the Namespace to be onboarded to application monitoring
- Click on Application Monitoring (Preview)
- Choose the Application Insights resource with OTLP enabled that was created in the previous step
- Choose the Instrumentation type
  - Select **Auto-Instrumentation** for apps using the supported languages (Java, NodeJs)
  - OR
  - Select **Auto-Configuration** for apps already instrumented with the open-source OpenTelemetry SDK
- Do not configure the rollout restart to be performed immediately, you will need to complete this step manually
- Click Configure

### Perform rollout restart

Perform rollout restart of deployments in the namespace using the Run blade in the Portal or kubectl directly on the cluster.

```bash
kubectl rollout restart deployment -n <your-namespace>
```

### Verify instrumentation

Revisit the Application Monitoring configuration to confirm deployments are shown as instrumented.

- Navigate to the Namespaces blade
- Click the namespace that was onboarded in the previous step
- Click on Application Monitoring (preview)
- Expand Deployments in this namespace to view the status

Additionally, you can use namespace-wide or per-deployment auto-instrumentation for Java or NodeJs apps following the instructions here: [https://learn.microsoft.com/azure/azure-monitor/app/kubernetes-codeless#onboard-deployments](https://learn.microsoft.com/azure/azure-monitor/app/kubernetes-codeless#onboard-deployments)

After 3-5 minutes, navigate to the App Insights resource in the Azure Portal to confirm data collection.

## 7. Viewing application signals in Container Insights

Navigate to the Azure portal feature flag link to view App Insights telemetry in the context of Container Insights and transition to Application Insights.

## Appendix 

### Auto-instrumentation with Custom Resources

You can use namespace-wide or per-deployment auto-instrumentation for Java or NodeJs apps following the instructions here: [https://learn.microsoft.com/azure/azure-monitor/app/kubernetes-codeless#onboard-deployments](https://learn.microsoft.com/azure/azure-monitor/app/kubernetes-codeless#onboard-deployments)

### Auto-configuration with Custom Resources and annotations

For apps already instrumented with the open-source OpenTelemetry SDKs, you can onboard by setting environment variables to emit telemetry to Application Insights via the Azure Monitor Agent on the cluster. To instruct the system to configure relevant OTEL environment variables without placing any SDKs on the pod, follow the same docs as for auto-instrumentaion ([https://learn.microsoft.com/azure/azure-monitor/app/kubernetes-codeless#onboard-deployments](https://learn.microsoft.com/azure/azure-monitor/app/kubernetes-codeless#onboard-deployments)), except:

- If you're following the namespace-wide onboarding approach, make sure the `spec.settings.autoInstrumentationPlatforms` field in your Instrumentation custom resource is an empty array. The syntax is: `spec.settings.autoInstrumentationPlatforms: []`
- If you're following the per-deployment onboarding approach, use the `instrumentation.opentelemetry.io/inject-configuration` annotation.

For example:

```yaml
instrumentation.opentelemetry.io/inject-configuration: "cr1"
```

The value of `spec.settings.autoInstrumentationPlatforms` field of the custom resource referenced by the inject-configuration annotation will be ignored, and the deployment will be configured to send OTEL data to the destination specified in the `applicationInsightsConnectionString` field. The application is assumed to have been instrumented at design time, so no SDK will be placed on the pod.

## Limitations

1. Maximum supported DCR associations per AKS cluster is 30.
2. Supported scale for logs/traces is 50k EPS with additional 250 Mi memory usage and 0.5 CPU.
3. OTEL SDK instrumentation with compression is not supported.
4. Namespaces with ISTIO mTLS enabled are not supported.
5. HTTPs in instrumentation configuration is not supported.

## Untested scenarios

1. AKS clusters with HTTP proxy
2. AKS clusters with Private link
3. AKS dual stack clusters
