# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

resource "null_resource" "init_acm_repository" {
  triggers = {
    create_command_hash               = md5(local.init_local_acm_repository_command)
    acm_repository_path               = var.acm_repository_path
    init_local_acm_repository_command = local.init_local_acm_repository_command
    create_script_md5                 = md5(file(local.init_local_acm_repository_script_path))
  }

  provisioner "local-exec" {
    when    = create
    command = self.triggers.init_local_acm_repository_command
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      rm -rf "${self.triggers.acm_repository_path}"
    EOT
  }
}

resource "null_resource" "copy_common_acm_content" {
  triggers = {
    source_contents_hash              = local.acm_config_sync_common_content_source_content_hash
    destination_contents_hash         = local.acm_config_sync_common_content_destination_content_hash
    source_destination_diff           = local.acm_config_sync_common_content_source_content_hash == local.acm_config_sync_common_content_destination_content_hash ? false : true
    copy_acm_common_content_command   = local.copy_acm_common_content_command
    delete_acm_common_content_command = local.delete_acm_common_content_command
    create_script_hash                = md5(file(local.copy_acm_common_content_script_path))
    destroy_script_hash               = md5(file(local.delete_acm_common_content_script_path))
  }

  provisioner "local-exec" {
    when    = create
    command = self.triggers.copy_acm_common_content_command
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.delete_acm_common_content_command
  }

  depends_on = [
    null_resource.init_acm_repository
  ]
}

resource "null_resource" "tenant_configuration" {
  for_each = local.tenants_excluding_main

  triggers = {
    create_command      = <<-EOT
      "${local.generate_and_copy_acm_tenant_content_script_path}" \
        "${local.acm_config_sync_tenants_configuration_destination_directory_path}" \
        "${local.acm_config_sync_tenant_configuration_package_source_directory_path}" \
        "${each.value.tenant_name}" \
        "${module.service_accounts.service_accounts_map[each.value.tenant_apps_sa_name].email}" \
        "${local.tenant_developer_example_account}"
    EOT
    create_script_hash  = md5(file(local.generate_and_copy_acm_tenant_content_script_path))
    destroy_command     = <<-EOT
      "${local.delete_acm_tenant_content_script_path}" \
        "${local.acm_config_sync_tenants_configuration_destination_directory_path}/${each.value.tenant_name}"
    EOT
    destroy_script_hash = md5(file(local.delete_acm_tenant_content_script_path))

    source_contents_hash = local.acm_config_sync_tenant_configuration_package_source_content_hash
  }

  provisioner "local-exec" {
    when    = create
    command = self.triggers.create_command
  }

  provisioner "local-exec" {
    when    = destroy
    command = self.triggers.destroy_command
  }

  depends_on = [
    null_resource.copy_common_acm_content
  ]
}

resource "null_resource" "commit_acm_config_sync_configuration" {
  triggers = {
    command     = <<-EOT
      "${local.acm_config_sync_commit_configuration_script_path}" \
        "${var.acm_repository_path}" \
        "${var.acm_branch}"
    EOT
    script_hash = md5(file(local.acm_config_sync_commit_configuration_script_path))
    # Always run this. We check if there are changes to commit in the script to run
    timestamp = timestamp()
  }

  provisioner "local-exec" {
    command = self.triggers.command
  }

  depends_on = [
    null_resource.copy_common_acm_content,
    null_resource.tenant_configuration
  ]
}