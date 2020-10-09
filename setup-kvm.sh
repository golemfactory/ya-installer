#! /bin/bash

u=$1

[ "$UID" = 0 ] || {
  exec sudo "$0" $USER
  exit 1
}

getent group kvm >/dev/null || groupadd kvm

cat <<EOF >/etc/udev/rules.d/60-golem-vm.rules
KERNEL=="kvm", GROUP="kvm", MODE="0660"
EOF

chown root:kvm /dev/kvm
adduser $u kvm

