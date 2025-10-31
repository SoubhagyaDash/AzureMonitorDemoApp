# Output values for use in deployment and configuration
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "location" {
  description = "Azure region"
  value       = azurerm_resource_group.main.location
}

# AKS Outputs
output "aks_cluster_name" {
  description = "Name of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "ID of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_kube_config" {
  description = "Kubeconfig for the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "aks_cluster_fqdn" {
  description = "FQDN of the AKS cluster"
  value       = azurerm_kubernetes_cluster.main.fqdn
}

# Container Registry Outputs
output "acr_name" {
  description = "Name of the Azure Container Registry"
  value       = azurerm_container_registry.main.name
}

output "acr_login_server" {
  description = "Login server of the Azure Container Registry"
  value       = azurerm_container_registry.main.login_server
}

output "acr_admin_username" {
  description = "Admin username for Azure Container Registry"
  value       = azurerm_container_registry.main.admin_username
  sensitive   = true
}

output "acr_admin_password" {
  description = "Admin password for Azure Container Registry"
  value       = azurerm_container_registry.main.admin_password
  sensitive   = true
}

# VM Outputs
output "vm_public_ips" {
  description = "Public IP addresses of the VMs"
  value       = azurerm_public_ip.vm_public_ip[*].ip_address
}

output "vm_private_ips" {
  description = "Private IP addresses of the VMs"
  value       = azurerm_network_interface.vm_nic[*].private_ip_address
}

output "vm_names" {
  description = "Names of the VMs"
  value       = azurerm_linux_virtual_machine.vm[*].name
}

output "vm_admin_username" {
  description = "Admin username for VMs"
  value       = var.admin_username
}

output "vm_admin_password" {
  description = "Admin password for VMs"
  value       = random_password.vm_admin_password.result
  sensitive   = true
}

# Load Balancer Output
output "load_balancer_public_ip" {
  description = "Public IP of the load balancer"
  value       = azurerm_public_ip.lb_public_ip.ip_address
}

# Database Outputs
output "sql_server_name" {
  description = "Name of the SQL Server"
  value       = azurerm_mssql_server.main.name
}

output "sql_server_fqdn" {
  description = "FQDN of the SQL Server"
  value       = azurerm_mssql_server.main.fully_qualified_domain_name
}

output "sql_admin_username" {
  description = "SQL Server admin username"
  value       = azurerm_mssql_server.main.administrator_login
}

output "sql_admin_password" {
  description = "SQL Server admin password"
  value       = random_password.sql_admin_password.result
  sensitive   = true
}

output "redis_hostname" {
  description = "Redis Cache hostname"
  value       = azurerm_redis_cache.main.hostname
}

output "redis_port" {
  description = "Redis Cache port"
  value       = azurerm_redis_cache.main.port
}

output "redis_primary_key" {
  description = "Redis Cache primary access key"
  value       = azurerm_redis_cache.main.primary_access_key
  sensitive   = true
}

output "cosmos_endpoint" {
  description = "Cosmos DB endpoint"
  value       = azurerm_cosmosdb_account.main.endpoint
}

output "cosmos_primary_key" {
  description = "Cosmos DB primary key"
  value       = azurerm_cosmosdb_account.main.primary_key
  sensitive   = true
}

# EventHub Outputs
output "eventhub_namespace_name" {
  description = "EventHub namespace name"
  value       = azurerm_eventhub_namespace.main.name
}

output "eventhub_connection_string" {
  description = "EventHub connection string"
  value       = azurerm_eventhub_authorization_rule.main.primary_connection_string
  sensitive   = true
}

# Monitoring Outputs
output "application_insights_connection_string" {
  description = "Application Insights connection string"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "application_insights_instrumentation_key" {
  description = "Application Insights instrumentation key"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace ID"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

# Connection strings for applications
output "connection_strings" {
  description = "Connection strings for all services"
  value = {
    sql_database = "Server=${azurerm_mssql_server.main.fully_qualified_domain_name};Database=${azurerm_mssql_database.orders.name};User Id=${azurerm_mssql_server.main.administrator_login};Password=${random_password.sql_admin_password.result};Encrypt=True;TrustServerCertificate=False;"
    redis        = "${azurerm_redis_cache.main.hostname}:${azurerm_redis_cache.main.ssl_port},password=${azurerm_redis_cache.main.primary_access_key},ssl=True,abortConnect=False"
    cosmos_db    = "AccountEndpoint=${azurerm_cosmosdb_account.main.endpoint};AccountKey=${azurerm_cosmosdb_account.main.primary_key};"
    eventhub_orders        = azurerm_eventhub_authorization_rule.main.primary_connection_string
    eventhub_payments      = azurerm_eventhub_authorization_rule.payments.primary_connection_string
    eventhub_notifications = azurerm_eventhub_authorization_rule.notifications.primary_connection_string
  }
  sensitive = true
}

# Service endpoints for configuration
output "service_endpoints" {
  description = "Service endpoints for inter-service communication"
  value = {
    api_gateway_url               = "http://${azurerm_public_ip.lb_public_ip.ip_address}"
    api_gateway_public_url        = "http://${azurerm_public_ip.lb_public_ip.ip_address}"
    api_gateway_private_url       = try(format("http://%s:5000", length(azurerm_network_interface.vm_nic) > 1 ? azurerm_network_interface.vm_nic[1].private_ip_address : azurerm_network_interface.vm_nic[0].private_ip_address), null)
    order_service_private_url     = try(format("http://%s:8080", length(azurerm_network_interface.vm_nic) > 1 ? azurerm_network_interface.vm_nic[1].private_ip_address : azurerm_network_interface.vm_nic[0].private_ip_address), null)
    payment_service_private_url   = try(format("http://%s:3000", length(azurerm_network_interface.vm_nic) > 1 ? azurerm_network_interface.vm_nic[1].private_ip_address : azurerm_network_interface.vm_nic[0].private_ip_address), null)
    inventory_service_private_url = try(format("http://%s:3001", azurerm_network_interface.vm_nic[0].private_ip_address), null)
    event_processor_private_url   = try(format("http://%s:8001", length(azurerm_network_interface.vm_nic) > 1 ? azurerm_network_interface.vm_nic[1].private_ip_address : azurerm_network_interface.vm_nic[0].private_ip_address), null)
    aks_cluster_fqdn              = azurerm_kubernetes_cluster.main.fqdn
    vm1_public_ip                 = azurerm_public_ip.vm_public_ip[0].ip_address
    vm2_public_ip                 = length(azurerm_public_ip.vm_public_ip) > 1 ? azurerm_public_ip.vm_public_ip[1].ip_address : null
  }
}

output "app_service_subnet_id" {
  description = "Subnet ID used for App Service VNet integration"
  value       = azurerm_subnet.app_service_subnet.id
}

output "frontend_web_app_name" {
  description = "Name of the App Service hosting the frontend"
  value       = azurerm_linux_web_app.frontend.name
}

output "frontend_static_site_name" {
  description = "Name of the Static Web App for the frontend"
  value       = azurerm_static_site.frontend.name
}

# Frontend Access URLs
output "frontend_urls" {
  description = "URLs to access the frontend application"
  value = {
    static_web_app_url       = "https://${azurerm_static_site.frontend.default_host_name}"
    app_service_url          = "https://${azurerm_linux_web_app.frontend.default_hostname}"
    cdn_url                  = var.enable_frontdoor ? try("https://${azurerm_cdn_frontdoor_endpoint.frontend[0].host_name}", null) : null
    vm_hosted_url           = "http://${azurerm_public_ip.vm_public_ip[0].ip_address}:3000"
    load_balancer_frontend  = "http://${azurerm_public_ip.lb_public_ip.ip_address}:3000"
  }
}

# Complete application access guide
output "application_access_guide" {
  description = "Complete guide for accessing the deployed application"
  value = {
    primary_frontend        = "https://${azurerm_linux_web_app.frontend.default_hostname}"
    api_gateway            = "http://${azurerm_public_ip.lb_public_ip.ip_address}"
    swagger_ui             = "http://${azurerm_public_ip.lb_public_ip.ip_address}/swagger"
    vm1_services           = "http://${azurerm_public_ip.vm_public_ip[0].ip_address} (API Gateway)"
    vm2_services           = length(azurerm_public_ip.vm_public_ip) > 1 ? "http://${azurerm_public_ip.vm_public_ip[1].ip_address} (Event Processor, Inventory)" : null
    aks_services           = "Access via kubectl port-forward or ingress"
    monitoring_dashboard   = "https://portal.azure.com/#@/resource${azurerm_application_insights.main.id}/overview"
  }
}