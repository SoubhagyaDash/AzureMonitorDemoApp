resource "azurerm_storage_account" "traffic_function_storage" {
  name                     = "sa${substr(replace(var.project_name, "-", ""), 0, 10)}tfunc${substr(random_string.suffix.result, 0, 4)}"
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false

  tags = var.tags
}

resource "azurerm_service_plan" "traffic_function_plan" {
  name                = "plan-${var.project_name}-traffic-function-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  os_type             = "Linux"
  sku_name            = "B1"  # Basic tier to avoid Linux Consumption Plan limitation in mixed RG

  tags = var.tags
}

resource "azurerm_linux_function_app" "traffic_generator" {
  name                = "func-${var.project_name}-traffic-${var.environment}-${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  storage_account_name       = azurerm_storage_account.traffic_function_storage.name
  storage_account_access_key = azurerm_storage_account.traffic_function_storage.primary_access_key
  service_plan_id            = azurerm_service_plan.traffic_function_plan.id

  app_settings = {
    "FUNCTIONS_WORKER_RUNTIME"              = "dotnet-isolated"
    "APPINSIGHTS_INSTRUMENTATIONKEY"        = azurerm_application_insights.main.instrumentation_key
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = azurerm_application_insights.main.connection_string
    "API_GATEWAY_URL"                       = "http://${azurerm_public_ip.lb_public_ip.ip_address}"
    "TRAFFIC_MIN_REQUESTS"                  = "5"
    "TRAFFIC_MAX_REQUESTS"                  = "40"
    "TRAFFIC_ERROR_RATE"                    = "0.02"
    "TRAFFIC_ENABLED_SCENARIOS"             = "Product Browsing,Shopping Cart,Order Processing,User Registration,Health Monitoring"
    "WEBSITE_RUN_FROM_PACKAGE"              = "1"
  }

  site_config {
    always_on = true  # Required for Basic SKU and better for continuous traffic generation
    
    application_stack {
      dotnet_version              = "8.0"
      use_dotnet_isolated_runtime = true
    }

    cors {
      allowed_origins = ["*"]
    }
  }

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

# Output for the Function App
output "traffic_function_app_name" {
  description = "Name of the traffic generator Function App"
  value       = azurerm_linux_function_app.traffic_generator.name
}

output "traffic_function_app_url" {
  description = "URL of the traffic generator Function App"
  value       = "https://${azurerm_linux_function_app.traffic_generator.default_hostname}"
}

output "traffic_function_app_id" {
  description = "ID of the traffic generator Function App"
  value       = azurerm_linux_function_app.traffic_generator.id
}