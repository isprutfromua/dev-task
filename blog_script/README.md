# Hardened Ghost on Hetzner Cloud

This bundle provisions one Ubuntu 24.04 Hetzner CX server, a labelled cloud firewall, and a Dockerized Ghost stack. The firewall permits only public TCP 80 and 443; it deliberately has no TCP 22 rule. The host also applies UFW default-deny inbound policy with only 80/443 allowed, so public SSH is blocked at two independent layers. Tailscale joins outbound using an auth key and enables Tailscale SSH, which means administrative sessions use encrypted tailnet connectivity and are ACL-gated rather than exposed to the internet. Caddy obtains and renews Let's Encrypt certificates, while Ghost content, MySQL data, and Caddy ACME state use Docker volumes. Deployment files and runtime secrets are installed through Tailscale SSH only after tunnel connectivity is verified. The deployment is label-based and re-runnable: it reuses the server/firewall and leaves existing remote database credentials unchanged. A nightly restic timer makes encrypted, consistent database-plus-content backups when backup credentials are configured.

## Architecture

~~~text
Internet -- 80/443 --> Hetzner Firewall --> UFW --> Caddy --> Ghost --> MySQL
                                |
                   TCP/22: no rule / denied

Administrator -- encrypted Tailscale tailnet --> Tailscale SSH --> deploy user
                                                       |
                                                 Docker / backups
~~~

## Files

~~~text
blog_script/
├── .env.example
├── .gitignore
├── Caddyfile
├── README.md
├── backup.sh
├── cloud-init.yaml
├── deploy.sh
├── docker-compose.yml
├── ghost-backup.service
├── ghost-backup.timer
└── hardening.sh
~~~

## Prerequisites

- A Hetzner Cloud project API token with read/write access.
- A local workstation connected to the same Tailscale tailnet, with the tailscale CLI installed and logged in.
- A reusable or ephemeral Tailscale auth key allowed to use tag:ghost (recommended), and ACL rules permitting your operator identity to Tailscale SSH to that tag.
- bash, curl, jq, openssl, ssh-keygen, tar, and getent locally.
- A DNS A record for DOMAIN. The script prints the Hetzner IP, then waits for that record before ACME can run. A Hetzner Cloud token cannot manage arbitrary third-party DNS.

CX22 provides 2 shared vCPUs, 4 GB RAM, and 40 GB disk: suitable for a modest single Ghost site. Scale the server in Hetzner after monitoring memory, storage, and database load; this is deliberately a single-node, non-HA design.

## How to run

~~~bash
cd blog_script
cp .env.example .env
chmod 600 .env
# Edit .env: set HETZNER_TOKEN, DOMAIN, EMAIL, TUNNEL_AUTH_KEY and TAILSCALE_HOSTNAME.
./deploy.sh
~~~

On a first deployment the script prints the new public IPv4 address and stops at DNS validation if necessary. Add DOMAIN's A record at your DNS provider, wait for propagation, and re-run ./deploy.sh. Public SSH is never opened during this process.

After success:

~~~bash
tailscale ssh deploy@ghost-blog
# Visit https://blog.example.com/ghost/ to finish first-time Ghost setup.
~~~

To validate the public SSH boundary from a machine outside the tailnet:

~~~bash
nmap -Pn -p 22 SERVER_IPV4
~~~

It should report port 22 filtered or closed; HTTPS should be open.

## Backups and recovery

Set RESTIC_REPOSITORY and RESTIC_PASSWORD in local .env before the first deploy, plus applicable S3 credentials. The values are installed only in /opt/ghost/.env (mode 0600), and ghost-backup.timer runs daily at 03:15 UTC. Backups include a MySQL dump, Ghost content tarball, and compose/Caddy configuration, encrypted client-side by restic. Test it:

~~~bash
tailscale ssh deploy@ghost-blog -- 'sudo systemctl start ghost-backup.service && sudo systemctl status ghost-backup.service'
~~~

For recovery on a replacement host: stop the stack, restore the chosen restic snapshot to a temporary directory, import ghost.sql using the root password in /opt/ghost/.env, and extract ghost-content.tar.gz into the ghost_content volume. Start the stack and verify https://DOMAIN/ghost/. Conduct and record a restore drill before relying on backups.

## Access rotation and teardown

Revoke a lost administrator in Tailscale ACLs immediately; it blocks their SSH without changing the public firewall. Rotate the enrollment key by updating /etc/default/ghost-tunnel through an authorized Tailscale session, restarting ghost-tailscale-up, and then revoking the old key in Tailscale. Keep an authorized admin before editing ACLs.

~~~bash
cd blog_script
./deploy.sh --teardown
~~~

Teardown removes only resources labelled as managed by this bundle: server, attached volumes, firewall, and bootstrap SSH key. Confirm a tested off-host backup exists first. Theme CI/CD, multi-node/HA Ghost, and non-Hetzner providers are future extensions outside this single-server baseline.

