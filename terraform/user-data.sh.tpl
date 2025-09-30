#!/bin/bash -eux

exec >>/var/log/user_data.log 2>&1

# Re-run user_data on reboot
rm -f /var/lib/cloud/instance/sem/config_scripts_user

REPO=https://github.com/wtsi-hgi/osdataproc.git
BRANCH=master
FOLDER=/tmp/osdataproc

# Wait for system to be ready and avoid dpkg lock conflicts
sleep 30
while sudo fuser /var/lib/dpkg/lock >/dev/null 2>&1 || sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
    echo "Waiting for dpkg lock to be released..."
    sleep 10
done

if ! [[ -d $FOLDER ]]; then
  git clone -b $BRANCH $REPO $FOLDER
fi

if ! grep -Eq "spark-master$" /etc/hosts; then
  cat >>/etc/hosts <<-EOF
${master} spark-master
%{ for host, ip in workers ~}
${ip} ${host}
%{ endfor ~}
EOF
fi

# Retry apt operations with better error handling
for i in {1..3}; do
    if apt update; then
        break
    fi
    echo "apt update failed, attempt $i/3, retrying in 30 seconds..."
    sleep 30
done

apt install software-properties-common -y
apt-add-repository --yes --update ppa:ansible/ansible

# Force non-interactive install with retries
for i in {1..3}; do
    if UCF_FORCE_CONFOLD=1 \
    DEBIAN_FRONTEND=noninteractive \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            -qq -y install ansible; then
        break
    fi
    echo "ansible installation failed, attempt $i/3, retrying in 30 seconds..."
    sleep 30
done

# Run ansible with retries
for i in {1..2}; do
    if ansible-playbook /tmp/osdataproc/ansible/main.yml \
                     -i localhost \
                     -e ansible_python_interpreter=/usr/bin/python3 \
                     -e spark_master_private_ip=${master} \
                     -e netdata_api_key=${netdata_api_key} \
                     -e nfs_volume=${nfs_volume} \
                     -e '@/tmp/osdataproc/vars.yml' \
                     --skip-tags=master; then
        break
    fi
    echo "ansible-playbook failed, attempt $i/2, retrying in 60 seconds..."
    sleep 60
done
