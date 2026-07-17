#!/usr/bin/env bash
# Build the Apache Unomi website and publish a Netlify staging preview.
#
# This mirrors the earlier UNOMI-932 staging flow (unomi-v3-site.netlify.app).
# It is for personal/community review only — production remains:
#   mvn install scm-publish:publish-scm ...
#
# Usage:
#   ./preview.sh                 # Docker build + Netlify draft deploy (unique URL)
#   ./preview.sh --prod          # Docker build + deploy to the linked site URL
#   ./preview.sh --local         # Docker build + serve at http://localhost:4000
#   ./preview.sh --build-only    # Docker build only (output: target/site)
#   ./preview.sh --check-only  # Prerequisite checks only (no build/deploy)
#   ./preview.sh --open        # After deploy, open the preview URL (macOS)
#
# Optional environment:
#   NETLIFY_AUTH_TOKEN   Personal access token (or run: npx netlify-cli login)
#   NETLIFY_SITE_ID      Existing site id (skips interactive link)
#   NETLIFY_SITE_NAME    Site name when creating/linking (default: unomi-v3-site)
#   JEKYLL_IMAGE         Docker image (default: bretfisher/jekyll)
#   JEKYLL_SERVE_IMAGE   Serve image (default: bretfisher/jekyll-serve)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

MODE="draft"          # draft | prod | local | build-only | check-only
OPEN_URL=0
JEKYLL_IMAGE="${JEKYLL_IMAGE:-bretfisher/jekyll}"
JEKYLL_SERVE_IMAGE="${JEKYLL_SERVE_IMAGE:-bretfisher/jekyll-serve}"
NETLIFY_SITE_NAME="${NETLIFY_SITE_NAME:-unomi-v3-site}"
SITE_DIR="target/site"

usage() {
  sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prod) MODE="prod"; shift ;;
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

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    return 1
  fi
  return 0
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

check_pass() { echo "  [ok] $1"; }
check_fail() { echo "  [FAIL] $1" >&2; CHECKS_FAILED=1; }
check_warn() { echo "  [warn] $1" >&2; }

CHECKS_FAILED=0

check_prerequisites() {
  echo "==> Prerequisite checks (mode: ${MODE})"
  CHECKS_FAILED=0

  # --- Project layout ---
  if [[ -f "${ROOT}/_config.yml" ]]; then
    check_pass "_config.yml present"
  else
    check_fail "_config.yml missing — run from the unomi-site repo root"
  fi

  if [[ -d "${ROOT}/src/main/webapp" ]]; then
    check_pass "src/main/webapp present"
  else
    check_fail "src/main/webapp missing — unexpected project layout"
  fi

  if [[ -f "${ROOT}/netlify.toml" ]]; then
    check_pass "netlify.toml present"
  else
    check_warn "netlify.toml missing (deploy still works with --dir=${SITE_DIR})"
  fi

  # --- Docker (required for all modes that build) ---
  if have_cmd docker; then
    check_pass "docker found ($(command -v docker))"
    if docker info >/dev/null 2>&1; then
      check_pass "Docker daemon is running"
    else
      check_fail "Docker daemon is not running — start Docker Desktop / dockerd"
    fi
  else
    check_fail "docker not found — install Docker (required to build with ${JEKYLL_IMAGE})"
  fi

  # Writable output dir
  if mkdir -p "${ROOT}/target" 2>/dev/null && [[ -w "${ROOT}/target" ]]; then
    check_pass "target/ is writable"
  else
    check_fail "cannot create/write ${ROOT}/target"
  fi

  # --- Mode-specific ---
  case "${MODE}" in
    draft|prod|check-only)
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

  if [[ "${CHECKS_FAILED}" -ne 0 ]]; then
    echo "" >&2
    echo "Prerequisite checks failed. Fix the items marked [FAIL] and re-run." >&2
    exit 1
  fi
  echo "==> Prerequisites OK"
  echo ""
}

build_site() {
  echo "==> Building site with Docker (${JEKYLL_IMAGE})"
  mkdir -p target
  docker run --rm \
    --volume="${ROOT}:/site" \
    -w /site \
    "${JEKYLL_IMAGE}" \
    build

  if [[ ! -d "${SITE_DIR}" ]] || [[ -z "$(ls -A "${SITE_DIR}" 2>/dev/null || true)" ]]; then
    echo "Build failed: ${SITE_DIR} is missing or empty" >&2
    exit 1
  fi
  echo "==> Build OK → ${SITE_DIR}"
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
  if [[ -n "${NETLIFY_SITE_ID:-}" ]]; then
    echo "==> Using NETLIFY_SITE_ID=${NETLIFY_SITE_ID}"
    return 0
  fi
  if [[ -f .netlify/state.json ]]; then
    echo "==> Using existing Netlify link (.netlify/state.json)"
    return 0
  fi

  echo "==> Linking/creating Netlify site '${NETLIFY_SITE_NAME}'"
  if netlify_cli sites:list --json 2>/dev/null | grep -q "\"name\":\"${NETLIFY_SITE_NAME}\""; then
    netlify_cli link --name "${NETLIFY_SITE_NAME}"
  else
    netlify_cli sites:create --name "${NETLIFY_SITE_NAME}" --disable-linking || true
    netlify_cli link --name "${NETLIFY_SITE_NAME}" || netlify_cli init
  fi
}

deploy_netlify() {
  ensure_netlify_auth
  link_or_create_site

  local args=(deploy --dir="${SITE_DIR}" --message "unomi-site preview $(date -u +%Y-%m-%dT%H:%MZ)")
  if [[ "${MODE}" == "prod" ]]; then
    args+=(--prod)
    echo "==> Deploying to Netlify production URL for linked site"
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

  local url
  url="$(grep -Eo 'https://[^ ]+\.netlify\.app/?[^ ]*' "${log}" | tail -1 || true)"
  rm -f "${log}"

  if [[ -n "${url}" ]]; then
    echo ""
    echo "==> Preview URL: ${url}"
    if [[ "${OPEN_URL}" -eq 1 ]] && command -v open >/dev/null 2>&1; then
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
    "${JEKYLL_SERVE_IMAGE}"
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
  draft|prod)
    deploy_netlify
    ;;
  *)
    echo "Internal error: unknown mode ${MODE}" >&2
    exit 1
    ;;
esac
