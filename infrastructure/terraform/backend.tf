# Terraform Backend Configuration
# Uncomment and configure for production use
/*
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "terraformstate"
    container_name      = "tfstate"
    key                 = "otel-demo.tfstate"
  }
}
*/

# For development, use local state
# terraform {
#   backend "local" {
#     path = "terraform.tfstate"
#   }
# }