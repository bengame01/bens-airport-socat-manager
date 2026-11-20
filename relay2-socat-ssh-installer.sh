#!/usr/bin/env bash
# Ben's Airport: SSH-only Socat TCP relay manager for Debian 13.
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
  [[ "${ID:-}" == debian && "${VERSION_ID:-}" == 13 ]] || {
    echo "ERROR: expected Debian 13, found ${PRETTY_NAME:-unknown}." >&2; exit 1;
  }
  command -v systemctl >/dev/null || { echo 'ERROR: systemd missing.' >&2; exit 1; }
  echo "System: ${PRETTY_NAME}"
  echo "Host: $(hostname)"
  echo 'IPv4 addresses:'
  (ip -4 -br addr 2>/dev/null || hostname -I || true)
  echo 'DNS relay2.boosa285280.xyz (informational only):'
  (getent ahostsv4 relay2.boosa285280.xyz | awk 'NR==1{print $1}' || true)
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

CAUTION: confirm that you are signed in to the REINSTALLED Japanese relay2 VPS (151.242.165.19).
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
    cp -a "$unit" "$snap/units/"
  done
  echo "已備份：$snap"
}
used_port() {
  ss -H -lnt "sport = :$1" 2>/dev/null | grep -q .
}
show_list() {
  local f p state enable h d
  echo
  printf '%-8s %-28s %-9s %-9s %s\n' '本地TCP' '目的地' '運行中' '開機啟動' '設定'
  local found=0
  for f in "$CFG"/[0-9]*.conf; do
    [[ -f "$f" ]] || continue
    p="${f##*/}"; p="${p%.conf}"
    [[ "$p" =~ ^[0-9]+$ ]] || continue
    if read_cfg "$p"; then
      h="$CONF_HOST"; d="$CONF_DEST"
      state=$(systemctl is-active "$(service "$p")" 2>/dev/null || true)
      enable=$(systemctl is-enabled "$(service "$p")" 2>/dev/null || true)
      printf '%-8s %-28s %-9s %-9s %s\n' "$p" "$h:$d" "$state" "$enable" 'OK'
    else
      printf '%-8s %-28s %-9s %-9s %s\n' "$p" '-' '-' '-' '設定需檢查'
    fi
    found=1
  done
  (( found )) || echo '未有由本管理器建立嘅中轉。'
  echo
}
write_unit() {
  local p="$1" host="$2" dp="$3" tmp
  tmp=$(mktemp "$UNIT_DIR/.bens-socat-XXXXXXXX")
  cat > "$tmp" <<EOF
[Unit]
Description=Ben's Airport Socat TCP4 relay ${p} to ${host}:${dp}
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
ExecStart=/usr/bin/socat -d -d TCP4-LISTEN:${p},reuseaddr,fork TCP4:${host}:${dp}
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$tmp"
  mv -f "$tmp" "$(unitfile "$p")"
}
create() {
  local p host dp confirm name
  read -r -p '新中轉本地 TCP 端口 (1024-65535): ' p
  valid_port "$p" || { echo '端口格式或範圍錯誤'; return; }
  if [[ -e "$(cfgfile "$p")" || -e "$(unitfile "$p")" ]]; then
    echo '已有本管理器設定，請用修改功能'; return
  fi
  if used_port "$p"; then
    echo '端口已被其他進程使用，唔會覆蓋'; ss -H -lntup "sport = :$p" || true; return
  fi
  read -r -p '目標 IPv4 或域名 (不可有冒號): ' host
  safe_host "$host" || { echo '目標格式唔正確'; return; }
  read -r -p '目標 TCP 端口 (1-65535): ' dp
  valid_target_port "$dp" || { echo '目標端口需為 1-65535'; return; }
  echo
  echo '[Dry Run] 將建立 TCP4 0.0.0.0:'"$p"' -> '"$host:$dp"
  echo '會建立獨立 systemd 服務，並立即啟動及設為開機自動啟動。'
  read -r -p '輸入 YES 正式建立：' confirm
  [[ "$confirm" == YES ]] || { echo '已取消'; return; }
  backup_all
  printf '%s %s %s\n' "$p" "$host" "$dp" > "$(cfgfile "$p")"
  chmod 600 "$(cfgfile "$p")"
  write_unit "$p" "$host" "$dp"
  systemctl daemon-reload
  name="$(service "$p")"
  if systemctl enable --now "$name" && systemctl is-active --quiet "$name"; then
    echo "成功啟動：$name"
    ss -H -lntup "sport = :$p" || true
  else
    echo '啟動失敗；清理今次新增嘅服務。'
    journalctl -u "$name" -n 15 --no-pager || true
    systemctl disable --now "$name" >/dev/null 2>&1 || true
    rm -f "$(cfgfile "$p")" "$(unitfile "$p")"
    systemctl daemon-reload
    echo '已還原至建立前狀態。'
  fi
}
change_target() {
  local p host dp confirm oldunit oldcfg name
  read -r -p '要修改嘅本地端口：' p
  valid_port "$p" && read_cfg "$p" || { echo '未找到有效管理記錄'; return; }
  echo "目前 TCP4 :$p -> $CONF_HOST:$CONF_DEST"
  read -r -p '新目標 IPv4 或域名：' host
  safe_host "$host" || { echo '格式錯誤'; return; }
  read -r -p '新目標 TCP 端口 (1-65535)：' dp
  valid_target_port "$dp" || { echo '端口錯誤'; return; }
  echo "[Dry Run] :$p -> $host:$dp；會短暫重啟此單一中轉服務。"
  read -r -p '輸入 YES 正式修改：' confirm
  [[ "$confirm" == YES ]] || { echo '已取消'; return; }
  backup_all
  oldunit=$(mktemp); oldcfg=$(mktemp)
  cp -a "$(unitfile "$p")" "$oldunit"
  cp -a "$(cfgfile "$p")" "$oldcfg"
  name="$(service "$p")"
  systemctl stop "$name" || true
  printf '%s %s %s\n' "$p" "$host" "$dp" > "$(cfgfile "$p")"
  write_unit "$p" "$host" "$dp"
  systemctl daemon-reload
  if systemctl start "$name" && systemctl is-active --quiet "$name"; then
    echo '已更新目標及重新啟動。'
  else
    echo '更新失敗，還原之前設定。'
    cp -a "$oldunit" "$(unitfile "$p")"
    cp -a "$oldcfg" "$(cfgfile "$p")"
    systemctl daemon-reload
    systemctl start "$name" || echo '原設定重新啟動失敗，請檢查 journalctl！'
  fi
  rm -f "$oldunit" "$oldcfg"
}
start_stop() {
  local p action confirm
  read -r -p '要操作嘅本地端口：' p
  valid_port "$p" && read_cfg "$p" || { echo '未找到有效管理記錄'; return; }
  echo '1. 啟動   2. 停止   3. 重新啟動'
  read -r -p '揀選：' action
  case "$action" in
    1) action=start;; 2) action=stop;; 3) action=restart;; *) echo '無效選擇'; return;;
  esac
  echo "[Dry Run] systemctl $action $(service "$p")"
  read -r -p '輸入 YES 確認：' confirm
  [[ "$confirm" == YES ]] || { echo '已取消'; return; }
  systemctl "$action" "$(service "$p")"
  systemctl --no-pager --full status "$(service "$p")" | head -n 16 || true
}
delete_one() {
  local p confirm name
  read -r -p '刪除嘅本地端口：' p
  valid_port "$p" && read_cfg "$p" || { echo '未找到有效管理記錄'; return; }
  echo "[Dry Run] 停止、停用及刪除 $(service "$p")；會斷開現有連線。"
  read -r -p "輸入 DELETE-$p 確認：" confirm
  [[ "$confirm" == "DELETE-$p" ]] || { echo '已取消'; return; }
  backup_all
  name="$(service "$p")"
  systemctl disable --now "$name" || true
  rm -f "$(cfgfile "$p")" "$(unitfile "$p")"
  systemctl daemon-reload
  echo "已刪除本管理器的 $name；備份保留。"
}
inspect() {
  local p
  read -r -p '查看本地端口 (空白顯示所有 TCP LISTEN)：' p
  if [[ -z "$p" ]]; then ss -lntup; return; fi
  valid_port "$p" || { echo '端口錯誤'; return; }
  ss -lntup "sport = :$p" || true
  if [[ -e "$(unitfile "$p")" ]]; then
    systemctl --no-pager --full status "$(service "$p")" | head -n 25 || true
  fi
}
logs() {
  local p
  read -r -p '中轉本地端口：' p
  valid_port "$p" && [[ -e "$(unitfile "$p")" ]] || { echo '找不到管理服務'; return; }
  journalctl -u "$(service "$p")" -n 60 --no-pager
}

needs_root
mkdir -p "$CFG" "$BACKUPS"
case "${1:-}" in
  --list) show_list; exit;;
  --help|-h) echo 'socat-manager (SSH only) | --list | --help'; exit;;
  '') ;;
  *) echo '未知參數'; exit 2;;
esac
while true; do
  echo
  echo '===================================='
  echo "Ben's Airport | Socat SSH Manager"
  echo '僅管理 bens-socat-* | TCP4 版本'
  echo '===================================='
  echo '1. 新增中轉（Dry Run 確認）'
  echo '2. 查看中轉列表'
  echo '3. 修改目標 IP／端口'
  echo '4. 啟動／停止／重新啟動'
  echo '5. 刪除中轉（先備份）'
  echo '6. 端口、狀態檢查'
  echo '7. 查看 systemd 日誌'
  echo '8. 即時備份設定'
  echo '0. 退出'
  read -r -p '請選擇：' choice || exit 0
  case "$choice" in
    1) create;; 2) show_list;; 3) change_target;; 4) start_stop;;
    5) delete_one;; 6) inspect;; 7) logs;; 8) backup_all;; 0) exit 0;;
    *) echo '無效選擇';;
  esac
done
MANAGER
chmod 0755 "$MANAGER_PATH"
bash -n "$MANAGER_PATH"
echo
printf 'Installed: %s\n' "$MANAGER_PATH"
echo "Socat: $(socat -V | head -n 1)"
echo 'No relay ports have been added. No existing services or firewall rules were changed.'
echo 'Next: socat-manager  (or socat-manager --list)'
