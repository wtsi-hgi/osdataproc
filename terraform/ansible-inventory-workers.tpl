[spark_workers]
%{ for ip in worker_ips ~}
ubuntu@${ip}
%{ endfor ~}

[all:vars]
spark_master_public_ip=${master_ip}
ansible_ssh_common_args=-o IdentitiesOnly=yes -o ProxyJump=ubuntu@${master_ip}
