#!/usr/bin/env bash
set -euo pipefail

# scripts/create-installation-token.sh
# Template helper to create a GitHub App JWT and exchange it for an installation token.
# This file is created in the workspace but NOT committed per your request.

usage(){
  cat <<EOF
Usage: $0 --app-id APP_ID --installation-id INSTALLATION_ID --private-key /path/to/private-key.pem

Generates a JWT for the GitHub App and requests an installation access token.
Requires: openssl, curl, jq

Example:
  ./scripts/create-installation-token.sh --app-id 12345 --installation-id 67890 --private-key /tmp/my-app.pem

Outputs an export command you can `eval` to set INSTALL_TOKEN.
EOF
}

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required"
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required"
  exit 2
fi

APP_ID=""
INSTALLATION_ID=""
PRIVATE_KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id) APP_ID="$2"; shift 2;;
    --installation-id) INSTALLATION_ID="$2"; shift 2;;
    --private-key) PRIVATE_KEY="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$APP_ID" || -z "$INSTALLATION_ID" || -z "$PRIVATE_KEY" ]]; then
  usage
  exit 1
fi
if [[ ! -f "$PRIVATE_KEY" ]]; then
  echo "Private key file not found: $PRIVATE_KEY"
  exit 1
fi

# build JWT
NOW=$(date +%s)
IAT=$((NOW - 60))
EXP=$((NOW + 600))

header='{"alg":"RS256","typ":"JWT"}'
payload="{\"iat\":$IAT,\"exp\":$EXP,\"iss\":$APP_ID}"

b64url(){
  base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n'
}

header_b64=$(printf '%s' "$header" | b64url)
payload_b64=$(printf '%s' "$payload" | b64url)
unsigned="${header_b64}.${payload_b64}"

# Create signature
sig=$(printf '%s' "$unsigned" | openssl dgst -sha256 -sign "$PRIVATE_KEY" | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')
JWT="${unsigned}.${sig}"

# request installation token
resp=$(curl -sS -X POST "https://api.github.com/app/installations/$INSTALLATION_ID/access_tokens" \
  -H "Authorization: Bearer $JWT" \
  -H "Accept: application/vnd.github+json")

token=$(echo "$resp" | jq -r '.token // ""')
expires_at=$(echo "$resp" | jq -r '.expires_at // ""')

if [[ -z "$token" ]]; then
  echo "Failed to get installation token. Response:" >&2
  echo "$resp" >&2
  exit 1
fi

cat <<EOF
# Installation token (valid until: $expires_at)
export INSTALL_TOKEN="$token"
# Use with the other helper, e.g.:
# INSTALL_TOKEN="$token" ./scripts/check-run.sh create --name "Local Test" --sha <SHA> --repo owner/repo
EOF
