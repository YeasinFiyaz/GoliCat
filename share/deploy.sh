#!/usr/bin/env bash
# Runs wrangler with GoliCat's OWN login (yeasinfiyaz@gmail.com Cloudflare account),
# stored in share/.wrangler-home, so the global NRF wrangler login is never touched.
set -e
cd "$(dirname "$0")"
export XDG_CONFIG_HOME="$PWD/.wrangler-home"
# A stale OAuth token makes `deploy` fail with "non-interactive... CLOUDFLARE_API_TOKEN";
# `whoami` refreshes it first.
[ "${1:-}" = "deploy" ] && npx wrangler whoami >/dev/null 2>&1 || true
exec npx wrangler "$@"
