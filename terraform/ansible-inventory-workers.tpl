[spark_workers]
%{ for ip in worker_ips ~}
ubuntu@${ip}
%{ endfor ~}

[all:vars]
spark_master_public_ip=${master_ip}

