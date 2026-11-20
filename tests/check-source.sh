
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

echo "Ben's Airport Socat Manager - Source Check"

for file in \
  socat-manager \
  relay2-socat-ssh-installer.sh
do
  if [[ ! -f "$file" ]]; then
    echo "FAIL: Missing $file"
    exit 1
  fi

  bash -n "$file"
  echo "PASS: $file"
done

# bash -n alone can overlook a truncated heredoc. Check its terminator,
# then validate the embedded manager independently and compare the sources.
installer=relay2-socat-ssh-installer.sh
[[ $(grep -cx 'MANAGER' "$installer") -eq 1 ]] || {
  echo 'FAIL: Missing or duplicate MANAGER terminator'
  exit 1
}
embedded=$(mktemp)
trap 'rm -f "$embedded"' EXIT
awk '/^cat > "\$MANAGER_PATH" <<\x27MANAGER\x27$/ { copying=1; next }
     copying && /^MANAGER$/ { exit }
     copying { print }' "$installer" > "$embedded"
test -s "$embedded"
bash -n "$embedded"
diff -u socat-manager "$embedded"
grep -Fxq 'bash -n "$MANAGER_PATH"' "$installer"

echo "All syntax and source integrity checks passed."
