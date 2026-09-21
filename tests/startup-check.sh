#!/usr/bin/env bash
set -euo pipefail

arcmac_test_emacs=${1:-emacs}
arcmac_test_source=${2:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}
arcmac_test_root=$(mktemp -d)
trap 'rm -rf -- "$arcmac_test_root"' EXIT

export ARCMAC_STARTUP_ROOT="$arcmac_test_root"
export ARCMAC_STARTUP_SOURCE="$arcmac_test_source"
export XDG_CONFIG_HOME="$arcmac_test_root/config"
export XDG_STATE_HOME="$arcmac_test_root/state"
export XDG_CACHE_HOME="$arcmac_test_root/cache"
export XDG_DATA_HOME="$arcmac_test_root/data"
export XDG_RUNTIME_DIR="$arcmac_test_root/run"
# Nix builders have no desktop locale; Hunspell's dictionary discovery
# still needs a default before the config enables English + Swedish.
export DICTIONARY=en_US
mkdir -p "$XDG_CONFIG_HOME/arcmac" "$XDG_RUNTIME_DIR"
cp "$arcmac_test_source/init.el" "$arcmac_test_source/early-init.el" "$XDG_CONFIG_HOME/arcmac/"
chmod u+w "$XDG_CONFIG_HOME/arcmac/early-init.el"
printf '%s\n' ';;; -*- lexical-binding: t; -*-' \
  '(setq user-full-name "Startup Test" user-mail-address "startup@example.invalid")' \
  '(setq nd/mail-accounts (quote (("primary" "primary@example.invalid" "p") ("work" "alex+work@example.org" "w"))))' \
  > "$XDG_CONFIG_HOME/arcmac-local.el"

# Install the test harness after early-init, before the real init runs.
# The tests themselves run at the end of emacs-startup-hook.
cat >> "$XDG_CONFIG_HOME/arcmac/early-init.el" <<'ELISP'
(load (expand-file-name "tests/startup-test.el" (getenv "ARCMAC_STARTUP_SOURCE")) nil t)
ELISP

# A unique absolute socket path cannot connect to the user's daemon.
# Timeout also makes early-init errors and startup hangs fail the check.
timeout 90 "$arcmac_test_emacs" --init-directory "$XDG_CONFIG_HOME/arcmac" \
  --fg-daemon="$arcmac_test_root/server"
