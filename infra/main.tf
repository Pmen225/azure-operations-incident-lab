resource "random_string" "s" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_resource_group" "main" {
  name     = "rg-ops-${random_string.s.result}"
  location = var.location
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-ops-${random_string.s.result}"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-ops"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.50.0.0/16"]
}

resource "azurerm_subnet" "main" {
  name                            = "servers"
  resource_group_name             = azurerm_resource_group.main.name
  virtual_network_name            = azurerm_virtual_network.main.name
  address_prefixes                = ["10.50.1.0/24"]
  default_outbound_access_enabled = false
}

# Explicit outbound connectivity for AMA, extension downloads and Run Command.
# NAT does not permit unsolicited inbound connections and is not an egress firewall.
resource "azurerm_public_ip" "nat" {
  name                = "pip-ops-egress"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "main" {
  name                = "nat-ops"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "main" {
  nat_gateway_id       = azurerm_nat_gateway.main.id
  public_ip_address_id = azurerm_public_ip.nat.id
}

resource "azurerm_subnet_nat_gateway_association" "main" {
  subnet_id      = azurerm_subnet.main.id
  nat_gateway_id = azurerm_nat_gateway.main.id
}

resource "azurerm_network_security_group" "main" {
  name                = "nsg-ops"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  security_rule {
    name                       = "DenyInbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "main" {
  subnet_id                 = azurerm_subnet.main.id
  network_security_group_id = azurerm_network_security_group.main.id
}

resource "azurerm_network_interface" "main" {
  name                = "nic-ops"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.main.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "main" {
  name                            = "vm-ops"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.main.name
  size                            = "Standard_B2s"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.main.id]

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = "azureuser"
    public_key = trimspace(var.admin_ssh_public_key)
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  depends_on = [
    azurerm_subnet_network_security_group_association.main,
    azurerm_subnet_nat_gateway_association.main,
    azurerm_nat_gateway_public_ip_association.main,
  ]
}

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.main.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
}

resource "azurerm_monitor_data_collection_rule" "main" {
  name                = "dcr-ops"
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  kind                = "Linux"

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "law"
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["law"]
  }

  data_sources {
    syslog {
      name           = "syslog"
      facility_names = ["auth", "authpriv", "daemon", "syslog"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
      streams        = ["Microsoft-Syslog"]
    }
  }
}

resource "azurerm_monitor_data_collection_rule_association" "main" {
  name                    = "dcra-ops"
  target_resource_id      = azurerm_linux_virtual_machine.main.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.main.id
}

resource "azurerm_monitor_action_group" "main" {
  name                = "ag-ops"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "ops"

  dynamic "email_receiver" {
    for_each = var.alert_email == null ? [] : [var.alert_email]
    content {
      name                    = "lab-operator"
      email_address           = email_receiver.value
      use_common_alert_schema = true
    }
  }
}

resource "azurerm_monitor_metric_alert" "cpu" {
  name                = "high-cpu"
  resource_group_name = azurerm_resource_group.main.name
  scopes              = [azurerm_linux_virtual_machine.main.id]
  description         = "Average CPU above 80% over a five-minute window in the lab"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}
