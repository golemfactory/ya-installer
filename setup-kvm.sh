#! /bin/bash

u=${1}

[ "${UID}" = 0 ] || {
  exec sudo "${0}" "${USER}"
  exit 1
}

function is_user_ingroup() {
  local user group

  user="${1}"
  group="${2}"
  local getent_output
  getent_output="$(getent group "${group}")" && grep -q "\b${user}\b" <<END
${getent_output}
END
  return ${?}
}

getent group kvm >/dev/null || groupadd kvm

cat <<EOF >/etc/udev/rules.d/60-golem-vm.rules
KERNEL=="kvm", GROUP="kvm", MODE="0660"
EOF

chown root:kvm /dev/kvm
setfacl -m "user:${u}:rw" /dev/kvm
is_user_ingroup "${u}" kvm || adduser "${u}" kvm

