locals {
  vm_private_ips              = azurerm_network_interface.vm_nic[*].private_ip_address
  inventory_vm_private_ip     = try(local.vm_private_ips[0], null)
  backend_vm_private_ip       = length(local.vm_private_ips) > 1 ? try(local.vm_private_ips[1], local.vm_private_ips[0]) : try(local.vm_private_ips[0], null)
  api_gateway_private_url     = local.backend_vm_private_ip != null ? format("http://%s:5000", local.backend_vm_private_ip) : null
  order_service_private_url   = local.backend_vm_private_ip != null ? format("http://%s:8080", local.backend_vm_private_ip) : null
  payment_service_private_url = local.backend_vm_private_ip != null ? format("http://%s:3000", local.backend_vm_private_ip) : null
  inventory_service_private_url = local.inventory_vm_private_ip != null ? format("http://%s:3001", local.inventory_vm_private_ip) : null
  event_processor_private_url = local.backend_vm_private_ip != null ? format("http://%s:8001", local.backend_vm_private_ip) : null
}

# Azure Static Web App for Frontend
resource "azurerm_static_site" "frontend" {
  name                = "swa-${var.project_name}-frontend-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = "East US 2" # Static Web Apps have limited regions
  sku_tier            = "Free"
  sku_size            = "Free"

  tags = var.tags
}

# App Service Plan for alternative frontend hosting
resource "azurerm_service_plan" "frontend" {
  name                = "asp-${var.project_name}-frontend-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "S1"

  tags = var.tags
}

# App Service for frontend (alternative to Static Web App)
resource "azurerm_linux_web_app" "frontend" {
  name                = "app-${var.project_name}-frontend-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  service_plan_id     = azurerm_service_plan.frontend.id
  virtual_network_subnet_id = azurerm_subnet.app_service_subnet.id

  site_config {
    always_on = false
    vnet_route_all_enabled = true

    application_stack {
      node_version = "18-lts"
    }

    app_command_line = "npm start"
  }

  app_settings = {
    "API_GATEWAY_URL"                          = coalesce(local.api_gateway_private_url, "")
    "ORDER_SERVICE_URL"                        = coalesce(local.order_service_private_url, "")
    "PAYMENT_SERVICE_URL"                      = coalesce(local.payment_service_private_url, "")
    "INVENTORY_SERVICE_URL"                    = coalesce(local.inventory_service_private_url, "")
    "REACT_APP_API_GATEWAY_URL"                = coalesce(local.api_gateway_private_url, "")
    "REACT_APP_ORDER_SERVICE_URL"              = coalesce(local.order_service_private_url, "")
    "REACT_APP_PAYMENT_SERVICE_URL"            = coalesce(local.payment_service_private_url, "")
    "REACT_APP_INVENTORY_SERVICE_URL"          = coalesce(local.inventory_service_private_url, "")
    "REACT_APP_EVENT_PROCESSOR_URL"            = coalesce(local.event_processor_private_url, "")
    "REACT_APP_NOTIFICATION_SERVICE_URL"       = ""
    "APPLICATIONINSIGHTS_CONNECTION_STRING"    = azurerm_application_insights.main.connection_string
    "REACT_APP_APPINSIGHTS_INSTRUMENTATIONKEY" = azurerm_application_insights.main.instrumentation_key
  }

  tags = var.tags
}

# CDN Profile for frontend optimization
# Front Door CDN Profile (newer service)
resource "azurerm_cdn_frontdoor_profile" "frontend" {
  count               = var.enable_frontdoor ? 1 : 0
  name                = "fd-${var.project_name}-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"

  tags = var.tags
}

# Front Door Endpoint for frontend
resource "azurerm_cdn_frontdoor_endpoint" "frontend" {
  count                   = var.enable_frontdoor ? 1 : 0
  name                    = "fd-${var.project_name}-frontend-${random_string.suffix.result}"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.frontend[0].id

  tags = var.tags
}