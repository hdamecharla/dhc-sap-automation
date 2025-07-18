# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.


###############################################################################
#                                                                             #
#                             Resource Group                                  #
#                                                                             #
###############################################################################

output "created_resource_group_id"              {
                                                  description = "Created resource group ID"
                                                  value       = var.infrastructure.resource_group.exists ? data.azurerm_resource_group.library[0].id : azurerm_resource_group.library[0].id
                                                }

output "created_resource_group_subscription_id" {
                                                  description = "Created resource group' subscription ID"
                                                  value = var.infrastructure.resource_group.exists ? (
                                                    split("/", data.azurerm_resource_group.library[0].id))[2] : (
                                                    split("/", azurerm_resource_group.library[0].id)[2]
                                                  )
                                                }

output "created_resource_group_name"            {
                                                  description = "Created resource group name"
                                                  value = var.infrastructure.resource_group.exists ? (
                                                    data.azurerm_resource_group.library[0].name) : (
                                                    azurerm_resource_group.library[0].name
                                                  )
                                                }


###############################################################################
#                                                                             #
#                             Storage Accounts                                #
#                                                                             #
###############################################################################

output "tfstate_storage_account"                 {
                                                   description = "TFState storage account name"
                                                   value = var.storage_account_tfstate.exists ? (
                                                     split("/", var.storage_account_tfstate.id)[8]) : (
                                                     length(var.storage_account_tfstate.name) > 0 ? (
                                                       var.storage_account_tfstate.name) : (
                                                       var.naming.storageaccount_names.LIBRARY.terraformstate_storageaccount_name
                                                   ))
                                                 }

output "storagecontainer_tfstate"                {
                                                   description = "TFState container name"
                                                   value       = var.storage_account_tfstate.tfstate_blob_container.name
                                                 }


output "sapbits_storage_account_name"            {
                                                   description = "SAPBits storage account name"
                                                   value = var.storage_account_sapbits.exists ? (
                                                     split("/", var.storage_account_sapbits.id)[8]) : (
                                                     length(var.storage_account_sapbits.name) > 0 ? (
                                                       var.storage_account_sapbits.name) : (
                                                       var.naming.storageaccount_names.LIBRARY.library_storageaccount_name
                                                   ))

                                                 }

output "sapbits_sa_resource_group_name"          {
                                                   description = "SAPBits storage account resource group name"
                                                   value       = local.resource_group_name
                                                 }

output "storagecontainer_sapbits_name"           {
                                                   description = "SAP Bits container name"
                                                   value       = var.storage_account_sapbits.file_share.name
                                                 }

output "random_id"                               {
                                                   value = random_id.post_fix.hex
                                                 }

output "remote_state_storage_account_name"       {
                                                   description = "Storage account name for Terraform remote state"
                                                   value = var.storage_account_tfstate.exists ? (
                                                     split("/", var.storage_account_tfstate.id)[8]) : (
                                                     length(var.storage_account_tfstate.name) > 0 ? (
                                                       var.storage_account_tfstate.name) : (
                                                       var.naming.storageaccount_names.LIBRARY.terraformstate_storageaccount_name
                                                   ))
                                                 }


output "tfstate_resource_id"                     {
                                                   description = "value of the Azure resource id for the tfstate storage account"
                                                   value = var.storage_account_tfstate.exists ? (
                                                     data.azurerm_storage_account.storage_tfstate[0].id) : (
                                                     try(azurerm_storage_account.storage_tfstate[0].id, "")
                                                   )
                                                 }

output "sa_connection_string"                    {
                                                   description = "Connection string to storage account"
                                                   sensitive   = true
                                                   value = var.storage_account_tfstate.exists ? (
                                                     data.azurerm_storage_account.storage_tfstate[0].primary_connection_string) : (
                                                     try(azurerm_storage_account.storage_tfstate[0].primary_connection_string, "")
                                                   )
                                                 }
