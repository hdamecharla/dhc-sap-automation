# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

variable "application_tier"                      {
                                       validation {
                                                    condition = (
                                                      length(trimspace(try(var.application_tier.sid, ""))) == 3
                                                    )
                                                    error_message = "The sid must be specified in the sid field."
                                                  }
                                       validation {
                                                    condition = (
                                                      var.application_tier.webdispatcher_count > 0 ? length(trimspace(try(var.application_tier.web_sid, ""))) == 3 : true
                                                    )
                                                    error_message = "The web dispatcher sid must be specified in the web_sid field."
                                                  }

                                       validation {
                                                    condition = (
                                                                  var.application_tier.scs_high_availability ? (
                                                                    var.application_tier.scs_cluster_type != "ASD" ? (
                                                                      true) : (
                                                                      length(try(var.application_tier.scs_zones, [])) <= (var.application_tier.scs_cluster_disk_type == "Premium_ZRS" ? 2 : 1)
                                                                    )) : (
                                                                    true
                                                                  )
                                                                )

                                                              error_message = format("Cluster type 'ASD' with disk type %s does not support deployments across %d zones.",  var.application_tier.scs_cluster_disk_type, length(try(var.application_tier.scs_zones, [])))
                                                  }
                                                 }

variable "application_tier_ppg_names"            {
                                                    description = "Application tier proximity placement group names"
                                                    default     = []
                                                    type        = list(string)
                                                 }

variable "database"                              {
                                       validation {
                                                    condition = (
                                                      length(trimspace(try(var.database.platform, ""))) != 7
                                                    )
                                                    error_message = "The platform (HANA, SQLSERVER, ORACLE, ORACLE-ASM, DB2, SYBASE) must be specified."
                                                  }

                                       validation {
                                                    condition = (
                                                      length(trimspace(try(var.database.db_sizing_key, ""))) != 0
                                                    )
                                                    error_message = "The db_sizing_key must be specified."
                                                  }
                                                 }
variable "infrastructure"                        {
                                       validation {
                                                    condition = (
                                                      length(trimspace(try(var.infrastructure.region, ""))) != 0
                                                    )
                                                    error_message = "The region must be specified in the infrastructure.region field."
                                                  }

                                       validation {
                                                    condition = (
                                                      length(trimspace(try(var.infrastructure.environment, ""))) != 0
                                                    )
                                                    error_message = "The environment must be specified in the infrastructure.environment field."
                                                  }

                                       validation {
                                                    condition = (
                                                      length(trimspace(try(var.infrastructure.virtual_networks.sap.logical_name, ""))) != 0
                                                    )
                                                    error_message = "Please specify the logical VNet identifier in the network_logical_name field. For deployments prior to version '2.3.3.1' please use the identifier 'sap'."
                                                  }

                                       validation {
                                         condition = (
                                           contains(keys(var.infrastructure.virtual_networks.sap), "subnet_admin") ? (
                                             !var.infrastructure.virtual_networks.sap.subnet_admin.exists_in_workload && var.infrastructure.virtual_networks.sap.subnet_admin.defined ? (
                                               length(trimspace(try(var.infrastructure.virtual_networks.sap.subnet_admin.id, ""))) != 0 || length(trimspace(try(var.infrastructure.virtual_networks.sap.subnet_admin.prefix, ""))) != 0) : (
                                               true
                                             )) : (
                                             true
                                           )
                                         )
                                         error_message = "Either the id or prefix of the Admin subnet must be specified in the infrastructure.virtual_networks.sap.subnet_admin block."
                                       }

                                       validation {
                                                    condition = (
                                                      contains(keys(var.infrastructure.virtual_networks.sap), "subnet_app") ? (
                                                        !var.infrastructure.virtual_networks.sap.subnet_app.exists_in_workload && var.infrastructure.virtual_networks.sap.subnet_app.defined ? (
                                                          length(trimspace(try(var.infrastructure.virtual_networks.sap.subnet_app.id, ""))) != 0 || length(trimspace(try(var.infrastructure.virtual_networks.sap.subnet_app.prefix, ""))) != 0) : (
                                                          true
                                                        )) : (
                                                        true
                                                      )
                                                    )
                                                    error_message = "Either the id or prefix of the Application subnet must be specified in the infrastructure.virtual_networks.sap.subnet_app block."
                                                  }

                                       validation {
                                                    condition = (
                                                      contains(keys(var.infrastructure.virtual_networks.sap), "subnet_db") ? (
                                                        !var.infrastructure.virtual_networks.sap.subnet_db.exists_in_workload && var.infrastructure.virtual_networks.sap.subnet_db.defined ? (
                                                          length(trimspace(try(var.infrastructure.virtual_networks.sap.subnet_db.id, ""))) != 0 || length(trimspace(try(var.infrastructure.virtual_networks.sap.subnet_db.prefix, ""))) != 0) : (
                                                          true
                                                        )) : (
                                                        true
                                                      )
                                                    )
                                                    error_message = "Either the id or prefix of the Database subnet must be specified in the infrastructure.virtual_networks.sap.subnet_db block."
                                                  }
                                                 }


variable "options"                               {}
variable "authentication"                        {}
variable "key_vault"                             {
                                       validation {
                                                    condition = (
                                                      contains(keys(var.key_vault), "keyvault_id_for_deployment_credentials") ? (
                                                        length(var.key_vault.keyvault_id_for_deployment_credentials) > 0 ? (
                                                          length(split("/", var.key_vault.keyvault_id_for_deployment_credentials)) == 9) : (
                                                          true
                                                        )) : (
                                                        true
                                                      )
                                                    )
                                                    error_message = "If specified, the keyvault_id_for_deployment_credentials needs to be a correctly formed Azure resource ID."
                                                  }
                                       validation {
                                                    condition = (
                                                      contains(keys(var.key_vault), "keyvault_id_for_system_credentials") ? (
                                                        length(var.key_vault.keyvault_id_for_system_credentials) > 0 ? (
                                                          length(split("/", var.key_vault.keyvault_id_for_system_credentials)) == 9) : (
                                                          true
                                                        )) : (
                                                        true
                                                      )
                                                    )
                                                    error_message = "If specified, the keyvault_id_for_system_credentials needs to be a correctly formed Azure resource ID."
                                                  }
                                                 }

variable "ha_validator"                          {
                                       validation {
                                                    condition = (
                                                      parseint(split("-", var.ha_validator)[0], 10) != 0 ? upper(split("-", var.ha_validator)[1]) != "NONE" : true
                                                    )
                                                    error_message = "An NFS provider must be specified using the NFS_provider variable in a HA scenario."
                                                  }
                                                 }

variable "custom_prefix"                         {
                                                    description = "Custom prefix"
                                                    default     = ""
                                                    type        = string
                                                 }

variable "is_single_node_hana"                   {
                                                   description = "Checks if single node hana architecture scenario is being deployed"
                                                   default     = false
                                                 }

variable "deployer_tfstate"                      { description = "Deployer remote tfstate file" }

variable "naming"                                { description = "Defines the names for the resources" }

variable "custom_disk_sizes_filename"            {
                                                    description = "Custom disk sizing file"
                                                    default     = ""
                                                 }

variable "deployment"                            { description = "The type of deployment" }

variable "terraform_template_version"            { description = "The version of Terraform templates that were identified in the state file" }

variable "license_type"                          {
                                                   description = "Specifies the license type for the OS"
                                                   default     = ""
                                                 }

variable "enable_purge_control_for_keyvaults"    { description = "Allow the deployment to control the purge protection" }

variable "sapmnt_volume_size"                    { description = "The volume size in GB for sapmnt" }

variable "NFS_provider"                          {
                                                    description = "NFS provider *(AFS, ANF, NONE)*)"
                                                    default     = "NONE"
                                                    type        = string
                                                 }

variable "azure_files_sapmnt_id"                 {
                                                    description = "Azure resource id for the Azure Files sapmnt storage account"
                                                    default     = ""
                                                    type        = string
                                                 }


variable "use_random_id_for_storageaccounts"     { description = "If true, will use random id for storage accounts" }

variable "Agent_IP"                              {
                                                    description = "If provided, contains the IP address of the agent"
                                                    type        = string
                                                    default     = ""
                                                 }

variable "use_private_endpoint"                  {
                                                    description = "Boolean value indicating if private endpoint should be used for the deployment"
                                                    default     = false
                                                    type        = bool
                                                 }
variable "enable_firewall_for_keyvaults_and_storage" {
                                                       description = "Boolean value indicating if firewall should be enabled for key vaults and storage"
                                                       type        = bool
                                                     }

#########################################################################################
#                                                                                       #
#  DNS settings                                                                         #
#                                                                                       #
#########################################################################################


variable "dns_settings"                                 {
                                                          description = "DNS Settings"
                                                        }
variable "sapmnt_private_endpoint_id"            {
                                                    description = "Azure Resource Identifier for an private endpoint connection"
                                                    type        = string
                                                    default     = ""
                                                 }

variable "database_dual_nics"                    { description = "value to indicate if dual nics are used for HANA" }

variable "hana_ANF_volumes"                      { description = "Defines HANA ANF  volumes" }

variable "deploy_application_security_groups"    { description = "Defines if application security groups should be deployed" }


variable "landscape_tfstate"                     {
                                                    description = "Landscape remote tfstate file"
                                                    validation {
                                                                 condition = (
                                                                     length(trimspace(try(var.landscape_tfstate.vnet_sap_arm_id, ""))) != 0
                                                                   )
                                                                   error_message = "Network is undefined, please redeploy the workload zone."
                                                                }
                                                 }

#########################################################################################
#                                                                                       #
#  Scale Set                                                                            #
#                                                                                       #
#########################################################################################
variable "use_scalesets_for_deployment"          { description = "Use Flexible Virtual Machine Scale Sets for the deployment" }

variable "scaleset_id"                           {
                                                   description = "If defined the Flexible Virtual Machine Scale Sets for the deployment"
                                                   default     = ""
                                                 }


#########################################################################################
#                                                                                       #
#  Tags                                                                                 #
#                                                                                       #
#########################################################################################

variable "tags"                                  { description = "If provided, tags for all resources" }
