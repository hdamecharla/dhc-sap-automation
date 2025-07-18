# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

/*-----------------------------------------------------------------------------8
|                                                                              |
|                                 HANA - VMs                                   |
|                                                                              |
+--------------------------------------4--------------------------------------*/

# NICS ============================================================================================================

/*-----------------------------------------------------------------------------8
HANA DB Linux Server private IP range: .10 -
+--------------------------------------4--------------------------------------*/


#########################################################################################
#                                                                                       #
#  Admin Network Interface                                                              #
#                                                                                       #
#########################################################################################

resource "azurerm_network_interface" "nics_dbnodes_admin" {
  provider                             = azurerm.main
  count                                = local.enable_deployment && var.database_dual_nics && length(try(var.admin_subnet.id, "")) > 0 ? (
                                           var.database_server_count) : (
                                           0
                                         )
  depends_on                           = [ azurerm_network_interface.nics_dbnodes_db ]

  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.admin_nic,
                                           local.prefix,
                                           var.naming.separator,
                                           var.naming.virtualmachine_names.HANA_VMNAME[count.index],
                                           local.resource_suffixes.admin_nic
                                         )

  location                             = var.resource_group[0].location
  resource_group_name                  = var.resource_group[0].name
  accelerated_networking_enabled        = true
  tags                                 = var.tags

  ip_configuration {
                     name      = "ipconfig1"
                     subnet_id = try(var.admin_subnet.id, var.landscape_tfstate.admin_subnet_id)
                     private_ip_address = try(var.database_vm_admin_nic_ips[count.index], var.database.use_DHCP ? (
                       null) : (
                       cidrhost(
                         var.admin_subnet.address_prefixes[0],
                         tonumber(count.index) + local.hdb_ip_offsets.hdb_admin_vm
                       )
                       )
                     )
                     private_ip_address_allocation = length(try(var.database_vm_admin_nic_ips[count.index], "")) > 0 ? (
                       "Static") : (
                       "Dynamic"
                     )
                   }
}

#########################################################################################
#                                                                                       #
#  Primary Network Interface                                                            #
#                                                                                       #
#########################################################################################
resource "azurerm_network_interface" "nics_dbnodes_db" {
  provider                             = azurerm.main
  count                                = local.enable_deployment ? var.database_server_count : 0
  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.db_nic,
                                           local.prefix,
                                           var.naming.separator,
                                           var.naming.virtualmachine_names.HANA_VMNAME[count.index],
                                           local.resource_suffixes.db_nic
                                         )

  location                             = var.resource_group[0].location
  resource_group_name                  = var.resource_group[0].name
  accelerated_networking_enabled        = true
  tags                                 = var.tags
  dynamic "ip_configuration" {
                               iterator = pub
                               for_each = local.database_ips
                               content {
                                 name      = pub.value.name
                                 subnet_id = pub.value.subnet_id
                                 private_ip_address = try(pub.value.nic_ips[count.index],
                                   var.database.use_DHCP ? (
                                     null) : (
                                     cidrhost(
                                       var.db_subnet.address_prefixes[0],
                                       tonumber(count.index) + local.hdb_ip_offsets.hdb_db_vm + pub.value.offset
                                     )
                                   )
                                 )
                                 private_ip_address_allocation = length(try(pub.value.nic_ips[count.index], "")) > 0 ? (
                                   "Static") : (
                                   pub.value.private_ip_address_allocation
                                 )

                                          primary = pub.value.primary
                               }
                             }
}

resource "azurerm_network_interface_application_security_group_association" "db" {
  provider                             = azurerm.main
  count                                = local.enable_deployment ? (
                                           var.deploy_application_security_groups ? var.database_server_count : 0) : (
                                           0
                                         )
  network_interface_id                 = var.use_admin_nic_for_asg && var.database_dual_nics ? azurerm_network_interface.nics_dbnodes_admin[count.index].id : azurerm_network_interface.nics_dbnodes_db[count.index].id
  application_security_group_id        = var.db_asg_id
}

#########################################################################################
#                                                                                       #
#  Storage Network Interface                                                            #
#                                                                                       #
#########################################################################################

resource "azurerm_network_interface" "nics_dbnodes_storage" {
  provider                             = azurerm.main
  count                                = local.enable_deployment && try(var.landscape_tfstate.use_separate_storage_subnet, local.enable_storage_subnet) && var.enable_storage_nic ? (
                                            var.database_server_count
                                         ) : (
                                           0
                                         )
  depends_on                           = [ azurerm_network_interface.nics_dbnodes_db, azurerm_network_interface.nics_dbnodes_admin ]
  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.storage_nic,
                                           local.prefix,
                                           var.naming.separator,
                                           var.naming.virtualmachine_names.HANA_VMNAME[count.index],
                                           local.resource_suffixes.storage_nic
                                         )

  location                             = var.resource_group[0].location
  resource_group_name                  = var.resource_group[0].name
  accelerated_networking_enabled        = true
  tags                                 = var.tags

  ip_configuration {
                     primary   = true
                     name      = "ipconfig1"
                     subnet_id = var.storage_subnet.id

                      private_ip_address = var.database.use_DHCP ? (
                       null) : (
                       length(try(var.database_vm_storage_nic_ips[count.index], "")) > 0 ? (
                         var.database_vm_storage_nic_ips[count.index]) : (
                         cidrhost(
                           var.storage_subnet[0].address_prefixes[0],
                           tonumber(count.index) + local.hdb_ip_offsets.hdb_scaleout_vm
                         )
                       )

                      )
                     private_ip_address_allocation = var.database.use_DHCP ? "Dynamic" : "Static"
                   }
}

# VIRTUAL MACHINES ================================================================================================

# Manages Linux Virtual Machine for HANA DB servers
resource "azurerm_linux_virtual_machine" "vm_dbnode" {
  provider                             = azurerm.main
  count                                = local.enable_deployment ? var.database_server_count : 0
  depends_on                           = [var.anchor_vm]
  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.vm,
                                           local.prefix,
                                           var.naming.separator,
                                           var.naming.virtualmachine_names.HANA_VMNAME[count.index],
                                           local.resource_suffixes.vm
                                         )
  computer_name                        = var.naming.virtualmachine_names.HANA_COMPUTERNAME[count.index]

  resource_group_name                  = var.resource_group[0].name
  location                             = var.resource_group[0].location

  proximity_placement_group_id         = var.database.use_ppg ? (
                                           var.ppg[count.index % max(local.db_zone_count, 1)]) : (
                                           null
                                         )

  source_image_id                      = var.database.os.type == "custom" ? local.hdb_os.source_image_id : null

  virtual_machine_scale_set_id         = length(var.scale_set_id) > 0 ? var.scale_set_id : null

  admin_username                       = var.sid_username
  admin_password                       = local.enable_auth_key ? null : var.sid_password
  disable_password_authentication      = !local.enable_auth_password
  tags                                 = merge(var.tags, local.tags, var.database.scale_out ?  { "SITE" = count.index %2 == 0 ? "SITE1" : "SITE2" } : null)

  patch_mode                                             = var.infrastructure.patch_mode
  patch_assessment_mode                                  = var.infrastructure.patch_assessment_mode
  bypass_platform_safety_checks_on_user_schedule_enabled = var.infrastructure.patch_mode != "AutomaticByPlatform" ? false : true

  zone                                 = local.use_avset ? null : try(local.zones[count.index % max(local.db_zone_count, 1)], null)

  size                                 = local.hdb_vm_sku

  custom_data                          = var.deployment == "new" ? var.cloudinit_growpart_config : null

  license_type                         = length(var.license_type) > 0 ? var.license_type : null
  # ToDo Add back later
# patch_mode                           = var.infrastructure.patch_mode

  encryption_at_host_enabled           = var.infrastructure.encryption_at_host_enabled

  //If more than one servers are deployed into a single zone put them in an availability set and not a zone
  availability_set_id                  = local.use_avset && !local.enable_ultradisk ? (
                                           local.availabilitysets_exist ? (
                                             data.azurerm_availability_set.hdb[count.index % max(length(data.azurerm_availability_set.hdb), 1)].id) : (
                                             azurerm_availability_set.hdb[count.index % max(length(azurerm_availability_set.hdb), 1)].id
                                           )
                                         ) : null

  network_interface_ids                = local.enable_storage_subnet && var.enable_storage_nic ? (
                                           compact([
                                               var.database_dual_nics ? azurerm_network_interface.nics_dbnodes_admin[count.index].id : null,
                                               azurerm_network_interface.nics_dbnodes_db[count.index].id,
                                               azurerm_network_interface.nics_dbnodes_storage[count.index].id
                                             ])

                                           ) : (
                                           var.database_dual_nics ? (
                                             var.options.legacy_nic_order ? (
                                               [
                                                 azurerm_network_interface.nics_dbnodes_admin[count.index].id,
                                                 azurerm_network_interface.nics_dbnodes_db[count.index].id
                                               ]
                                               ) : (
                                               [
                                                 azurerm_network_interface.nics_dbnodes_db[count.index].id,
                                                 azurerm_network_interface.nics_dbnodes_admin[count.index].id
                                               ]
                                             )
                                             ) : (
                                             [
                                               azurerm_network_interface.nics_dbnodes_db[count.index].id
                                             ]
                                           )
                                         )
  # Set the disc controller type, default SCSI
  disk_controller_type                 = var.infrastructure.disk_controller_type_database_tier

  dynamic "admin_ssh_key" {
                            for_each = range(var.deployment == "new" ? 1 : (local.enable_auth_password ? 0 : 1))
                            content {
                              username   = var.sid_username
                              public_key = var.sdu_public_key
                            }
                          }

  dynamic "os_disk" {
                      iterator = disk
                      for_each = range(length(local.os_disk))
                      content {
                        name = format("%s%s%s%s%s",
                          var.naming.resource_prefixes.osdisk,
                          local.prefix,
                          var.naming.separator,
                          var.naming.virtualmachine_names.HANA_VMNAME[count.index],
                          local.resource_suffixes.osdisk
                        )
                        caching                = local.os_disk[0].caching
                        storage_account_type   = local.os_disk[0].storage_account_type
                        disk_size_gb           = local.os_disk[0].disk_size_gb
                        disk_encryption_set_id = try(var.options.disk_encryption_set_id, null)

                      }
                    }

  dynamic "source_image_reference" {
                                     for_each = range(var.database.os.type == "marketplace" || var.database.os.type == "marketplace_with_plan" ? 1 : 0)
                                     content {
                                       publisher = var.database.os.publisher
                                       offer     = var.database.os.offer
                                       sku       = var.database.os.sku
                                       version   = var.database.os.version
                                     }
                                   }
  dynamic "plan" {
                   for_each = range(var.database.os.type == "marketplace_with_plan" ? 1 : 0)
                   content {
                             name      = var.database.os.sku
                             publisher = var.database.os.publisher
                             product   = var.database.os.offer
                           }
                 }

  additional_capabilities {
                            ultra_ssd_enabled = local.enable_ultradisk
                          }

  boot_diagnostics {
                     storage_account_uri = var.storage_bootdiag_endpoint
                   }


  dynamic "identity" {
                       for_each = range((var.use_msi_for_clusters && var.database.high_availability) || length(var.database.user_assigned_identity_id) > 0 ? 1 : 0)
                       content {
                         type         = var.use_msi_for_clusters && length(var.database.user_assigned_identity_id) > 0 ? "SystemAssigned, UserAssigned" : var.use_msi_for_clusters ? "SystemAssigned" : "UserAssigned"
                         identity_ids = length(var.database.user_assigned_identity_id) > 0 ? [var.database.user_assigned_identity_id] : null
                       }
                     }
  lifecycle {
    ignore_changes = [
      source_image_id
    ]
  }


}

resource "azurerm_role_assignment" "role_assignment_msi" {
  provider                             = azurerm.main
  count                                = (
                                           var.use_msi_for_clusters &&
                                           length(var.fencing_role_name) > 0 &&
                                           var.database.high_availability
                                           ) ? (
                                           var.database_server_count
                                           ) : (
                                           0
                                         )
  scope                                = azurerm_linux_virtual_machine.vm_dbnode[count.index].id
  role_definition_name                 = var.fencing_role_name
  principal_id                         = azurerm_linux_virtual_machine.vm_dbnode[count.index].identity[0].principal_id
}

resource "azurerm_role_assignment" "role_assignment_msi_ha" {
  provider                             = azurerm.main
  count                                = (
                                          var.use_msi_for_clusters &&
                                          length(var.fencing_role_name) > 0 &&
                                          var.database.high_availability
                                          ) ? (
                                          var.database_server_count
                                          ) : (
                                          0
                                        )
  scope                                = azurerm_linux_virtual_machine.vm_dbnode[count.index].id
  role_definition_name                 = var.fencing_role_name
  principal_id                         = azurerm_linux_virtual_machine.vm_dbnode[(count.index +1) % var.database_server_count].identity[0].principal_id
}

# Creates managed data disk
resource "azurerm_managed_disk" "data_disk" {
  provider                             = azurerm.main
  count                                = local.enable_deployment ? length(local.data_disk_list) : 0
  name                                 = format("%s%s%s%s%s",
                                           var.naming.resource_prefixes.disk,
                                           local.prefix,
                                           var.naming.separator,
                                           var.naming.virtualmachine_names.HANA_VMNAME[local.data_disk_list[count.index].vm_index],
                                           local.data_disk_list[count.index].suffix
                                         )
  location                             = var.resource_group[0].location
  resource_group_name                  = var.resource_group[0].name
  create_option                        = "Empty"
  storage_account_type                 = local.data_disk_list[count.index].storage_account_type
  disk_size_gb                         = local.data_disk_list[count.index].disk_size_gb
  disk_iops_read_write                 = contains(["UltraSSD_LRS", "PremiumV2_LRS"], local.data_disk_list[count.index].storage_account_type) ? (
                                           local.data_disk_list[count.index].disk_iops_read_write) : (
                                           null
                                         )
  disk_mbps_read_write                 = contains(["UltraSSD_LRS", "PremiumV2_LRS"], local.data_disk_list[count.index].storage_account_type) ? (
                                           local.data_disk_list[count.index].disk_mbps_read_write) : (
                                           null
                                         )

  disk_encryption_set_id               = try(var.options.disk_encryption_set_id, null)

  zone                                 = !local.use_avset ? (
                                           try(azurerm_linux_virtual_machine.vm_dbnode[local.data_disk_list[count.index].vm_index].zone, null)) : (
                                           null
                                         )
  tags                                 = var.tags
  lifecycle {
    ignore_changes = [
      create_option,
      hyper_v_generation,
      source_resource_id
    ]
  }

}

# Manages attaching a Disk to a Virtual Machine
resource "azurerm_virtual_machine_data_disk_attachment" "vm_dbnode_data_disk" {
  provider                             = azurerm.main
  count                                = local.enable_deployment ? length(local.data_disk_list) : 0
  managed_disk_id                      = azurerm_managed_disk.data_disk[count.index].id
  virtual_machine_id                   = azurerm_linux_virtual_machine.vm_dbnode[local.data_disk_list[count.index].vm_index].id
  caching                              = local.data_disk_list[count.index].caching
  write_accelerator_enabled            = local.data_disk_list[count.index].write_accelerator_enabled
  lun                                  = local.data_disk_list[count.index].lun
}

# VM Extension
resource "azurerm_virtual_machine_extension" "hdb_linux_extension" {
  provider                             = azurerm.main
  count                                = local.enable_deployment && var.database.deploy_v1_monitoring_extension ? var.database_server_count : 0
  name                                 = "MonitorX64Linux"
  virtual_machine_id                   = azurerm_linux_virtual_machine.vm_dbnode[count.index].id
  publisher                            = "Microsoft.AzureCAT.AzureEnhancedMonitoring"
  type                                 = "MonitorX64Linux"
  type_handler_version                 = "1.0"
  settings                             = jsonencode(
                                           {
                                             "system": "SAP",

                                           }
                                         )
  tags                                 = var.tags
}


#########################################################################################
#                                                                                       #
#  Azure Shared Disk for SBD                                                            #
#                                                                                       #
#######################################+#################################################
resource "azurerm_managed_disk" "cluster" {
  provider                             = azurerm.main
  count                                = (
                                           local.enable_deployment &&
                                           var.database.high_availability &&
                                           (
                                             upper(var.database.os.os_type) == "WINDOWS" ||
                                             (
                                               upper(var.database.os.os_type) == "LINUX" &&
                                               upper(var.database.database_cluster_type) == "ASD"
                                             )
                                           )
                                         ) ? 1 : 0
  name                                 = format("%s%s%s%s",
                                           var.naming.resource_prefixes.database_cluster_disk,
                                           local.prefix,
                                           var.naming.separator,
                                           var.naming.resource_suffixes.database_cluster_disk
                                         )
  location                             = var.resource_group[0].location
  resource_group_name                  = var.resource_group[0].name
  create_option                        = "Empty"
  storage_account_type                 = var.database.database_cluster_disk_type
  disk_size_gb                         = var.database.database_cluster_disk_size
  disk_encryption_set_id               = try(var.options.disk_encryption_set_id, null)
  max_shares                           = var.database_server_count
  tags                                 = var.tags

  zone                                 = var.database.database_cluster_disk_type == "Premium_LRS" && !local.use_avset ? (
                                           azurerm_linux_virtual_machine.vm_dbnode[local.data_disk_list[count.index].vm_index].zone) : (
                                           null
                                         )
  lifecycle {
    ignore_changes = [
      create_option,
      hyper_v_generation,
      source_resource_id,
      tags
    ]
  }

}

resource "azurerm_virtual_machine_data_disk_attachment" "cluster" {
  provider                             = azurerm.main
  count                                = length(local.cluster_vm_ids)
  managed_disk_id                      = azurerm_managed_disk.cluster[0].id
  virtual_machine_id                   = local.cluster_vm_ids[count.index]
  caching                              = "None"
  lun                                  = var.database.database_cluster_disk_lun

  # The disk is shared, so we do not need to create it before destroying
  # Use lifecycle management for sequencing
  lifecycle {
    create_before_destroy = false
  }
}

#########################################################################################
#                                                                                       #
#  Azure Data Disk for Kdump                                                            #
#                                                                                       #
#######################################+#################################################
resource "azurerm_managed_disk" "kdump" {
  provider                             = azurerm.main
  count                                = (
                                           local.enable_deployment &&
                                           var.database.high_availability &&
                                           (
                                               upper(var.database.os.os_type) == "LINUX" &&
                                               ( var.database.fence_kdump_disk_size > 0 )
                                           )
                                         ) ? var.database_server_count : 0

  name                                 = format("%s%s%s%s%s",
                                           try( var.naming.resource_prefixes.fence_kdump_disk, ""),
                                           local.prefix,
                                           var.naming.separator,
                                           var.naming.virtualmachine_names.HANA_VMNAME[count.index],
                                           try( var.naming.resource_suffixes.fence_kdump_disk, "fence_kdump_disk" )
                                         )
  location                             = var.resource_group[0].location
  resource_group_name                  = var.resource_group[0].name
  create_option                        = "Empty"
  storage_account_type                 = "Premium_LRS"
  disk_size_gb                         = try(var.database.fence_kdump_disk_size,128)
  disk_encryption_set_id               = try(var.options.disk_encryption_set_id, null)
  tags                                 = var.tags
  zone                                 = local.zonal_deployment && !local.use_avset ? (
                                          azurerm_linux_virtual_machine.vm_dbnode[count.index].zone) : (
                                          null
                                        )
  lifecycle {
    ignore_changes = [
      create_option,
      hyper_v_generation,
      source_resource_id,
      tags
    ]
  }

}

resource "azurerm_virtual_machine_data_disk_attachment" "kdump" {
  provider                             = azurerm.main
  count                                = (
                                           local.enable_deployment &&
                                           var.database.high_availability &&
                                           (
                                               upper(var.database.os.os_type) == "LINUX" &&
                                               ( var.database.fence_kdump_disk_size > 0 )
                                           )
                                         ) ? var.database_server_count : 0

  managed_disk_id                      = azurerm_managed_disk.kdump[count.index].id
  virtual_machine_id                   = (upper(var.database.os.os_type) == "LINUX"                                # If Linux
                                         ) ? (
                                           azurerm_linux_virtual_machine.vm_dbnode[count.index].id
                                         ) : null
  caching                              = "None"
  lun                                  = var.database.fence_kdump_lun_number
}

resource "azurerm_virtual_machine_extension" "monitoring_extension_db_lnx" {
  provider                             = azurerm.main
  count                                = local.deploy_monitoring_extension ? (
                                           var.database_server_count) : (
                                           0                                           )
  virtual_machine_id                   = azurerm_linux_virtual_machine.vm_dbnode[count.index].id
  name                                 = "Microsoft.Azure.Monitor.AzureMonitorLinuxAgent"
  publisher                            = "Microsoft.Azure.Monitor"
  type                                 = "AzureMonitorLinuxAgent"
  type_handler_version                 = "1.0"
  auto_upgrade_minor_version           = true
  automatic_upgrade_enabled            = true

}


resource "azurerm_virtual_machine_extension" "monitoring_defender_db_lnx" {
  provider                             = azurerm.main
  count                                = var.infrastructure.deploy_defender_extension ? (
                                           var.database_server_count) : (
                                           0
                                         )
  virtual_machine_id                   = azurerm_linux_virtual_machine.vm_dbnode[count.index].id
  name                                 = "Microsoft.Azure.Security.Monitoring.AzureSecurityLinuxAgent"
  publisher                            = "Microsoft.Azure.Security.Monitoring"
  type                                 = "AzureSecurityLinuxAgent"
  type_handler_version                 = "2.0"
  auto_upgrade_minor_version           = true
  automatic_upgrade_enabled            = true

  settings                             = jsonencode(
                                            {
                                              "enableGenevaUpload"  = true,
                                              "enableAutoConfig"  = true,
                                              "reportSuccessOnUnsupportedDistro"  = true,
                                            }
                                          )
}
