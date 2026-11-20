#!/usr/bin/env bash
# Ben's Airport: SSH-only Socat TCP relay manager for Debian 12+ and Ubuntu 22.04+.
# No web UI, nginx, XBoard, Docker or cloud APIs.
set -Eeuo pipefail
umask 077

MANAGER_PATH=/usr/local/sbin/socat-manager
CONFIG_DIR=/etc/bens-socat-manager
UNIT_DIR=/etc/systemd/system
BACKUP_DIR=/root/bens-socat-backups
PREFIX=bens-socat-

preflight() {
  [[ ${EUID} -eq 0 ]] || { echo 'ERROR: run as root (sudo bash ...).' >&2; exit 1; }
  [[ -r /etc/os-release ]] || { echo 'ERROR: cannot identify Linux distro.' >&2; exit 1; }
  # shellcheck source=/dev/null
  . /etc/os-release
  # Explicitly support Debian 12+ and Ubuntu 22.04+. Future versions
  # pass the version gate, but still require real-world compatibility tests.
  local major minor
  case "${ID:-}" in
    debian)
      [[ "${VERSION_ID:-}" =~ ^([0-9]+)(\.[0-9]+)?$ ]] || {
        echo "ERROR: Debian version is not numeric: ${VERSION_ID:-unknown}." >&2; exit 1;
      }
      major=$((10#${BASH_REMATCH[1]}))
      (( major >= 12 )) || {
        echo "ERROR: Debian 12+ required, found ${PRETTY_NAME:-unknown}." >&2; exit 1;
      }
      ;;
    ubuntu)
      [[ "${VERSION_ID:-}" =~ ^([0-9]+)\.([0-9]+)$ ]] || {
        echo "ERROR: Ubuntu version format not recognized: ${VERSION_ID:-unknown}." >&2; exit 1;
      }
      major=$((10#${BASH_REMATCH[1]}))
      minor=$((10#${BASH_REMATCH[2]}))
      (( major > 22 || (major == 22 && minor >= 4) )) || {
        echo "ERROR: Ubuntu 22.04+ required, found ${PRETTY_NAME:-unknown}." >&2; exit 1;
      }
      ;;
    *)
      echo "ERROR: only Debian 12+ or Ubuntu 22.04+ supported; found ${PRETTY_NAME:-unknown}." >&2
      exit 1
      ;;
  esac
  command -v systemctl >/dev/null || { echo 'ERROR: systemd missing.' >&2; exit 1; }
  echo "System: ${PRETTY_NAME}"
  echo "Host: $(hostname)"
  echo 'IPv4 addresses:'
  (ip -4 -br addr 2>/dev/null || hostname -I || true)
  echo 'Existing managed services:'
  (systemctl list-unit-files --type=service --no-legend 2>/dev/null | grep -E '^bens-socat-[0-9]+\.service ' || true)
  echo 'Existing listening ports:'
  (ss -H -lnt 2>/dev/null | awk '{print $4}' || true)
}

if [[ "${1:-}" == '--dry-run' ]]; then
  preflight
  echo
  echo '[DRY RUN] No changes have been made.'
  echo 'Install will: apt update; apt install socat iproute2; back up an old manager if one exists; write /usr/local/sbin/socat-manager.'
  echo 'Install will NOT create or enable any TCP forwarding rule, change firewall, DNS, Nginx or XBoard.'
  exit 0
fi
if [[ "${1:-}" != '--install' ]]; then
  echo 'Usage: bash relay2-socat-ssh-installer.sh --dry-run | --install'
  exit 2
fi
preflight
cat <<'NOTICE'

CAUTION: confirm that you are signed in to the intended VPS (Debian 12+ or Ubuntu 22.04+).
This installer does not modify existing forwarding services, firewalls or websites.
Type exactly INSTALL to continue; anything else cancels.
NOTICE
read -r -p 'Confirm: ' approval
[[ "$approval" == 'INSTALL' ]] || { echo 'Cancelled, no changes made.'; exit 0; }

apt-get update
apt-get install -y socat iproute2
command -v socat >/dev/null || { echo 'ERROR: socat not installed.' >&2; exit 1; }
command -v ss >/dev/null || { echo 'ERROR: ss not installed.' >&2; exit 1; }
install -d -m 700 "$CONFIG_DIR" "$BACKUP_DIR"
if [[ -e "$MANAGER_PATH" ]]; then
  cp -a "$MANAGER_PATH" "$BACKUP_DIR/socat-manager-pre-install-$(date -u +%Y%m%dT%H%M%SZ)-$$"
fi

cat > "$MANAGER_PATH" <<'MANAGER'
#!/usr/bin/env bash
# Ben's Airport Socat Manager: TCP/IPv4 per-port systemd units.
set -Eeuo pipefail
umask 077
CFG=/etc/bens-socat-manager
UNIT_DIR=/etc/systemd/system
BACKUPS=/root/bens-socat-backups
PFX=bens-socat-

needs_root() { (( EUID == 0 )) || { echo '請用 sudo socat-manager 或 root 執行'; exit 1; }; }
valid_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] || return 1
  (( 10#$1 >= 1024 && 10#$1 <= 65535 ))
}
valid_target_port() {
  [[ "$1" =~ ^[0-9]{1,5}$ ]] || return 1
  (( 10#$1 >= 1 && 10#$1 <= 65535 ))
}
# Strictly keep target free of socat address/option delimiters and spaces.
safe_host() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9.-]*$ && "$1" != *..* && ${#1} -le 253 ]]
}
service() { printf '%s%s.service' "$PFX" "$1"; }
cfgfile() { printf '%s/%s.conf' "$CFG" "$1"; }
unitfile() { printf '%s/%s' "$UNIT_DIR" "$(service "$1")"; }
read_cfg() {
  local p="$1" extra=""
  CONF_PORT=""; CONF_HOST=""; CONF_DEST=""
  [[ -f "$(cfgfile "$p")" ]] || return 1
  read -r CONF_PORT CONF_HOST CONF_DEST extra < "$(cfgfile "$p")" || true
  [[ "$CONF_PORT" == "$p" ]] && valid_port "$CONF_PORT" && safe_host "$CONF_HOST" && valid_target_port "$CONF_DEST" && [[ -z "$extra" ]]
}
backup_all() {
  local snap
  local unit
  snap=$(mktemp -d "$BACKUPS/$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")
  mkdir -p "$snap/config" "$snap/units"
  cp -a "$CFG"/. "$snap/config/" 2>/dev/null || true
  for unit in "$UNIT_DIR"/bens-socat-[0-9]*.service; do
    [[ -f "$unit" ]] || continue
