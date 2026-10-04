output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "vm_name" {
  value = azurerm_linux_virtual_machine.main.name
}

output "vm_id" {
  value = azurerm_linux_virtual_machine.main.id
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.main.name
}

output "workspace_id" {
  value = azurerm_log_analytics_workspace.main.workspace_id
}

output "email_notifications_enabled" {
  value = var.alert_email != null
}
