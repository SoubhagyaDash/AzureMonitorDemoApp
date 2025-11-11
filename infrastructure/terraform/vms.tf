# Public IPs for VMs
resource "azurerm_public_ip" "vm_public_ip" {
  count               = var.vm_count
  name                = "pip-vm-${count.index + 1}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# Network Interfaces for VMs
resource "azurerm_network_interface" "vm_nic" {
  count               = var.vm_count
  name                = "nic-vm-${count.index + 1}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip[count.index].id
  }

  tags = var.tags
}

# Virtual Machines
resource "azurerm_linux_virtual_machine" "vm" {
  count               = var.vm_count
  name                = "vm-${var.project_name}-${count.index + 1}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  size                = var.vm_size
  admin_username      = var.admin_username

  # Skip Linux Azure Security Pack to avoid conflicts with Azure Monitor Agent
  plan {
    name                   = "20_04-lts-gen2"
    publisher              = "Canonical"
    product                = "0001-com-ubuntu-server-focal"
    SkipLinuxAzSecPack     = true
  }

  additional_capabilities {
    ultra_ssd_enabled = false
  }

  # Support both password and SSH key authentication
  # Password is kept for emergency access, but SSH key is preferred
  disable_password_authentication = false
  admin_password                  = random_password.vm_admin_password.result

  # SSH public key for passwordless authentication
  # Will use the key if it exists, otherwise password-only
  dynamic "admin_ssh_key" {
    for_each = fileexists("${pathexpand("~")}/.ssh/azure_vm_key.pub") ? [1] : []
    content {
      username   = var.admin_username
      public_key = file("${pathexpand("~")}/.ssh/azure_vm_key.pub")
    }
  }

  network_interface_ids = [
    azurerm_network_interface.vm_nic[count.index].id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  tags = merge(var.tags, {
    Role = count.index == 0 ? "api-gateway" : "services"
  })
}

# Custom Script Extension for VM initialization
resource "azurerm_virtual_machine_extension" "vm_init" {
  count                      = var.vm_count
  name                       = "vm-init-script"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm[count.index].id
  publisher                  = "Microsoft.Azure.Extensions"
  type                       = "CustomScript"
  type_handler_version       = "2.1"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    script = base64encode(templatefile("${path.module}/scripts/vm-init.sh", {
      application_insights_connection_string = azurerm_application_insights.main.connection_string
      vm_index                              = count.index + 1
      admin_username                        = var.admin_username
    }))
  })

  tags = var.tags
}

# Azure Monitor Linux Agent Extension
resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  count                      = var.vm_count
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm[count.index].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    azureMonitorConfiguration = {
      enable = true
    }
    genevaConfiguration = {
      enable = false
    }
  })

  tags = var.tags

  depends_on = [azurerm_virtual_machine_extension.vm_init]
}

# Load Balancer for VMs
resource "azurerm_public_ip" "lb_public_ip" {
  name                = "pip-lb-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_lb" "main" {
  name                = "lb-${var.project_name}-${var.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = azurerm_public_ip.lb_public_ip.id
  }

  tags = var.tags
}

# Backend Pool
resource "azurerm_lb_backend_address_pool" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "BackEndAddressPool"
}

# Backend Pool Association
resource "azurerm_network_interface_backend_address_pool_association" "main" {
  count                   = var.vm_count
  network_interface_id    = azurerm_network_interface.vm_nic[count.index].id
  ip_configuration_name   = "internal"
  backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

# Health Probe
resource "azurerm_lb_probe" "main" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "health-probe"
  port            = 5000
  protocol        = "Http"
  request_path    = "/health"
}

# Load Balancer Rule
resource "azurerm_lb_rule" "main" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "api-gateway-rule"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 5000
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.main.id
}

# Load Balancer Rule for Frontend
resource "azurerm_lb_rule" "frontend" {
  loadbalancer_id                = azurerm_lb.main.id
  name                           = "frontend-rule"
  protocol                       = "Tcp"
  frontend_port                  = 3000
  backend_port                   = 3000
  frontend_ip_configuration_name = "PublicIPAddress"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.main.id]
  probe_id                       = azurerm_lb_probe.frontend.id
}

# Health Probe for Frontend
resource "azurerm_lb_probe" "frontend" {
  loadbalancer_id = azurerm_lb.main.id
  name            = "frontend-health-probe"
  port            = 3000
  protocol        = "Http"
  request_path    = "/"
}