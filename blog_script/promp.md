# Prompt: One-Click Ghost Deployment on Hetzner (Tunnel-Only Access)

## Role
You are a senior DevOps/platform engineer. Produce a **production-grade, idempotent, single-command deployment script** (plus supporting files) that stands up a self-hosted Ghost blog on a Hetzner Cloud VPS, with **no public SSH exposure** — all administrative access goes through an encrypted tunnel.

## Objective
Deliver a repo/script bundle that a user can run as:
```bash
cd blog_script
./deploy.sh
```
and end up with a hardened, running Ghost instance reachable over HTTPS, with SSH reachable *only* via a tunnel of the user's choosing.

## Hard Constraints
0. **Output location.** All deliverables — every script, config, compose file, and doc listed under Deliverables — must be created inside a single `blog_script/` folder at the project root (i.e. `./blog_script/deploy.sh`, `./blog_script/.env.example`, etc.). Nothing is written outside `blog_script/`, and no extra nested subfolder is introduced inside it — it is the one top-level container for the whole bundle. Any path referenced inside scripts (compose file paths, cloud-init references, cron/systemd unit ExecStart paths) must be relative to `blog_script/` and correct when the script is run from within that folder.
1. **No public SSH.** Port 22 must never be reachable from `0.0.0.0/0`. Enforce this at two layers: Hetzner Cloud Firewall (API-managed) *and* host-level `ufw`/`nftables`.
2. **Tunnel-based access only.** Support at least one of, ideally pluggable between:
   - **Tailscale SSH** (`tailscale up --ssh`, ACL-gated, no exposed port at all)
   - **Cloudflare Tunnel** (`cloudflared` sidecar exposing SSH via a private DNS name, zero open inbound ports)
   - **WireGuard** (self-hosted tunnel interface; SSH bound to the wg0 interface only)
   Script should accept a `TUNNEL_PROVIDER` variable and branch accordingly; default to Tailscale for simplicity.
3. **Idempotent & re-runnable.** Re-running the script on a partially-provisioned box should detect existing state and skip/repair rather than fail or duplicate resources.
4. **Non-interactive after config.** All inputs (domain, email, tunnel provider, Hetzner API token) come from a `.env` file or flags — validated up front, fail fast with clear errors if missing.
5. **Secrets never hit shell history or version control.** Read tokens from `.env` (git-ignored) or prompt with hidden input; no secrets in `ghost.yml`/compose files in plaintext without a documented mitigation.

## Functional Requirements

### A. Provisioning (local machine → Hetzner)
- Use `hcloud` CLI or Hetzner Cloud API via curl/terraform (pick one, justify choice).
- Create: server (CX22 or similar, Ubuntu 24.04 LTS), SSH key resource (for cloud-init bootstrap only, can be disabled/rotated after tunnel is live), Cloud Firewall with **only** 80/443 open publicly and 22 closed to the internet, private network if using WireGuard.
- Use `cloud-init`/user-data to bootstrap the box on first boot rather than relying on an initial SSH session, where possible.

### B. Tunnel setup
- Install and authenticate the chosen tunnel agent as a systemd service with auto-restart.
- Confirm tunnel connectivity before disabling any fallback SSH access.
- Document the exact command the operator will use afterward to connect (e.g., `tailscale ssh root@ghost-host`, `ssh -o ProxyCommand="cloudflared access ssh --hostname %h" ghost-host`).

### C. Host hardening
- `ufw`/`nftables` default-deny inbound except 80/443 (+ tunnel interface).
- `fail2ban` for the tunnel-facing SSH service.
- `unattended-upgrades` for security patches.
- Non-root deploy user with sudo, root login disabled.

### D. Ghost deployment
- Docker + Docker Compose stack: `ghost` (official image, pinned version) + `mysql:8` (or `db` volume with persistent storage) + a reverse proxy (Caddy or nginx+certbot) terminating TLS.
- Automatic HTTPS via Let's Encrypt (Caddy preferred for simplicity — auto-renewal built in).
- Persist Ghost content volume and DB volume; document backup strategy (e.g., nightly `mysqldump` + volume tarball pushed to Hetzner Storage Box or S3-compatible target via `restic`/`rclone`).
- Health check: script polls `https://$DOMAIN/ghost/api/admin/site/` (or equivalent) until Ghost responds 200 before declaring success.

### E. One-click orchestration (`deploy.sh`)
- Sequence: validate config → provision server → wait for cloud-init → establish tunnel → verify tunnel → harden host → deploy Ghost stack via tunnel connection (not public SSH) → verify HTTPS + Ghost health → print connection/access summary.
- Clear progress logging (step numbers, timestamps), and a `--teardown` flag to cleanly destroy the Hetzner resources.
- Exit non-zero with actionable error messages on any failed step; no silent partial states.

## Deliverables
All of the following live inside `blog_script/`:
1. `blog_script/deploy.sh` — orchestrator entrypoint.
2. `blog_script/.env.example` — documented required variables (`HETZNER_TOKEN`, `DOMAIN`, `EMAIL`, `TUNNEL_PROVIDER`, `TUNNEL_AUTH_KEY`, etc.).
3. `blog_script/cloud-init.yaml` — first-boot bootstrap (hardening + tunnel agent install).
4. `blog_script/docker-compose.yml` — Ghost + DB + reverse proxy stack.
5. `blog_script/hardening.sh` — idempotent, callable standalone for firewall/fail2ban/updates.
6. `blog_script/backup.sh` + cron/systemd-timer unit — automated backups.
7. `blog_script/README.md` — architecture diagram (ASCII is fine), prerequisites, run instructions, how to rotate/revoke tunnel access, disaster-recovery steps.

## Non-Functional Requirements
- Bash: `set -euo pipefail`, shellcheck-clean, functions over copy-paste, trap-based cleanup on failure.
- Target OS: Ubuntu 24.04 LTS on Hetzner CX-series.
- Should work from a fresh Hetzner project with zero pre-existing resources.
- Costs/resource sizing should be stated explicitly (CPU/RAM/disk) with a note on scaling up.
- Scripts must be runnable both from the project root (e.g. `./blog_script/deploy.sh`) and from inside `blog_script/` (e.g. `./deploy.sh`) — resolve their own directory (`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`) rather than assuming the caller's working directory.

## Explicitly Out of Scope
- Multi-node/HA Ghost setups.
- CI/CD pipeline for Ghost theme deployment (mention as a future extension only).
- Non-Hetzner cloud providers.

## Acceptance Criteria (script is "done" when)
- [ ] All generated files live under `blog_script/` with no stray files at the project root.
- [ ] Fresh Hetzner project → running `./blog_script/deploy.sh` produces a live HTTPS Ghost site with zero manual steps.
- [ ] `nmap -p 22 <server-ip>` from the public internet shows the port filtered/closed.
- [ ] Admin can SSH in successfully *only* via the configured tunnel.
- [ ] Re-running `./blog_script/deploy.sh` on the same server is a no-op (idempotent) and doesn't duplicate firewall rules, containers, or DNS entries.
- [ ] `./blog_script/deploy.sh --teardown` fully removes all created cloud resources.
- [ ] Backup script produces a restorable artifact, and restore steps are documented and tested.
