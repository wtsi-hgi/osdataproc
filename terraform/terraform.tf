terraform {
  required_version = ">= 0.12"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.32.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5.0"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2.3.0"
    }
  }
  backend "local" {
    path = "/tmp/terraform-state/terraform.tfstate"
  }
}
