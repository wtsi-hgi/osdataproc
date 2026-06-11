data "cloudinit_config" "master_user_data" {
  part {
    content_type = "text/cloud-config"
    content = yamlencode({
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
      package_update  = false
      package_upgrade = false
    })
  }
}

resource "openstack_compute_instance_v2" "spark_master" {
  name         = "${local.name_prefix}-master"
  image_name   = var.image_name
  flavor_name  = var.flavor_name
  key_pair     = openstack_compute_keypair_v2.spark_keypair.id
  config_drive = true
  user_data    = data.cloudinit_config.master_user_data.rendered

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
    for_each = module.networking.master_ports
    content {
      port = network.value
    }
  }
}

resource "openstack_compute_interface_attach_v2" "spark_master_lustre" {
  count       = var.lustre_network == "" ? 0 : 1
  instance_id = openstack_compute_instance_v2.spark_master.id
  port_id     = module.networking.lustre_ports[0]
}

resource "openstack_compute_volume_attach_v2" "spark_volume" {
  count       = var.nfs_volume == "" ? 0 : 1
  instance_id = openstack_compute_instance_v2.spark_master.id
  volume_id   = var.nfs_volume
}

resource "openstack_compute_floatingip_associate_v2" "public_ip" {
  floating_ip = module.networking.floating_ip
  instance_id = openstack_compute_instance_v2.spark_master.id
}
