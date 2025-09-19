terraform {
  backend "local" {
    path = "/tmp/terraform-state/terraform.tfstate"
  }
}
