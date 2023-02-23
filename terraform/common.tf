provider "openstack" {}
provider "local" {}
provider "cloudinit" {}

module "security_groups" {
  source     = "./security-groups"
  identifier = local.name_prefix
}

module "networking" {
  source = "./networking"

  identifier      = local.name_prefix
  workers         = var.workers
  network_name    = var.network_name
  lustre_network  = var.lustre_network
  floating_ip     = var.spark_master_public_ip
  security_groups = module.security_groups
}

resource "openstack_compute_keypair_v2" "spark_keypair" {
  name       = "${local.name_prefix}-keypair"
  public_key = var.identity_file
}

data "openstack_compute_flavor_v2" "input_flavour" {
  name = var.flavor_name
  lifecycle {
    postcondition {  # Available disk space must be more than 13GB
      condition     = self.disk > 13
      error_message = "OpenStack VM must have at least 14GB disk space"
    }
  }
}
