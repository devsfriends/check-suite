#!/usr/bin/env bash
set -euo pipefail

# scripts/check-run.sh
# Helper to create/update/complete GitHub Check Runs using an installation token.
# NOTE: This file is created in the workspace but NOT committed per your request.

usage(){
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  create --name NAME --sha SHA [--repo owner/repo]
  update --id CHECK_RUN_ID --status STATUS [--repo owner/repo]
  complete --id CHECK_RUN_ID --conclusion CONCLUSION --summary "text" [--repo owner/repo]

Environment variables:
  GITHUB_TOKEN or GH_TOKEN or INSTALL_TOKEN  # required (installation token from GitHub App)

Examples:
  # First, generate a token:
  # ./scripts/create-installation-token.sh --app-id <<APP_ID>> --installation-id <<INSTALLATION_ID>> --private-key /path/to/your-private-key.pem
  
  # Then export it:
  export INSTALL_TOKEN=ghu_...
  export REPO=devsfriends/check-suite
  SHA=\$(git rev-parse --verify HEAD)

  # create a new check run (prints check_run id)
  ./scripts/check-run.sh create --name "Local Test" --sha \$SHA --repo \$REPO

  # mark in progress
  ./scripts/check-run.sh update --id 123456 --status in_progress --repo \$REPO

  # complete with success
  ./scripts/check-run.sh complete --id 123456 --conclusion success --summary "All good" --repo \$REPO
EOF
}

# get token - try INSTALL_TOKEN first, fallback to GITHUB_TOKEN
TOKEN="${INSTALL_TOKEN:-${GITHUB_TOKEN:-${GH_TOKEN:-}}}"
if [[ -z "$TOKEN" ]]; then
  echo "Error: set INSTALL_TOKEN, GITHUB_TOKEN or GH_TOKEN"
  exit 2
fi

API_BASE="https://api.github.com"

# default repo
DEFAULT_REPO="${REPO:-}" # can be set as env REPO=owner/repo

# helper: parse repo argument or env
get_repo(){
  if [[ -n "$repo_arg" ]]; then
    echo "$repo_arg"
  elif [[ -n "$DEFAULT_REPO" ]]; then
    echo "$DEFAULT_REPO"
  else
    # try from git remote
    if git rev-parse --git-dir > /dev/null 2>&1; then
      url=$(git config --get remote.origin.url || true)
      if [[ "$url" =~ github.com[:/]+([^/]+)/([^.]+)(.git)? ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return
      fi
    fi
    echo ""  # empty
  fi
}

create_check_run(){
  local name="$1"; shift
  local sha="$1"; shift
  local repo; repo=$(get_repo)
  if [[ -z "$repo" ]]; then
    echo "Error: repo not specified. Use --repo owner/repo or set REPO env."
    exit 2
  fi

  read -r owner repo_name <<<"$(echo $repo | awk -F/ '{print $1" "$2}')"

  payload=$(cat <<JSON
{"name":"$name","head_sha":"$sha","status":"queued","started_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
JSON
)

  resp=$(curl -sS -X POST "$API_BASE/repos/$owner/$repo_name/check-runs" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload")

  # print response and try to fetch id
  echo "$resp" | jq . || echo "$resp"
  id=$(echo "$resp" | jq -r '.id // ""')
  if [[ -n "$id" ]]; then
    echo "CHECK_RUN_ID=$id"
  else
    echo "Failed to create check run"
    return 1
  fi
}

update_check_run(){
  local id="$1"; shift
  local status="$1"; shift
  local repo; repo=$(get_repo)
  if [[ -z "$repo" ]]; then
    echo "Error: repo not specified. Use --repo owner/repo or set REPO env."
    exit 2
  fi
  read -r owner repo_name <<<"$(echo $repo | awk -F/ '{print $1" "$2}')"

  payload=$(cat <<JSON
{"status":"$status"}
JSON
)

  resp=$(curl -sS -X PATCH "$API_BASE/repos/$owner/$repo_name/check-runs/$id" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo "$resp" | jq . || echo "$resp"
}

complete_check_run(){
  local id="$1"; shift
  local conclusion="$1"; shift
  local summary_text="$1"; shift
  local repo; repo=$(get_repo)
  if [[ -z "$repo" ]]; then
    echo "Error: repo not specified. Use --repo owner/repo or set REPO env."
    exit 2
  fi
  read -r owner repo_name <<<"$(echo $repo | awk -F/ '{print $1" "$2}')"

  payload=$(cat <<JSON
{"status":"completed","conclusion":"$conclusion","completed_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","output": {"title":"TypoApp application approved PR","summary":"$summary_text"}}
JSON
)

  resp=$(curl -sS -X PATCH "$API_BASE/repos/$owner/$repo_name/check-runs/$id" \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload")

  echo "$resp" | jq . || echo "$resp"
}

# --- parse args ---
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

cmd="$1"; shift || true
repo_arg=""

# simple arg parsing
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo_arg="$2"; shift 2;;
    --name)
      arg_name="$2"; shift 2;;
    --sha)
      arg_sha="$2"; shift 2;;
    --id)
      arg_id="$2"; shift 2;;
    --status)
      arg_status="$2"; shift 2;;
    --conclusion)
      arg_conclusion="$2"; shift 2;;
    --summary)
      arg_summary="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

case "$cmd" in
  create)
    if [[ -z "${arg_name:-}" || -z "${arg_sha:-}" ]]; then
      echo "create requires --name and --sha"; exit 1
    fi
    create_check_run "$arg_name" "$arg_sha" ;;
  update)
    if [[ -z "${arg_id:-}" || -z "${arg_status:-}" ]]; then
      echo "update requires --id and --status"; exit 1
    fi
    update_check_run "$arg_id" "$arg_status" ;;
  complete)
    if [[ -z "${arg_id:-}" || -z "${arg_conclusion:-}" ]]; then
      echo "complete requires --id and --conclusion"; exit 1
    fi
    complete_check_run "$arg_id" "$arg_conclusion" "${arg_summary:-}" ;;
  *)
    echo "Unknown command: $cmd"; usage; exit 1;;
esac
