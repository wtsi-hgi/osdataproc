#!/bin/bash -eux

exec >>/var/log/user_data.log 2>&1

# Re-run user_data on reboot
rm -f /var/lib/cloud/instance/sem/config_scripts_user

REPO=https://github.com/wtsi-hgi/osdataproc.git
BRANCH=faster-downloads-updated-versions
FOLDER=/tmp/osdataproc

export DEBIAN_FRONTEND=noninteractive

wait_for_apt_locks() {
  while \
    fuser /var/lib/dpkg/lock >/dev/null 2>&1 || \
    fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
    fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
    fuser /var/cache/apt/archives/lock >/dev/null 2>&1 || \
    systemctl is-active --quiet apt-daily.service || \
    systemctl is-active --quiet apt-daily-upgrade.service; do
    echo "Waiting for apt/dpkg locks to be released..."
    sleep 10
  done
}

# Wait for system to be ready and prevent background apt jobs racing setup.
sleep 30
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer || true
systemctl stop apt-daily.service apt-daily-upgrade.service unattended-upgrades.service || true
systemctl mask apt-daily.service apt-daily-upgrade.service unattended-upgrades.service || true
wait_for_apt_locks

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
apt_updated=false
for i in {1..3}; do
    wait_for_apt_locks
    if apt-get update; then
        apt_updated=true
        break
    fi
    echo "apt update failed, attempt $i/3, retrying in 30 seconds..."
    sleep 30
done
$apt_updated || exit 1

wait_for_apt_locks
apt-get install -y software-properties-common
wait_for_apt_locks
apt-add-repository --yes --update ppa:ansible/ansible

# Force non-interactive install with retries
ansible_installed=false
for i in {1..3}; do
    wait_for_apt_locks
    if UCF_FORCE_CONFOLD=1 \
    DEBCONF_NONINTERACTIVE_SEEN=true \
    apt-get -o Dpkg::Options::="--force-confdef" \
            -o Dpkg::Options::="--force-confold" \
            -qq -y install ansible; then
        ansible_installed=true
        break
    fi
    echo "ansible installation failed, attempt $i/3, retrying in 30 seconds..."
    sleep 30
done
$ansible_installed || exit 1

# Run ansible with retries
ansible_configured=false
for i in {1..2}; do
    if ansible-playbook /tmp/osdataproc/ansible/main.yml \
                     -i localhost \
                     -e ansible_python_interpreter=/usr/bin/python3 \
                     -e spark_master_private_ip=${master} \
                     -e netdata_api_key=${netdata_api_key} \
                     -e nfs_volume=${nfs_volume} \
                     -e '@/tmp/osdataproc/vars.yml' \
                     --skip-tags=master; then
        ansible_configured=true
        break
    fi
    echo "ansible-playbook failed, attempt $i/2, retrying in 60 seconds..."
    sleep 60
done
$ansible_configured || exit 1
