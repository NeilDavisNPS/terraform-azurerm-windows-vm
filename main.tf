locals {
  names = coalescelist(var.names, [var.name])

  resource_group_name  = coalesce(var.resource_group_name, lookup(var.defaults, "resource_group_name", "unspecified"))
  location             = coalesce(var.location, var.defaults.location)
  tags                 = merge(lookup(var.defaults, "tags", {}), var.tags)
  boot_diagnostics_uri = coalesce(var.boot_diagnostics_uri, var.defaults.boot_diagnostics_uri)
  admin_username       = coalesce(var.admin_username, var.defaults.admin_username, "ubuntu")
  admin_ssh_public_key = try(coalesce(var.admin_ssh_public_key, var.defaults.admin_ssh_public_key), file("~/.ssh/id_rsa.pub"))
  additional_ssh_keys  = try(coalesce(var.additional_ssh_keys, var.defaults.additional_ssh_keys), [])
  subnet_id            = coalesce(var.subnet_id, var.defaults.subnet_id)
  vm_size              = coalesce(var.vm_size, var.defaults.vm_size, "Standard_B1ls")
  identity_id          = try(coalesce(var.identity_id, var.defaults.identity_id), null)
  storage_account_type = coalesce(var.storage_account_type, var.defaults.storage_account_type, "Standard_LRS")
  win_admin_username       = coalesce(var.win_admin_username, var.defaults.win_admin_username, "Administrator")
  win_admin_password       = coalesce(var.win_admin_password, var.defaults.win_admin_password, "AEx1rSR-71!")

  application_security_groups = {
    for object in var.application_security_groups :
    object.name => object
  }

  load_balancer_backend_address_pools = {
    for object in var.load_balancer_backend_address_pools :
    object.name => object
  }

  application_gateway_backend_address_pools = {
    for object in var.application_gateway_backend_address_pools :
    object.name => object
  }

  vms_to_application_security_groups = {
    for prod in setproduct(local.names, keys(local.application_security_groups)) :
    format("%s-%s", prod[0], prod[1]) => {
      vm_name                         = prod[0]
      application_security_group_name = local.application_security_groups[prod[1]].name
      application_security_group_id   = local.application_security_groups[prod[1]].id
    }
  }

  vms_to_load_balancer_backend_address_pools = {
    for prod in setproduct(local.names, keys(local.load_balancer_backend_address_pools)) :
    format("%s-%s", prod[0], prod[1]) => {
      vm_name                   = prod[0]
      backend_address_pool_name = local.load_balancer_backend_address_pools[prod[1]].name
      backend_address_pool_id   = local.load_balancer_backend_address_pools[prod[1]].id
    }
  }

  vms_to_application_gateway_backend_address_pools = {
    for prod in setproduct(local.names, keys(local.application_gateway_backend_address_pools)) :
    format("%s-%s", prod[0], prod[1]) => {
      vm_name                   = prod[0]
      backend_address_pool_name = local.application_gateway_backend_address_pools[prod[1]].name
      backend_address_pool_id   = local.application_gateway_backend_address_pools[prod[1]].id
    }
  }
}

resource "azurerm_availability_set" "vm" {
  depends_on          = [var.module_depends_on]
  for_each            = toset(length(var.availability_set_name) > 0 ? [var.availability_set_name] : [])
  name                = each.value
  resource_group_name = local.resource_group_name
  location            = local.location
  tags                = local.tags
}

resource "azurerm_network_interface" "vm" {
  for_each = toset(local.names)
  name     = "${each.value}-nic"

  depends_on          = [var.module_depends_on]
  resource_group_name = local.resource_group_name
  location            = local.location
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfiguration1"
    subnet_id                     = local.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_application_security_group_association" "vm" {
  for_each                      = local.vms_to_application_security_groups
  network_interface_id          = azurerm_network_interface.vm[each.value.vm_name].id
  application_security_group_id = each.value.application_security_group_id
}

resource "azurerm_network_interface_backend_address_pool_association" "vm" {
  for_each                = local.vms_to_load_balancer_backend_address_pools
  network_interface_id    = azurerm_network_interface.vm[each.value.vm_name].id
  ip_configuration_name   = "ipconfiguration1"
  backend_address_pool_id = each.value.backend_address_pool_id
}

resource "azurerm_network_interface_application_gateway_backend_address_pool_association" "example" {
  for_each                = local.vms_to_application_gateway_backend_address_pools
  network_interface_id    = azurerm_network_interface.vm[each.value.vm_name].id
  ip_configuration_name   = "ipconfiguration1"
  backend_address_pool_id = each.value.backend_address_pool_id
}

resource "azurerm_windows_virtual_machine" "vm" {
  for_each = toset(local.names)
  name     = each.value

  resource_group_name = local.resource_group_name
  location            = local.location
  tags                = local.tags

  size           = local.vm_size
  admin_username = local.win_admin_username
  admin_password = local.win_admin_password


  network_interface_ids = [azurerm_network_interface.vm[each.key].id]
  availability_set_id   = length(var.availability_set_name) > 0 ? azurerm_availability_set.vm[var.availability_set_name].id : var.availability_set_id

  os_disk {
    name                 = "${each.value}-os"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  /*
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter"
    version   = "latest"
  }
*/

  source_image_id = var.source_image_id
  // custom_data = "Base64 encoded custom data"


  dynamic "identity" {
    for_each = toset(local.identity_id != null ? [1] : [])

    content {
      type         = "UserAssigned"
      identity_ids = [local.identity_id]
    }
  }

  dynamic "identity" {
    for_each = toset(local.identity_id == null ? [1] : [])

    content {
      type = "SystemAssigned"
    }
  }

  boot_diagnostics {
    storage_account_uri = local.boot_diagnostics_uri
  }
}
