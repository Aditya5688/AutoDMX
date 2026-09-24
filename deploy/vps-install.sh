#!/usr/bin/env bash
set -euo pipefail

# AutoDMX self-hosted VPS installer for Ubuntu/Debian.
# Usage:
#   sudo bash deploy/vps-install.sh
# Optional custom hostname:
#   sudo AUTODMX_HOST=autodmx.example.com bash deploy/vps-install.sh

APP_DIR="/opt/autodmx"
REPO_URL="https://github.com/Aditya5688/AutoDMX.git"
ENV_FILE="/etc/autodmx.env"
PORT="3000"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this installer as root (sudo)."
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git caddy nodejs npm

NODE_MAJOR="$(node -p 'process.versions.node.split(`.`)[0]' 2>/dev/null || echo 0)"
if [[ "${NODE_MAJOR}" -lt 18 ]]; then
  echo "Node.js 18+ is required. Installed version: $(node -v 2>/dev/null || echo none)"
  exit 1
fi

# A small swapfile makes npm/Next.js builds safer on 1 GB VPS instances.
if ! swapon --show | grep -q '^'; then
  if [[ ! -f /swapfile ]]; then
    fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
    chmod 600 /swapfile
    mkswap /swapfile
  fi
  swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "${APP_DIR}" fetch --all --prune
  git -C "${APP_DIR}" reset --hard origin/main
else
  rm -rf "${APP_DIR}"
  git clone "${REPO_URL}" "${APP_DIR}"
fi

cd "${APP_DIR}"
npm ci
npm run build

if [[ ! -f "${ENV_FILE}" ]]; then
  cat > "${ENV_FILE}" <<'EOF'
NEXT_PUBLIC_SUPABASE_URL=
SUPABASE_SERVICE_ROLE_KEY=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
ENCRYPTION_KEY=
META_VERIFY_TOKEN=
META_APP_SECRET=
META_APP_ID=
META_INITIAL_ACCESS_TOKEN=
CRON_SECRET=
DASHBOARD_PASSWORD=
NEXT_PUBLIC_CONTACT_EMAIL=
OPERATOR_NAME=Vegas AI Studios
NEXT_PUBLIC_SITE_URL=
EOF
  chmod 600 "${ENV_FILE}"
  echo
  echo "Created ${ENV_FILE}. Fill in the required secrets, then run this installer again."
  exit 2
fi

required=(
  NEXT_PUBLIC_SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
  NEXT_PUBLIC_SUPABASE_ANON_KEY
  ENCRYPTION_KEY
  META_VERIFY_TOKEN
  META_APP_SECRET
  META_APP_ID
  META_INITIAL_ACCESS_TOKEN
  CRON_SECRET
  DASHBOARD_PASSWORD
)
for key in "${required[@]}"; do
  value="$(grep -E "^${key}=" "${ENV_FILE}" | tail -n1 | cut -d= -f2- || true)"
  if [[ -z "${value}" ]]; then
    echo "Missing ${key} in ${ENV_FILE}"
    exit 3
  fi
done

cat > /etc/systemd/system/autodmx.service <<EOF
[Unit]
Description=AutoDMX Next.js service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
EnvironmentFile=${ENV_FILE}
Environment=NODE_ENV=production
ExecStart=/usr/bin/npm start -- -p ${PORT}
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/autodmx-cron.service <<'EOF'
[Unit]
Description=Drain AutoDMX send queue
After=autodmx.service

[Service]
Type=oneshot
EnvironmentFile=/etc/autodmx.env
ExecStart=/bin/bash -lc 'curl -fsS -X POST http://127.0.0.1:3000/api/cron/drain-queue -H "Authorization: Bearer ${CRON_SECRET}" >/dev/null'
EOF

cat > /etc/systemd/system/autodmx-cron.timer <<'EOF'
[Unit]
Description=Run AutoDMX queue drain every 10 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=10min
Persistent=true

[Install]
WantedBy=timers.target
EOF

PUBLIC_IP="$(curl -4fsS https://api.ipify.org || true)"
if [[ -n "${AUTODMX_HOST:-}" ]]; then
  HOST="${AUTODMX_HOST}"
elif [[ -n "${PUBLIC_IP}" ]]; then
  HOST="${PUBLIC_IP//./-}.sslip.io"
else
  echo "Could not determine public IP. Re-run with AUTODMX_HOST=your-domain.example"
  exit 4
fi

# Fill NEXT_PUBLIC_SITE_URL automatically when left blank.
if grep -q '^NEXT_PUBLIC_SITE_URL=$' "${ENV_FILE}"; then
  sed -i "s|^NEXT_PUBLIC_SITE_URL=$|NEXT_PUBLIC_SITE_URL=https://${HOST}|" "${ENV_FILE}"
fi

cat > /etc/caddy/Caddyfile <<EOF
${HOST} {
  encode gzip zstd
  reverse_proxy 127.0.0.1:${PORT}
}
EOF

systemctl daemon-reload
systemctl enable --now autodmx.service
systemctl enable --now autodmx-cron.timer
systemctl enable --now caddy
systemctl restart caddy autodmx.service

sleep 2
systemctl --no-pager --full status autodmx.service || true

echo
echo "AutoDMX deployed: https://${HOST}"
echo "Dashboard: https://${HOST}/dashboard"
echo "Meta webhook: https://${HOST}/api/webhook"
