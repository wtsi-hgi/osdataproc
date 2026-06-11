output "master_ports" {
  value = [openstack_networking_port_v2.master.id]
}

output "workers_ports" {
  value = [for idx in range(var.workers) :
    [openstack_networking_port_v2.worker[idx].id]
  ]
}

output "lustre_ports" {
  value = openstack_networking_port_v2.lustre[*].id
}

output "worker_ips" {
  value = flatten(openstack_networking_port_v2.worker[*].all_fixed_ips)
}

output "master_ip" {
  value = openstack_networking_port_v2.master.all_fixed_ips[0]
}

output "floating_ip" {
  value = local.create_ip ? openstack_networking_floatingip_v2.floating_ip[0].address : var.floating_ip
}
