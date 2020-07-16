output "vm" {
  value = {
    for vm in azurerm_windows_virtual_machine.vm :
    vm.name => {
      "private_ip_address" = vm.private_ip_address
    }
  }
}
