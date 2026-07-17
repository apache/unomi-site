#!/usr/bin/env bash
# Shared helpers for preview.sh and publish.sh (Apache Unomi website).
# shellcheck disable=SC2034

# Caller must set ROOT to the repository root before sourcing, or we infer it.
if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

JEKYLL_IMAGE="${JEKYLL_IMAGE:-bretfisher/jekyll}"
JEKYLL_SERVE_IMAGE="${JEKYLL_SERVE_IMAGE:-bretfisher/jekyll-serve}"
SITE_DIR="${SITE_DIR:-target/site}"
CHECKS_FAILED=0

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

need_cmd() {
  if ! have_cmd "$1"; then
    echo "Missing required command: $1" >&2
    return 1
  fi
  return 0
}

check_pass() { echo "  [ok] $1"; }
check_fail() { echo "  [FAIL] $1" >&2; CHECKS_FAILED=1; }
check_warn() { echo "  [warn] $1" >&2; }

finish_prerequisite_checks() {
  if [[ "${CHECKS_FAILED}" -ne 0 ]]; then
    echo "" >&2
    echo "Prerequisite checks failed. Fix the items marked [FAIL] and re-run." >&2
    exit 1
  fi
  echo "==> Prerequisites OK"
  echo ""
}

check_project_layout() {
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

  if [[ -f "${ROOT}/Gemfile" ]]; then
    check_pass "Gemfile present"
  else
    check_fail "Gemfile missing — Docker Jekyll build needs it"
  fi
}

check_docker_build_env() {
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

  if mkdir -p "${ROOT}/target" 2>/dev/null && [[ -w "${ROOT}/target" ]]; then
    check_pass "target/ is writable"
  else
    check_fail "cannot create/write ${ROOT}/target"
  fi
}

check_jekyll_config() {
  local dest url
  dest="$(grep -E '^destination:' "${ROOT}/_config.yml" 2>/dev/null | awk '{print $2}' | tr -d '"' || true)"
  url="$(grep -E '^url:' "${ROOT}/_config.yml" 2>/dev/null | awk '{print $2}' | tr -d '"' || true)"

  if [[ "${dest}" == "target/site" ]]; then
    check_pass "_config.yml destination is target/site"
  elif [[ -n "${dest}" ]]; then
    check_fail "_config.yml destination is '${dest}' (expected target/site)"
  else
    check_warn "could not parse destination from _config.yml"
  fi

  if [[ "${url}" == "https://unomi.apache.org" ]]; then
    check_pass "_config.yml url is https://unomi.apache.org"
  elif [[ -n "${url}" ]]; then
    check_warn "_config.yml url is '${url}' (expected https://unomi.apache.org for production)"
  fi
}

build_site() {
  echo "==> Building site with Docker (${JEKYLL_IMAGE})"
  mkdir -p "${ROOT}/target"
  # The repo Gemfile is mounted into the image, so Bundler must install gems
  # into the project before jekyll build. A bare `jekyll build` fails with
  # GemNotFound when Gemfile.lock exists locally.
  docker run --rm \
    --volume="${ROOT}:/site" \
    -w /site \
    --entrypoint bash \
    "${JEKYLL_IMAGE}" \
    -lc 'bundle install && bundle exec jekyll build'

  validate_built_site
  echo "==> Build OK → ${SITE_DIR}"
}

# Strong checks on target/site before any deploy/publish.
validate_built_site() {
  local site_path="${ROOT}/${SITE_DIR}"
  local file_count html_count
  local required=(
    "index.html"
    "download.html"
    "documentation.html"
    "get-started.html"
    "sitemap.xml"
    "robots.txt"
    "assets"
    "blog"
  )

  echo "==> Validating built site (${SITE_DIR})"

  if [[ ! -d "${site_path}" ]]; then
    echo "Validation failed: ${SITE_DIR} directory missing" >&2
    exit 1
  fi

  if [[ -z "$(ls -A "${site_path}" 2>/dev/null || true)" ]]; then
    echo "Validation failed: ${SITE_DIR} is empty" >&2
    exit 1
  fi

  local missing=0
  local item
  for item in "${required[@]}"; do
    if [[ ! -e "${site_path}/${item}" ]]; then
      echo "  [FAIL] missing required path: ${SITE_DIR}/${item}" >&2
      missing=1
    else
      echo "  [ok] ${SITE_DIR}/${item}"
    fi
  done
  if [[ "${missing}" -ne 0 ]]; then
    echo "Validation failed: required site paths missing" >&2
    exit 1
  fi

  if ! grep -qi 'Apache Unomi' "${site_path}/index.html"; then
    echo "Validation failed: index.html does not look like the Unomi site" >&2
    exit 1
  fi
  echo "  [ok] index.html contains 'Apache Unomi'"

  # Unrendered Liquid is a strong signal the build was wrong.
  if grep -R -E -l '\{\{|\{\%' \
      --include='*.html' --include='*.xml' --include='*.txt' \
      "${site_path}" 2>/dev/null \
      | grep -v '/assets/' \
      | head -5 \
      | grep -q .; then
    echo "  [warn] possible unrendered Liquid tags under ${SITE_DIR} (spot-check output)" >&2
    grep -R -n -E '\{\{|\{\%' \
      --include='*.html' --include='*.xml' --include='*.txt' \
      "${site_path}" 2>/dev/null \
      | grep -v '/assets/' \
      | head -10 >&2 || true
  else
    echo "  [ok] no obvious unrendered Liquid tags in HTML/XML/TXT"
  fi

  file_count="$(find "${site_path}" -type f | wc -l | tr -d ' ')"
  html_count="$(find "${site_path}" -type f -name '*.html' | wc -l | tr -d ' ')"
  if [[ "${file_count}" -lt 50 ]]; then
    echo "Validation failed: only ${file_count} files under ${SITE_DIR} (expected ≥ 50)" >&2
    exit 1
  fi
  if [[ "${html_count}" -lt 20 ]]; then
    echo "Validation failed: only ${html_count} HTML files (expected ≥ 20)" >&2
    exit 1
  fi
  echo "  [ok] ${file_count} files (${html_count} HTML)"

  # Refuse to publish a tree that still looks like a Jekyll source tree.
  if [[ -d "${site_path}/_layouts" ]] || [[ -d "${site_path}/_includes" ]]; then
    echo "Validation failed: ${SITE_DIR} contains Jekyll source dirs (_layouts/_includes)" >&2
    exit 1
  fi
  echo "  [ok] output does not look like Jekyll source"
  echo "==> Site validation OK"
}
