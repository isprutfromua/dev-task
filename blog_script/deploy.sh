#!/usr/bin/env bash
# Provision and deploy a single Ghost host through the Hetzner Cloud API and Tailscale SSH.
set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.state"
ENV_FILE="$SCRIPT_DIR/.env"
API_BASE='https://api.hetzner.cloud/v1'
CURRENT_STEP=0

log() { printf '[%s] [%02d] %s\n' "$(date -u +%FT%TZ)" "$CURRENT_STEP" "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
step() { CURRENT_STEP=$((CURRENT_STEP + 1)); log "$*"; }
cleanup() { [[ $? -eq 0 ]] || printf 'Deployment stopped; re-run ./deploy.sh after correcting the error.\n' >&2; }
trap cleanup EXIT
usage() { printf 'Usage: %s [--teardown]\n' "${0##*/}"; }
[[ $# -le 1 ]] || { usage; exit 2; }
TEARDOWN=false
if [[ ${1:-} == '--teardown' ]]; then TEARDOWN=true; elif [[ $# -eq 1 ]]; then usage; exit 2; fi

[[ -f "$ENV_FILE" ]] || die "Missing $ENV_FILE; copy .env.example to .env and configure it."
set -a
# shellcheck disable=SC1091
. "$ENV_FILE"
set +a
require() { [[ -n ${!1:-} ]] || die "$1 is required in .env"; }
for value in HETZNER_TOKEN DOMAIN EMAIL TUNNEL_PROVIDER TUNNEL_AUTH_KEY TAILSCALE_HOSTNAME; do require "$value"; done
[[ $TUNNEL_PROVIDER == tailscale ]] || die 'Only TUNNEL_PROVIDER=tailscale is currently implemented.'
[[ $DOMAIN =~ ^[A-Za-z0-9.-]+$ ]] || die 'DOMAIN must be a DNS hostname.'
[[ $EMAIL == *@* ]] || die 'EMAIL must be a valid email address.'
HETZNER_SERVER_TYPE=${HETZNER_SERVER_TYPE:-cx22}
HETZNER_LOCATION=${HETZNER_LOCATION:-fsn1}
HETZNER_IMAGE=${HETZNER_IMAGE:-ubuntu-24.04}
HETZNER_SERVER_NAME=${HETZNER_SERVER_NAME:-ghost-blog}
GHOST_IMAGE=${GHOST_IMAGE:-ghost:5.130.1-alpine}
MYSQL_IMAGE=${MYSQL_IMAGE:-mysql:8.4.6}
CADDY_IMAGE=${CADDY_IMAGE:-caddy:2.10.2-alpine}
for command in curl jq openssl base64 sed tar tailscale ssh-keygen getent; do command -v "$command" >/dev/null || die "Missing local prerequisite: $command"; done

api() {
  local method=$1 endpoint=$2 payload=${3:-}
  local -a args=(-fsS -X "$method" -H "Authorization: Bearer $HETZNER_TOKEN" -H 'Content-Type: application/json')
  [[ -n $payload ]] && args+=(--data "$payload")
  curl "${args[@]}" "$API_BASE$endpoint"
}
find_one() {
  local endpoint=$1
  shift
  api GET "$endpoint" | jq -r "$@"
}
write_state() { umask 077; printf 'SERVER_ID=%q\nFIREWALL_ID=%q\nSSH_KEY_ID=%q\n' "${SERVER_ID:-}" "${FIREWALL_ID:-}" "${SSH_KEY_ID:-}" >"$STATE_FILE"; }

teardown() {
  step 'Looking up labelled Hetzner resources for teardown'
  SERVER_ID=$(find_one '/servers' --arg n "$HETZNER_SERVER_NAME" '[.servers[] | select(.name == $n and .labels.managed_by == "blog_script") | .id][0] // ""')
  FIREWALL_ID=$(find_one '/firewalls' --arg n "${HETZNER_SERVER_NAME}-firewall" '[.firewalls[] | select(.name == $n and .labels.managed_by == "blog_script") | .id][0] // ""')
  SSH_KEY_ID=$(find_one '/ssh_keys' --arg n "${HETZNER_SERVER_NAME}-bootstrap" '[.ssh_keys[] | select(.name == $n and .labels.managed_by == "blog_script") | .id][0] // ""')
  [[ -z ${SERVER_ID:-} ]] || { log "Deleting server $SERVER_ID"; api DELETE "/servers/$SERVER_ID" >/dev/null; }
  [[ -z ${FIREWALL_ID:-} ]] || { log "Deleting firewall $FIREWALL_ID"; api DELETE "/firewalls/$FIREWALL_ID" >/dev/null; }
  [[ -z ${SSH_KEY_ID:-} ]] || { log "Deleting bootstrap SSH key $SSH_KEY_ID"; api DELETE "/ssh_keys/$SSH_KEY_ID" >/dev/null; }
  rm -f "$STATE_FILE" "$SCRIPT_DIR/.bootstrap_id_ed25519" "$SCRIPT_DIR/.bootstrap_id_ed25519.pub"
  log 'Teardown complete. Persistent volumes are deleted with the server.'
}
if $TEARDOWN; then teardown; exit 0; fi

step 'Checking local Tailscale connectivity'
tailscale status --json | jq -e '.BackendState == "Running"' >/dev/null || die 'Connect this workstation to Tailscale first.'
step 'Creating or reusing the public-web-only Hetzner firewall'
FIREWALL_ID=$(find_one '/firewalls' --arg n "${HETZNER_SERVER_NAME}-firewall" '[.firewalls[] | select(.name == $n and .labels.managed_by == "blog_script") | .id][0] // ""')
if [[ -z $FIREWALL_ID ]]; then
  firewall_payload=$(jq -nc --arg name "${HETZNER_SERVER_NAME}-firewall" '{name:$name,labels:{managed_by:"blog_script",purpose:"ghost"},rules:[{direction:"in",protocol:"tcp",port:"80",source_ips:["0.0.0.0/0","::/0"],description:"HTTP ACME redirect"},{direction:"in",protocol:"tcp",port:"443",source_ips:["0.0.0.0/0","::/0"],description:"HTTPS Ghost"}]}')
  FIREWALL_ID=$(api POST '/firewalls' "$firewall_payload" | jq -er '.firewall.id')
fi
step 'Creating or reusing the Hetzner server'
SERVER_ID=$(find_one '/servers' --arg n "$HETZNER_SERVER_NAME" '[.servers[] | select(.name == $n and .labels.managed_by == "blog_script") | .id][0] // ""')
if [[ -z $SERVER_ID ]]; then
  BOOTSTRAP_KEY_FILE=${SSH_PUBLIC_KEY_FILE:-"$SCRIPT_DIR/.bootstrap_id_ed25519.pub"}
  if [[ ! -f $BOOTSTRAP_KEY_FILE ]]; then ssh-keygen -q -t ed25519 -N '' -f "$SCRIPT_DIR/.bootstrap_id_ed25519"; BOOTSTRAP_KEY_FILE="$SCRIPT_DIR/.bootstrap_id_ed25519.pub"; fi
  BOOTSTRAP_KEY=$(<"$BOOTSTRAP_KEY_FILE")
  ssh_payload=$(jq -nc --arg name "${HETZNER_SERVER_NAME}-bootstrap" --arg key "$BOOTSTRAP_KEY" '{name:$name,public_key:$key,labels:{managed_by:"blog_script",purpose:"bootstrap"}}')
  SSH_KEY_ID=$(api POST '/ssh_keys' "$ssh_payload" | jq -er '.ssh_key.id')
  rendered_cloud_init=$(mktemp)
  BOOTSTRAP_KEY_SED=$(printf '%s' "$BOOTSTRAP_KEY" | sed 's/[\\&|]/\\&/g')
  TUNNEL_AUTH_KEY_SED=$(printf '%s' "$TUNNEL_AUTH_KEY" | sed 's/[\\&|]/\\&/g')
  TAILSCALE_HOSTNAME_SED=$(printf '%s' "$TAILSCALE_HOSTNAME" | sed 's/[\\&|]/\\&/g')
  sed -e "s|__BOOTSTRAP_SSH_KEY__|$BOOTSTRAP_KEY_SED|" -e "s|__TAILSCALE_AUTH_KEY__|$TUNNEL_AUTH_KEY_SED|" -e "s|__TAILSCALE_HOSTNAME__|$TAILSCALE_HOSTNAME_SED|" "$SCRIPT_DIR/cloud-init.yaml" >"$rendered_cloud_init"
  server_payload=$(jq -nc --arg name "$HETZNER_SERVER_NAME" --arg type "$HETZNER_SERVER_TYPE" --arg image "$HETZNER_IMAGE" --arg location "$HETZNER_LOCATION" --argjson key "$SSH_KEY_ID" --argjson firewall "$FIREWALL_ID" --rawfile user_data "$rendered_cloud_init" '{name:$name,server_type:$type,image:$image,location:$location,ssh_keys:[$key],firewalls:[{firewall:$firewall}],user_data:$user_data,labels:{managed_by:"blog_script",purpose:"ghost"}}')
  SERVER_ID=$(api POST '/servers' "$server_payload" | jq -er '.server.id')
  rm -f "$rendered_cloud_init"
fi
write_state
SERVER_IP=$(api GET "/servers/$SERVER_ID" | jq -er '.server.public_net.ipv4.ip')
log "Server IPv4: $SERVER_IP (only 80/443 are allowed by the cloud firewall)"
step 'Waiting for cloud-init and Tailscale SSH enrollment'
for attempt in {1..90}; do
  if tailscale ssh "deploy@$TAILSCALE_HOSTNAME" -- 'cloud-init status --wait >/dev/null 2>&1 && test -S /var/run/docker.sock'; then break; fi
  (( attempt == 90 )) && die 'Timed out waiting for Tailscale/cloud-init. Check the auth key and server console.'
  sleep 10
done
tailscale ssh "deploy@$TAILSCALE_HOSTNAME" -- true || die 'Tailscale SSH verification failed; host hardening will not continue.'
step 'Installing bundle and applying host hardening through Tailscale SSH'
tar -C "$SCRIPT_DIR" -cf - docker-compose.yml Caddyfile hardening.sh backup.sh ghost-backup.service ghost-backup.timer | tailscale ssh "deploy@$TAILSCALE_HOSTNAME" -- 'sudo mkdir -p /opt/ghost && sudo tar -xf - -C /opt/ghost && sudo chown -R deploy:deploy /opt/ghost && chmod 700 /opt/ghost/{hardening.sh,backup.sh}'
tailscale ssh "deploy@$TAILSCALE_HOSTNAME" -- 'sudo /opt/ghost/hardening.sh && sudo apt-get update && sudo apt-get install -y restic'
step 'Creating protected runtime configuration if absent'
if ! tailscale ssh "deploy@$TAILSCALE_HOSTNAME" -- 'test -s /opt/ghost/.env'; then
  MYSQL_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
  MYSQL_ROOT_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
  {
    printf 'DOMAIN=%q\nEMAIL=%q\nGHOST_IMAGE=%q\nMYSQL_IMAGE=%q\nCADDY_IMAGE=%q\nMYSQL_PASSWORD=%q\nMYSQL_ROOT_PASSWORD=%q\n' "$DOMAIN" "$EMAIL" "$GHOST_IMAGE" "$MYSQL_IMAGE" "$CADDY_IMAGE" "$MYSQL_PASSWORD" "$MYSQL_ROOT_PASSWORD"
    for variable in RESTIC_REPOSITORY RESTIC_PASSWORD AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION; do [[ -z ${!variable:-} ]] || printf '%s=%q\n' "$variable" "${!variable}"; done
  } | tailscale ssh "deploy@$TAILSCALE_HOSTNAME" -- 'umask 077; cat > /opt/ghost/.env; chmod 600 /opt/ghost/.env'
fi
step 'Confirming DNS points at the new server before requesting HTTPS'
DNS_IP=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1 {print $1}')
[[ $DNS_IP == "$SERVER_IP" ]] || die "DNS for $DOMAIN resolves to ${DNS_IP:-nothing}, not $SERVER_IP. Create its A record, wait for propagation, then re-run."
step 'Starting Ghost and Caddy over the encrypted management tunnel'
tailscale ssh "deploy@$TAILSCALE_HOSTNAME" -- 'cd /opt/ghost && docker compose up -d --remove-orphans && sudo install -m 0644 ghost-backup.service /etc/systemd/system/ghost-backup.service && sudo install -m 0644 ghost-backup.timer /etc/systemd/system/ghost-backup.timer && sudo systemctl daemon-reload && sudo systemctl enable --now ghost-backup.timer'
step 'Polling HTTPS Ghost health endpoint'
for attempt in {1..36}; do
  if curl --fail --silent --show-error --max-time 15 "https://$DOMAIN/ghost/api/admin/site/" >/dev/null; then break; fi
  (( attempt == 36 )) && die 'Ghost did not become healthy. Inspect with: tailscale ssh deploy@HOST -- "cd /opt/ghost && docker compose logs"'
  sleep 10
done
step 'Removing the bootstrap key after tunnel verification'
SSH_KEY_ID=$(find_one '/ssh_keys' --arg n "${HETZNER_SERVER_NAME}-bootstrap" '[.ssh_keys[] | select(.name == $n and .labels.managed_by == "blog_script") | .id][0] // ""')
[[ -z ${SSH_KEY_ID:-} ]] || api DELETE "/ssh_keys/$SSH_KEY_ID" >/dev/null
rm -f "$SCRIPT_DIR/.bootstrap_id_ed25519" "$SCRIPT_DIR/.bootstrap_id_ed25519.pub"
write_state
printf '\nDeployment complete.\nPublic site: https://%s\nAdmin SSH: tailscale ssh deploy@%s\nGhost admin: https://%s/ghost/\nPublic port 22: blocked by Hetzner Firewall and UFW.\n' "$DOMAIN" "$TAILSCALE_HOSTNAME" "$DOMAIN"
