data "cloudinit_config" "user_data" {
  # Cloud-init configuration to set longer timeout for scripts_user module
  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      cloud_init_modules_config = {
        scripts_user = {
          timeout = var.cloud_init_scripts_timeout
        }
      }
      # Add better error handling
      cloud_final_modules = [
        "scripts-user",
        "final-message",
        "power-state-change"
      ]
      # Disable automatic updates during cloud-init to avoid conflicts
      package_update  = false
      package_upgrade = false
      network = {
        version = 2
        ethernets = {
          all = {
            match = {
              name = "en*"
            }
            dhcp4    = true
            optional = true
          }
        }
      }
    })
  }

  # User data script with better error handling
  part {
    content_type = "text/x-shellscript"
    content = templatefile("user-data.sh.tpl", {
      # Master IP and worker nodes for /etc/hosts
      # FIXME Leaky abstraction
      master = module.networking.master_ip,
      workers = { for i in range(var.workers) :
        # NOTE It doesn't matter if we associate the wrong IP
        # to the wrong host, as long as it's consistent
        format("${local.name_prefix}-worker-%02d", i + 1) => module.networking.worker_ips[i]
      },

      netdata_api_key = var.netdata_api_key,
      nfs_volume      = var.nfs_volume
    })
  }
}

resource "openstack_compute_instance_v2" "spark_worker" {
  count = var.workers

  name         = format("${local.name_prefix}-worker-%02d", count.index + 1)
  image_name   = var.image_name
  flavor_name  = var.flavor_name
  key_pair     = openstack_compute_keypair_v2.spark_keypair.id
  config_drive = true
  user_data    = data.cloudinit_config.user_data.rendered

  personality {
    file    = "/etc/systemd/system/systemd-networkd-wait-online.service"
    content = <<-EOT
      [Unit]
      Description=Skip blocking network-online wait

      [Service]
      Type=oneshot
      ExecStart=/bin/true
      RemainAfterExit=yes

      [Install]
      WantedBy=network-online.target
    EOT
  }

  dynamic "network" {
    for_each = module.networking.workers_ports[count.index]
    content {
      port = network.value
    }
  }
}

resource "openstack_compute_interface_attach_v2" "spark_worker_lustre" {
  count       = var.lustre_network == "" ? 0 : var.workers
  instance_id = openstack_compute_instance_v2.spark_worker[count.index].id
  port_id     = module.networking.lustre_ports[count.index + 1]
}
