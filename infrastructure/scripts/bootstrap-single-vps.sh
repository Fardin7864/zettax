#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run as root on a fresh Ubuntu 24.04 VPS." >&2
  exit 1
fi

DEPLOY_USER=${DEPLOY_USER:-primevest-deploy}
EMERGENCY_USER=${EMERGENCY_USER:-primevest-breakglass}
ADMIN_CIDR=${ADMIN_CIDR:?Set ADMIN_CIDR to the trusted SSH source, for example 203.0.113.10/32}
DEPLOY_SSH_PUBLIC_KEY=${DEPLOY_SSH_PUBLIC_KEY:?Set DEPLOY_SSH_PUBLIC_KEY to the deployment operator public key}
EMERGENCY_SSH_PUBLIC_KEY=${EMERGENCY_SSH_PUBLIC_KEY:?Set EMERGENCY_SSH_PUBLIC_KEY to a separately controlled emergency public key}
DATA_ROOT=/srv/primevest

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  auditd ca-certificates curl fail2ban jq nftables openssh-server \
  unattended-upgrades chrony age

for account in "${DEPLOY_USER}" "${EMERGENCY_USER}"; do
  if ! id "${account}" >/dev/null 2>&1; then
    adduser --disabled-password --gecos "" "${account}"
  fi
  usermod -aG sudo "${account}"
  install -d -m 0700 -o "${account}" -g "${account}" "/home/${account}/.ssh"
done
printf '%s\n' "${DEPLOY_SSH_PUBLIC_KEY}" >"/home/${DEPLOY_USER}/.ssh/authorized_keys"
printf '%s\n' "${EMERGENCY_SSH_PUBLIC_KEY}" >"/home/${EMERGENCY_USER}/.ssh/authorized_keys"
chown "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh/authorized_keys"
chown "${EMERGENCY_USER}:${EMERGENCY_USER}" "/home/${EMERGENCY_USER}/.ssh/authorized_keys"
chmod 0600 "/home/${DEPLOY_USER}/.ssh/authorized_keys" "/home/${EMERGENCY_USER}/.ssh/authorized_keys"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
. /etc/os-release
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
  "$(dpkg --print-architecture)" "${VERSION_CODENAME}" >/etc/apt/sources.list.d/docker.list
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
usermod -aG docker "${DEPLOY_USER}"

install -d -m 0750 -o root -g root /etc/primevest
install -d -m 0750 -o "${DEPLOY_USER}" -g "${DEPLOY_USER}" /opt/primevest /opt/primevest/infrastructure /opt/primevest/infrastructure/scripts
for path in postgres redis minio clamav prometheus alertmanager grafana loki promtail backups; do
  install -d -m 0750 "${DATA_ROOT}/${path}"
done
chown -R 70:70 "${DATA_ROOT}/postgres"
chown -R 999:1000 "${DATA_ROOT}/redis"
chown -R 1000:1000 "${DATA_ROOT}/minio"
chown -R 100:101 "${DATA_ROOT}/clamav"
chown -R 472:472 "${DATA_ROOT}/grafana"
chown -R 65534:65534 "${DATA_ROOT}/prometheus" "${DATA_ROOT}/alertmanager"
chown -R 10001:10001 "${DATA_ROOT}/loki"

install -m 0600 /dev/null /etc/ssh/sshd_config.d/99-primevest.conf
cat >/etc/ssh/sshd_config.d/99-primevest.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
X11Forwarding no
AllowTcpForwarding no
MaxAuthTries 3
LoginGraceTime 30
EOF
sshd -t
systemctl reload ssh

cat >/etc/sysctl.d/99-primevest.conf <<'EOF'
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.unprivileged_bpf_disabled=1
fs.protected_fifos=2
fs.protected_regular=2
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
EOF
sysctl --system >/dev/null

cat >/etc/nftables.conf <<EOF
table inet primevest_filter {
  chain input {
    type filter hook input priority 0; policy drop;
    ct state established,related accept
    iif lo accept
    ip protocol icmp accept
    ip6 nexthdr ipv6-icmp accept
    ip saddr ${ADMIN_CIDR} tcp dport 22 accept
    tcp dport { 80, 443 } accept
  }
}
EOF
systemctl enable --now docker nftables auditd fail2ban chrony unattended-upgrades

install -m 0755 infrastructure/single-vps/primevest.service /etc/systemd/system/primevest.service
install -m 0755 infrastructure/single-vps/primevest-backup.service /etc/systemd/system/primevest-backup.service
install -m 0755 infrastructure/single-vps/primevest-backup.timer /etc/systemd/system/primevest-backup.timer
install -m 0755 infrastructure/scripts/backup-single-vps.sh /opt/primevest/infrastructure/scripts/backup-single-vps.sh
systemctl daemon-reload
systemctl enable primevest.service
systemctl enable primevest-backup.timer

echo "Host baseline complete. Copy the repository to /opt/primevest and install /etc/primevest/production.env with owner root and mode 0600."
