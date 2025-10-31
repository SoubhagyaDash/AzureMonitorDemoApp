variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "dash-otel-demo"
}

variable "location" {
  description = "The Azure region to deploy resources"
  type        = string
  default     = "West US 2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "otel-demo"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "OpenTelemetry Demo"
    Environment = "Development"
    Owner       = "Platform Team"
    Purpose     = "Azure Monitor OTel Showcase"
  }
}

# AKS Configuration
variable "aks_node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 3
}

variable "aks_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS"
  type        = string
  default     = "1.29"  # Changed from 1.28 (LTS-only) to supported version
}

# VM Configuration
variable "vm_count" {
  description = "Number of VMs for API Gateway and other services"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for application VMs"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "azureuser"
}

# EventHub Configuration
variable "eventhub_partition_count" {
  description = "Number of partitions for EventHub"
  type        = number
  default     = 4
}

variable "eventhub_message_retention" {
  description = "Message retention in days"
  type        = number
  default     = 1
}

# Database Configuration
variable "sql_admin_username" {
  description = "SQL Server admin username"
  type        = string
  default     = "sqladmin"
}

variable "sql_sku_name" {
  description = "SQL Database SKU"
  type        = string
  default     = "S1"
}

# Redis Configuration
variable "redis_sku_name" {
  description = "Redis Cache SKU"
  type        = string
  default     = "Basic"  # Changed from Standard for faster demo deployment (2-5 min vs 20+ min)
}

variable "redis_family" {
  description = "Redis Cache family"
  type        = string
  default     = "C"
}

variable "redis_capacity" {
  description = "Redis Cache capacity"
  type        = number
  default     = 1
}

# Cosmos DB Configuration
variable "cosmos_consistency_level" {
  description = "Cosmos DB consistency level"
  type        = string
  default     = "Session"
}

variable "cosmos_throughput" {
  description = "Cosmos DB throughput (RU/s)"
  type        = number
  default     = 400
}

# Monitoring Configuration
variable "log_analytics_retention_days" {
  description = "Log Analytics workspace retention in days"
  type        = number
  default     = 30
}

variable "application_insights_type" {
  description = "Application Insights application type"
  type        = string
  default     = "web"
}

variable "enable_frontdoor" {
  description = "Whether to provision the Azure Front Door profile"
  type        = bool
  default     = false
}