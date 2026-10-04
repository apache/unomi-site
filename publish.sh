#!/usr/bin/env bash
# Build the Apache Unomi website and publish to production (https://unomi.apache.org/).
#
# Uses Maven scm-publish to SVN (see pom.xml). This is NOT Netlify — use ./preview.sh
# for personal/community staging previews.
#
# Usage:
#   ./publish.sh --username ASF_ID --password 'SECRET'
#   ./publish.sh -u ASF_ID -p 'SECRET'
#   ./publish.sh --username ASF_ID          # prompts for password (no echo)
#   ./publish.sh --check-only -u ASF_ID -p 'SECRET'
#   ./publish.sh --dry-run -u ASF_ID -p 'SECRET'
#   ./publish.sh --skip-build -u ASF_ID -p 'SECRET'   # reuse existing target/site
#
# Credentials may also come from the environment (never commit these):
#   ASF_USERNAME / ASF_PASSWORD
#   or APACHE_USERNAME / APACHE_PASSWORD
#
# Optional:
#   JEKYLL_IMAGE   Docker image (default: bretfisher/jekyll)
#   --yes          Skip the interactive confirmation prompt
#
# Important: do not run Maven clean — it would wipe previously published trees
# that scm-publish intentionally preserves under docs/, manual/, etc.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/site-common.sh
source "${ROOT}/scripts/lib/site-common.sh"
cd "$ROOT"

ASF_USERNAME="${ASF_USERNAME:-${APACHE_USERNAME:-}}"
ASF_PASSWORD="${ASF_PASSWORD:-${APACHE_PASSWORD:-}}"
MODE="publish"          # publish | check-only | dry-run
SKIP_BUILD=0
ASSUME_YES=0
SVN_URL="https://svn.apache.org/repos/asf/unomi/website/"
PROD_URL="https://unomi.apache.org/"

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--username)
      ASF_USERNAME="${2:-}"
      shift 2
      ;;
    -p|--password)
      ASF_PASSWORD="${2:-}"
      shift 2
      ;;
    --check-only) MODE="check-only"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    -h|--help) usage 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage 1
      ;;
  esac
done

prompt_password_if_needed() {
  if [[ -n "${ASF_PASSWORD}" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "Password required: pass --password, or set ASF_PASSWORD (stdin is not a TTY)" >&2
    exit 1
  fi
  echo -n "ASF LDAP password for '${ASF_USERNAME}': " >&2
  # shellcheck disable=SC2162
  read -s ASF_PASSWORD
  echo "" >&2
}

check_pom_publish_config() {
  if [[ ! -f "${ROOT}/pom.xml" ]]; then
    check_fail "pom.xml missing"
    return
  fi
  check_pass "pom.xml present"

  if grep -q 'maven-scm-publish-plugin' "${ROOT}/pom.xml"; then
    check_pass "maven-scm-publish-plugin configured"
  else
    check_fail "pom.xml missing maven-scm-publish-plugin"
  fi

  if grep -q 'scm:svn:https://svn.apache.org/repos/asf/unomi/website/' "${ROOT}/pom.xml"; then
    check_pass "pubScmUrl points at ${SVN_URL}"
  else
    check_fail "pom.xml pubScmUrl is not the Unomi website SVN URL"
  fi

  if grep -q 'project.build.directory}/site' "${ROOT}/pom.xml"; then
    check_pass "scm-publish content is target/site"
  else
    check_warn "could not confirm scm-publish <content> is target/site"
  fi

  if grep -q 'ignorePathsToDelete' "${ROOT}/pom.xml"; then
    check_pass "ignorePathsToDelete present (docs/manual/api trees preserved)"
  else
    check_warn "ignorePathsToDelete missing — publish may delete docs/manual trees"
  fi
}

check_maven_java() {
  if have_cmd mvn; then
    check_pass "mvn found ($(mvn -v 2>/dev/null | head -1 || echo ok))"
  else
    check_fail "mvn not found — install Apache Maven"
  fi

  if have_cmd java; then
    check_pass "java found ($(java -version 2>&1 | head -1 || echo ok))"
  else
    check_fail "java not found — install a JDK for Maven"
  fi

  if [[ -n "${JAVA_HOME:-}" ]]; then
    if [[ -x "${JAVA_HOME}/bin/java" ]]; then
      check_pass "JAVA_HOME is set (${JAVA_HOME})"
    else
      check_warn "JAVA_HOME is set but ${JAVA_HOME}/bin/java is not executable"
    fi
  else
    check_warn "JAVA_HOME unset — Maven may still work via PATH"
  fi
}

check_credentials() {
  if [[ -z "${ASF_USERNAME}" ]]; then
    check_fail "ASF username missing — pass --username / -u (or ASF_USERNAME)"
  elif [[ "${ASF_USERNAME}" =~ ^[a-z][a-z0-9_-]*$ ]]; then
    check_pass "ASF username looks plausible (${ASF_USERNAME})"
  else
    check_fail "ASF username '${ASF_USERNAME}' looks invalid (expected lowercase ASF id)"
  fi

  if [[ -z "${ASF_PASSWORD}" ]]; then
    if [[ "${MODE}" == "check-only" ]] && [[ ! -t 0 ]]; then
      check_warn "password not set yet (check-only without TTY — will not prompt)"
    elif [[ "${MODE}" == "check-only" ]]; then
      check_warn "password not set yet (will prompt before publish unless provided)"
    else
      check_warn "password not set yet — will prompt securely before publish"
    fi
  else
    if [[ "${#ASF_PASSWORD}" -lt 8 ]]; then
      check_fail "password looks too short (< 8 chars)"
    else
      check_pass "ASF password is set (${#ASF_PASSWORD} chars, value not printed)"
    fi
  fi
}

check_network_svn() {
  if ! have_cmd curl; then
    check_warn "curl not found — skipping SVN reachability check"
    return
  fi
  if curl -fsS --connect-timeout 8 -o /dev/null -I "${SVN_URL}" 2>/dev/null \
    || curl -fsS --connect-timeout 8 -o /dev/null "https://svn.apache.org/" 2>/dev/null; then
    check_pass "network reachability to svn.apache.org"
  else
    check_fail "cannot reach svn.apache.org — publish will fail offline"
  fi
}

check_svn_auth_if_possible() {
  if [[ -z "${ASF_USERNAME}" ]] || [[ -z "${ASF_PASSWORD}" ]]; then
    check_warn "skipping SVN credential probe (username/password incomplete)"
    return
  fi
  if ! have_cmd svn; then
    check_warn "svn CLI not installed — skipping live credential probe (Maven will still auth)"
    return
  fi

  # Non-interactive auth against the publish URL. Failure here almost always
  # means bad credentials or missing commit karma on the Unomi website tree.
  local svn_out
  svn_out="$(mktemp)"
  if SVN_SSH="" svn info "${SVN_URL}" \
      --non-interactive \
      --username "${ASF_USERNAME}" \
      --password "${ASF_PASSWORD}" \
      --no-auth-cache \
      >"${svn_out}" 2>&1; then
    check_pass "SVN credentials accepted for ${SVN_URL}"
  else
    check_fail "SVN credential probe failed for ${SVN_URL}"
    echo "         (wrong password, or account lacks commit access to the Unomi website)" >&2
    head -5 "${svn_out}" >&2 || true
  fi
  rm -f "${svn_out}"
}

check_git_hygiene() {
  if ! have_cmd git || [[ ! -d "${ROOT}/.git" ]]; then
    check_warn "not a git checkout — skipping dirty-tree warning"
    return
  fi
  if git -C "${ROOT}" status --porcelain 2>/dev/null | grep -q .; then
    check_warn "working tree has uncommitted changes — confirm you intend to publish them"
  else
    check_pass "git working tree is clean"
  fi
}

check_no_clean_trap() {
  # Soft guard: refuse if someone aliased/wrapped this script oddly; real
  # protection is never invoking `mvn clean` in publish_site().
  check_pass "publish will not run Maven clean (preserves docs/manual on SVN)"
}

check_prerequisites() {
  echo "==> Prerequisite checks (mode: ${MODE})"
  CHECKS_FAILED=0

  check_project_layout
  check_jekyll_config
  check_pom_publish_config
  check_docker_build_env
  check_maven_java
  check_credentials
  check_network_svn
  check_svn_auth_if_possible
  check_git_hygiene
  check_no_clean_trap

  if [[ "${SKIP_BUILD}" -eq 1 ]]; then
    if [[ -d "${ROOT}/${SITE_DIR}" ]]; then
      check_pass "--skip-build: ${SITE_DIR} exists (will validate before publish)"
    else
      check_fail "--skip-build set but ${SITE_DIR} is missing — build first"
    fi
  fi

  finish_prerequisite_checks
}

confirm_production_publish() {
  if [[ "${ASSUME_YES}" -eq 1 ]]; then
    echo "==> Confirmation skipped (--yes)"
    return 0
  fi
  if [[ ! -t 0 ]]; then
    echo "Refusing non-interactive production publish without --yes" >&2
    exit 1
  fi
  echo ""
  echo "About to publish ${SITE_DIR} to production:"
  echo "  SVN : ${SVN_URL}"
  echo "  URL : ${PROD_URL}"
  echo "  User: ${ASF_USERNAME}"
  if [[ "${MODE}" == "dry-run" ]]; then
    echo "  Mode: DRY RUN (no commit)"
  else
    echo "  Mode: LIVE commit to ASF SVN"
  fi
  echo ""
  echo -n "Type 'publish' to continue: " >&2
  local answer
  # shellcheck disable=SC2162
  read answer
  if [[ "${answer}" != "publish" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
}

publish_site() {
  local mvn_args=(
    install
    scm-publish:publish-scm
    "-Dusername=${ASF_USERNAME}"
    "-Dpassword=${ASF_PASSWORD}"
  )

  if [[ "${MODE}" == "dry-run" ]]; then
    mvn_args+=("-Dscmpublish.dryRun=true")
    echo "==> Maven scm-publish DRY RUN (no SVN commit)"
  else
    echo "==> Publishing to ${SVN_URL}"
  fi

  # Intentionally never: mvn clean
  mvn "${mvn_args[@]}"

  echo ""
  if [[ "${MODE}" == "dry-run" ]]; then
    echo "==> Dry run finished (nothing committed)"
  else
    echo "==> Publish finished"
    echo "    Live site: ${PROD_URL}"
    echo "    (CDN/cache may take a few minutes to refresh)"
  fi
}

check_prerequisites

if [[ "${MODE}" == "check-only" ]]; then
  if [[ "${SKIP_BUILD}" -eq 1 ]] && [[ -d "${ROOT}/${SITE_DIR}" ]]; then
    validate_built_site
  fi
  echo "==> Done (check only) — nothing published"
  exit 0
fi

prompt_password_if_needed

# Re-run credential presence + optional SVN probe now that password is available.
CHECKS_FAILED=0
echo "==> Post-prompt credential checks"
if [[ -z "${ASF_PASSWORD}" ]]; then
  check_fail "password still empty after prompt"
else
  check_pass "password available for Maven/SVN"
fi
check_svn_auth_if_possible
finish_prerequisite_checks

if [[ "${SKIP_BUILD}" -eq 1 ]]; then
  echo "==> Skipping Jekyll build (--skip-build)"
  validate_built_site
else
  build_site
fi

confirm_production_publish
publish_site
