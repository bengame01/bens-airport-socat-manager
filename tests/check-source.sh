
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

echo "All syntax checks passed."
