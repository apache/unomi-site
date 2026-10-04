#!/usr/bin/env bash
# Build the Apache Unomi website and publish a Netlify staging preview.
#
# This is for personal/community review only — production uses ./publish.sh
# (Maven scm-publish to https://unomi.apache.org/).
#
# Usage:
#   ./preview.sh                 # Docker build + Netlify draft deploy (unique URL)
#   ./preview.sh --prod          # Same build, deploy to Netlify site URL (cleaner share link)
#                                #   e.g. https://unomi-preview.netlify.app — NOT unomi.apache.org
#   ./preview.sh --local         # Docker build + serve at http://localhost:4000
#   ./preview.sh --build-only    # Docker build only (output: target/site)
#   ./preview.sh --check-only    # Prerequisite checks only (no build/deploy)
#   ./preview.sh --open          # After deploy, open the preview URL (macOS)
#
# Apache production (https://unomi.apache.org/) uses ./publish.sh — not this script.
# Optional environment:
#   NETLIFY_AUTH_TOKEN   Personal access token (or run: npx netlify-cli login)
#   NETLIFY_SITE_ID      Existing site id (skips interactive link)
#   NETLIFY_SITE_NAME    Site name when creating/linking (default: unomi-preview)
#   JEKYLL_IMAGE         Docker image (default: bretfisher/jekyll)
#   JEKYLL_SERVE_IMAGE   Serve image (default: bretfisher/jekyll-serve)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/site-common.sh
source "${ROOT}/scripts/lib/site-common.sh"
cd "$ROOT"

MODE="draft"          # draft | netlify-prod | local | build-only | check-only
OPEN_URL=0
NETLIFY_SITE_NAME="${NETLIFY_SITE_NAME:-unomi-preview}"

usage() {
  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod) MODE="netlify-prod"; shift ;;
    --local) MODE="local"; shift ;;
    --build-only) MODE="build-only"; shift ;;
    --check-only) MODE="check-only"; shift ;;
    --open) OPEN_URL=1; shift ;;
    -h|--help) usage 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
  esac
done

check_prerequisites() {
  echo "==> Prerequisite checks (mode: ${MODE})"
  CHECKS_FAILED=0

  check_project_layout
  check_docker_build_env

  if [[ -f "${ROOT}/netlify.toml" ]]; then
    check_pass "netlify.toml present"
  else
    check_warn "netlify.toml missing (deploy still works with --dir=${SITE_DIR})"
  fi

  case "${MODE}" in
    draft|netlify-prod|check-only)
      if have_cmd netlify; then
        check_pass "netlify CLI found ($(netlify --version 2>/dev/null | head -1 || echo ok))"
      elif have_cmd npx; then
        check_pass "npx found (will use: npx netlify-cli)"
        if have_cmd node; then
          check_pass "node found ($(node --version 2>/dev/null))"
        else
          check_warn "node not found — npx may still work depending on your Node install"
        fi
      else
        check_fail "neither 'netlify' nor 'npx' found — install Netlify CLI or Node.js (npx)"
      fi

      if [[ -n "${NETLIFY_AUTH_TOKEN:-}" ]]; then
        check_pass "NETLIFY_AUTH_TOKEN is set"
      elif [[ -f "${HOME}/.netlify/config.json" ]] || [[ -d "${HOME}/.config/netlify" ]]; then
        check_pass "Netlify CLI config present (will verify auth at deploy time)"
      else
        check_warn "no NETLIFY_AUTH_TOKEN / Netlify config yet — script will run 'netlify login' if needed"
      fi

      if [[ -n "${NETLIFY_SITE_ID:-}" ]]; then
        check_pass "NETLIFY_SITE_ID is set"
      elif [[ -f "${ROOT}/.netlify/state.json" ]]; then
        check_pass "site already linked (.netlify/state.json)"
      else
        check_warn "site not linked yet — will create/link '${NETLIFY_SITE_NAME}'"
      fi

      if have_cmd curl; then
        if curl -fsS --connect-timeout 5 -o /dev/null https://api.netlify.com/api/v1/ 2>/dev/null \
          || curl -fsS --connect-timeout 5 -o /dev/null https://www.netlify.com/ 2>/dev/null; then
          check_pass "network reachability to Netlify"
        else
          check_warn "could not reach Netlify APIs — deploy may fail offline"
        fi
      fi
      ;;
    local)
      if have_cmd lsof && lsof -iTCP:4000 -sTCP:LISTEN >/dev/null 2>&1; then
        check_warn "port 4000 is already in use — jekyll-serve may fail to bind"
      else
        check_pass "port 4000 appears free"
      fi
      ;;
    build-only)
      ;;
  esac

  if [[ "${OPEN_URL}" -eq 1 ]]; then
    if have_cmd open; then
      check_pass "open found (will open preview URL)"
    else
      check_warn "'open' not found — --open will be ignored"
    fi
  fi

  finish_prerequisite_checks
}

netlify_cli() {
  if have_cmd netlify; then
    netlify "$@"
  else
    npx --yes netlify-cli "$@"
  fi
}

ensure_netlify_auth() {
  if [[ -n "${NETLIFY_AUTH_TOKEN:-}" ]]; then
    return 0
  fi
  if netlify_cli status >/dev/null 2>&1; then
    return 0
  fi
  echo "==> Netlify auth required (browser login)"
  netlify_cli login
}

link_or_create_site() {
  # Manual static deploys only — never run `netlify init` (that asks for GitHub
  # webhooks/deploy keys, which we do not need and should not grant for ASF repos).
  if [[ -n "${NETLIFY_SITE_ID:-}" ]]; then
    echo "==> Linking by NETLIFY_SITE_ID=${NETLIFY_SITE_ID}"
    netlify_cli link --id "${NETLIFY_SITE_ID}"
    return 0
  fi
  if [[ -f .netlify/state.json ]]; then
    echo "==> Using existing Netlify link (.netlify/state.json)"
    return 0
  fi

  echo "==> Linking/creating Netlify site '${NETLIFY_SITE_NAME}'"
  echo "    (static dir deploy only — no GitHub continuous-deploy setup)"

  local site_id=""
  if netlify_cli sites:list --json 2>/dev/null | grep -q "\"name\":\"${NETLIFY_SITE_NAME}\""; then
    site_id="$(netlify_cli sites:list --json 2>/dev/null \
      | tr ',' '\n' \
      | grep -A2 "\"name\":\"${NETLIFY_SITE_NAME}\"" \
      | grep '"id"' \
      | head -1 \
      | sed -E 's/.*"id":"([^"]+)".*/\1/' || true)"
    if [[ -n "${site_id}" ]]; then
      netlify_cli link --id "${site_id}"
      return 0
    fi
    netlify_cli link --name "${NETLIFY_SITE_NAME}"
    return 0
  fi

  local create_log
  create_log="$(mktemp)"
  if ! netlify_cli sites:create --name "${NETLIFY_SITE_NAME}" --disable-linking 2>&1 | tee "${create_log}"; then
    echo "Failed to create Netlify site '${NETLIFY_SITE_NAME}'" >&2
    echo "Create it in the Netlify UI, then re-run with:" >&2
    echo "  export NETLIFY_SITE_ID=<project-id>" >&2
    rm -f "${create_log}"
    exit 1
  fi

  site_id="$(grep -Eo 'Project ID:[[:space:]]*[0-9a-f-]+' "${create_log}" \
    | awk '{print $3}' \
    | head -1 || true)"
  if [[ -z "${site_id}" ]]; then
    site_id="$(grep -Eo '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "${create_log}" | head -1 || true)"
  fi
  rm -f "${create_log}"

  if [[ -n "${site_id}" ]]; then
    netlify_cli link --id "${site_id}"
  else
    netlify_cli link --name "${NETLIFY_SITE_NAME}"
  fi

  if [[ ! -f .netlify/state.json ]]; then
    echo "Site link failed. Set NETLIFY_SITE_ID and re-run (do not use netlify init)." >&2
    exit 1
  fi
}

deploy_netlify() {
  ensure_netlify_auth
  link_or_create_site

  local args=(deploy --dir="${SITE_DIR}" --message "unomi-site preview $(date -u +%Y-%m-%dT%H:%MZ)")
  if [[ "${MODE}" == "netlify-prod" ]]; then
    args+=(--prod)
    echo "==> Deploying to Netlify site production URL (cleaner share link)"
    echo "    This is NOT https://unomi.apache.org/ — use ./publish.sh for ASF production"
  else
    echo "==> Deploying Netlify draft preview (unique URL)"
  fi

  local log
  log="$(mktemp)"
  if ! netlify_cli "${args[@]}" 2>&1 | tee "${log}"; then
    echo "Netlify deploy failed" >&2
    rm -f "${log}"
    exit 1
  fi

  local url=""
  # Prefer the labelled URL for the mode; Netlify prints angle-bracketed links.
  if [[ "${MODE}" == "netlify-prod" ]]; then
    url="$(grep -E 'Production URL:' "${log}" \
      | grep -Eo 'https://[^ >]+' \
      | head -1 \
      | tr -d '<>' || true)"
  else
    url="$(grep -E 'Draft URL:' "${log}" \
      | grep -Eo 'https://[^ >]+' \
      | head -1 \
      | tr -d '<>' || true)"
  fi
  if [[ -z "${url}" ]]; then
    # Fallback: first *.netlify.app that is NOT a unique deploy subdomain (has --)
    url="$(grep -Eo 'https://[^ >]+\.netlify\.app' "${log}" \
      | tr -d '<>' \
      | grep -v -- '--' \
      | head -1 || true)"
  fi
  if [[ -z "${url}" ]]; then
    url="$(grep -Eo 'https://[^ >]+\.netlify\.app' "${log}" | tr -d '<>' | tail -1 || true)"
  fi
  rm -f "${log}"

  if [[ -n "${url}" ]]; then
    echo ""
    if [[ "${MODE}" == "netlify-prod" ]]; then
      echo "==> Share URL: ${url}"
    else
      echo "==> Preview URL: ${url}"
      echo "    Tip: ./preview.sh --prod for the stable https://${NETLIFY_SITE_NAME}.netlify.app link"
    fi
    if [[ "${OPEN_URL}" -eq 1 ]] && have_cmd open; then
      open "${url}"
    fi
  else
    echo "==> Deploy finished (check netlify output above for the URL)"
  fi
}

serve_local() {
  echo "==> Serving with Docker (${JEKYLL_SERVE_IMAGE}) at http://localhost:4000/"
  echo "    Ctrl+C to stop"
  docker run --rm \
    --volume="${ROOT}:/site" \
    -p 4000:4000 \
    -w /site \
    --entrypoint bash \
    "${JEKYLL_SERVE_IMAGE}" \
    -lc 'bundle install && bundle exec jekyll serve --host 0.0.0.0 --port 4000'
}

check_prerequisites

if [[ "${MODE}" == "check-only" ]]; then
  echo "==> Done (check only)"
  exit 0
fi

build_site

case "${MODE}" in
  build-only)
    echo "==> Done (build only)"
    ;;
  local)
    serve_local
    ;;
  draft|netlify-prod)
    deploy_netlify
    ;;
  *)
    echo "Internal error: unknown mode ${MODE}" >&2
    exit 1
    ;;
esac
