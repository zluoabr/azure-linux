output "azure-subscription" {
  value = data.azurerm_subscription.current.display_name
}

output "azure-region" {
  value = azurerm_resource_group.rg.location
}

output "resource-group-name" {
  value = azurerm_resource_group.rg.name
}

output "vm-hostname" {
  value = azurerm_linux_virtual_machine.vm.computer_name
}

output "private-ip" {
  value = azurerm_network_interface.nic.private_ip_address
}

output "public-ip" {
  value = local.public_ip_required ? azurerm_public_ip.pip[0].ip_address : "None"
}

output "admin-username" {
  value = azurerm_linux_virtual_machine.vm.admin_username
}

output "admin-password" {
  value = nonsensitive(azurerm_linux_virtual_machine.vm.admin_password)
}

output "admin-ssh-key" {
  value = var.admin_public_key == "" ? nonsensitive(tls_private_key.ssh-key[0].private_key_pem) : "User specified"
}

output "admin-ssh-key-file" {
  value = var.admin_public_key == "" ? local_file.private-key-file[0].filename : null
}
