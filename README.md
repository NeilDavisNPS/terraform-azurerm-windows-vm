# terraform-azurerm-windows-vm

## Description

Pass in a single name to create a VM, or a list of names to create a group of VMs.

The defaults object is defined in lockstep with the same object in the VM module so that they can share the same local.

> This is a WORK IN PROGRESS and will definitely change. Currently only supports custom images.

## Disclaimer
Shamelessly lifted from Richard Cheney's linux vm code.

Rather than replicate the "vm_defaults" structure (replacing the Linux centric), for now, I have opted to 
augment the structure at use time (see the "merge"). 

An outstanding question is how to manage the supply of the windows password.

* is it one password for all instances created in the module?
* is it a random password for all instances?
* is it one user name for all instances?



## Example

The example uses a number of modules from this organisation.

> Note that (currently) you must have a custom image or shared image.

```terraform
locals {
  load_balancer_defaults = {
    resource_group_name = azurerm_resource_group.example.name
    location            = azurerm_resource_group.example.location
    tags                = azurerm_resource_group.example.tags
    subnet_id           = azurerm_subnet.example.id
  }

  vm_defaults = {
    resource_group_name  = azurerm_resource_group.example.name
    location             = azurerm_resource_group.example.location
    tags                 = azurerm_resource_group.example.tags
    admin_username       = "ubuntu"
    admin_ssh_public_key = file(~/.ssh/id_rsa.pub)
    additional_ssh_keys  = []
    vm_size              = "Standard_B1ls"
    storage_account_type = "Standard_LRS"
    identity_id          = null
    subnet_id            = azurerm_subnet.example.id
    boot_diagnostics_uri = null
    win_admin_username   = "See Windows admin user name restrictions"
    win_admin_passowrd   = "Again, see the password policy.. should be stored elsewhere"
  }
}

data "azurerm_image" "windows_image" {
  name                = "windows_server_base"
  resource_group_name = "images"
}

resource "azurerm_resource_group" "example" {
  name     = "vmss-example"
  location = "West Europe"
  tags = {
    owner = "NPS",
    dept  = "SSPP"
  }
}

resource "azurerm_virtual_network" "example" {
  name                = "example-vnet"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  tags                = azurerm_resource_group.example.tags
  address_space       = ["10.0.0.0/24"]
}

resource "azurerm_subnet" "example" {
  name                 = "example-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.0.0/26"]
}

module "example_lb" {
  source   = "https://github.com/terraform-azurerm-modules/terraform-azurerm-load-balancer"
  defaults = locals.load_balancer_defaults
  name     = "example_lb"
}

module "example" {
  source   = "github.com/NeilDavisNPS/terraform-azurerm-windows-vm"
  defaults = local.vm_defaults

  availability_set_id                    = module.example_lb.availability_set_id
  load_balancer_backend_address_pool_ids = { "example" = module.example_lb.load_balancer_backend_address_pool_id }
  names                                  = ["example-01", "example-02"]
  source_image_id                        = data.azurerm_image.windows_image
}

output "example_load_balancer_ip_address" {
  value = module.example-lb.load_balancer_private_ip_address
}
```

```` Usage
module "win_app" {
   source = "../terraform-azurerm-windows-vm"
   defaults = merge (local.app_vm_defaults,
                     {"win_admin_username" = "win4admin", "win_admin_password"="It's a secret"})

   availability_set_name        = ""
   names                        = ["win-01"]
   source_image_id              = data.azurerm_image.windows_server_base.id
   application_security_groups  = []
   load_balancer_backend_address_pools = []
}

````

## Futures

Depends on the issues raised, but the following are definitely on the list:

1. data disks
1. platform images
1. custom extensions
1. cloud-init
