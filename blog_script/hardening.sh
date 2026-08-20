#!/usr/bin/env bash
# Idempotent host hardening. Run as root on Ubuntu 24.04.
set -euo pipefail

log() { printf '[%s] %s\n' "$(date -u +%FT%TZ)" "$*"; }
[[ ${EUID} -eq 0 ]] || { printf 'Run as root.\n' >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive
log 'Installing security packages'
apt-get update
apt-get install -y ufw fail2ban unattended-upgrades

log 'Applying SSH policy (Tailscale SSH only; public port 22 remains blocked)'
install -d -m 0755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-ghost.conf <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowUsers deploy
EOF
sshd -t
systemctl restart ssh

log 'Applying UFW policy'
ufw default deny incoming
ufw default allow outgoing
ufw allow 80/tcp comment 'Ghost HTTP / ACME'
ufw allow 443/tcp comment 'Ghost HTTPS'
# Do not add port 22. Tailscale SSH has no listening public port.
ufw --force enable

install -d -m 0755 /etc/fail2ban/jail.d
cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
maxretry = 4
findtime = 10m
bantime = 1h
EOF
systemctl enable --now fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades
log 'Hardening complete'
