#!/usr/bin/env bash
# Build the Apache Unomi website and publish to production (https://unomi.apache.org/).
#
# Uses Maven scm-publish to SVN (see pom.xml). This is NOT Netlify — use ./preview.sh
# for personal/community staging previews.
#
# Usage:
#   ./publish.sh --username ASF_ID          # prompts for password (no echo) - preferred
#   ./publish.sh --check-only -u ASF_ID
#   ./publish.sh --dry-run -u ASF_ID
#   ./publish.sh --skip-build -u ASF_ID     # reuse existing target/site
#   ./publish.sh -u ASF_ID -p 'SECRET'      # works, but the password lands in shell
#                                           # history and is visible in the process list
#
# Credentials may also come from the environment (never commit these):
#   ASF_USERNAME / ASF_PASSWORD
#   or APACHE_USERNAME / APACHE_PASSWORD
#
# The password is handed to Maven through a private temporary settings file, so it
# stays off the mvn command line and out of shell history. Maven's SCM provider still
# passes it to the svn child process as an argument while that process runs, so do
# not publish from a host you share with untrusted users. That settings file is used
# as Maven's *global* settings for this run (your ~/.m2/settings.xml still applies; a
# mirror or proxy configured in the Maven installation's conf/settings.xml does not).
# SVN only verifies the password at commit time: the checks here cannot tell a wrong
# password from a right one.
#
# Optional:
#   JEKYLL_IMAGE   Docker image (default: bretfisher/jekyll)
#   --yes, -y      Skip the interactive confirmation prompt
#   --force        Override the publish guards: dirty git tree, branch other than
#                  master, HEAD different from its upstream (or a failed fetch, or no
#                  upstream), not a git checkout, unrendered Liquid in the built site,
#                  _config.yml url not https://unomi.apache.org, and a target/site
#                  not built from the current clean commit
#
# Exit status: 0 published (or dry run / check finished), 3 Maven succeeded but
# checked nothing in to SVN (nothing was published), 1 anything else.
#
# Important: do not run Maven clean — it deletes target/, including the site that
# was just built and validated and the scm-publish working copy.

set -euo pipefail
# Unrendered Liquid in the built site stops a publish (see validate_built_site).
STRICT_LIQUID=1
# bash 5.2+ treats an unquoted & in a ${var//pat/repl} replacement as "the match",
# which would corrupt xml_escape. The option does not exist in older bash.
shopt -u patsub_replacement 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/site-common.sh
source "${ROOT}/scripts/lib/site-common.sh"
cd "$ROOT"

ASF_USERNAME="${ASF_USERNAME:-${APACHE_USERNAME:-}}"
ASF_PASSWORD="${ASF_PASSWORD:-${APACHE_PASSWORD:-}}"
MODE="publish"          # publish | check-only | dry-run
SKIP_BUILD=0
ASSUME_YES=0
FORCE=0
SVN_URL="https://svn.apache.org/repos/asf/unomi/website/"
PROD_URL="https://unomi.apache.org/"

usage() {
  # Print the leading comment block (everything after the shebang up to the first non-comment line).
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "${ROOT}/publish.sh"
  exit "${1:-0}"
}

require_value() {
  # $1 option name, $2 number of remaining arguments (including the option)
  if [[ "$2" -lt 2 ]]; then
    echo "Option $1 requires a value" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--username)
      require_value "$1" "$#"
      if [[ "$2" == -* ]]; then
        echo "Option $1 requires a value" >&2
        exit 1
      fi
      ASF_USERNAME="$2"
      shift 2
      ;;
    -p|--password)
      require_value "$1" "$#"
      ASF_PASSWORD="$2"
      shift 2
      ;;
    --check-only) MODE="check-only"; shift ;;
    --dry-run) MODE="dry-run"; shift ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    -y|--yes) ASSUME_YES=1; shift ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage 0 ;;
    *)
      # Do not echo the argument: a misplaced password could end up here.
      echo "Unknown option or unexpected argument (see --help)" >&2
      exit 1
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
  if ! IFS= read -rs ASF_PASSWORD; then
    echo "" >&2
    echo "No password entered" >&2
    exit 1
  fi
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
  # Run each tool, not just look it up: macOS ships java/svn stubs that exist but fail.
  local out
  if ! have_cmd mvn; then
    check_fail "mvn not found — install Apache Maven"
  elif out="$(mvn -v 2>&1)"; then
    check_pass "mvn found (${out%%$'\n'*})"
  else
    check_fail "mvn found but not runnable: ${out%%$'\n'*}"
  fi

  # Maven's SCM provider drives the svn command line client.
  if ! have_cmd svn; then
    check_fail "svn not found — Maven needs the Subversion command line client to publish"
  elif out="$(svn --version --quiet 2>&1)"; then
    check_pass "svn found (${out%%$'\n'*})"
  else
    check_fail "svn found but not runnable: ${out%%$'\n'*}"
  fi

  if ! have_cmd java; then
    check_fail "java not found — install a JDK for Maven"
  elif out="$(java -version 2>&1)"; then
    check_pass "java found (${out%%$'\n'*})"
  else
    check_fail "java found but not runnable: ${out%%$'\n'*}"
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
    check_password_shape
  fi
}

# Also run after the prompt, so a typed password gets the same checks.
check_password_shape() {
  # shellcheck disable=SC2016
  if [[ "${ASF_PASSWORD}" == *'${'* ]] || [[ "${ASF_PASSWORD}" != "${ASF_PASSWORD#[[:space:]]}" ]] \
    || [[ "${ASF_PASSWORD}" != "${ASF_PASSWORD%[[:space:]]}" ]]; then
    check_fail "password contains '\${' or leading/trailing whitespace, which Maven would alter — use the manual mvn command from the README"
  elif [[ "${#ASF_PASSWORD}" -lt 8 ]]; then
    check_fail "password looks too short (< 8 chars)"
  else
    check_pass "ASF password is set (${#ASF_PASSWORD} chars, value not printed; SVN verifies it at commit time)"
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

GIT_BRANCH=""
GIT_COMMIT=""

check_git_hygiene() {
  if ! have_cmd git || ! git -C "${ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    check_publish_guard "not a git checkout — cannot tell which branch or commit is being published"
    return
  fi
  GIT_BRANCH="$(git -C "${ROOT}" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  GIT_COMMIT="$(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null || true)"

  if [[ "${GIT_BRANCH}" == "master" ]]; then
    check_pass "on branch master (${GIT_COMMIT})"
  else
    check_publish_guard "on branch '${GIT_BRANCH}' (${GIT_COMMIT}), not master — production is published from master"
  fi

  if [[ -n "$(git -C "${ROOT}" status --porcelain 2>/dev/null)" ]]; then
    check_publish_guard "working tree has uncommitted changes — commit or stash them before publishing"
  else
    check_pass "git working tree is clean"
  fi

  # A stale or unpushed master publishes the wrong tree.
  local upstream ssh_cmd fetch_err
  # Never wait on a credential prompt: an unattended check would hang silently.
  # Keep the user's own ssh command (env or git config); leave a GIT_SSH wrapper alone.
  local fetch_env=(GIT_TERMINAL_PROMPT=0)
  ssh_cmd="${GIT_SSH_COMMAND:-$(git -C "${ROOT}" config core.sshCommand 2>/dev/null || true)}"
  if [[ -z "${ssh_cmd}" ]] && [[ -z "${GIT_SSH:-}" ]]; then
    ssh_cmd="ssh"
  fi
  if [[ -n "${ssh_cmd}" ]]; then
    fetch_env+=("GIT_SSH_COMMAND=${ssh_cmd} -o BatchMode=yes")
  fi
  local fetched=1
  if ! fetch_err="$(env "${fetch_env[@]}" git -C "${ROOT}" fetch --quiet 2>&1)"; then
    fetched=0
    check_publish_guard "git fetch failed (${fetch_err%%$'\n'*}) — cannot verify HEAD against the remote"
  fi
  upstream="$(git -C "${ROOT}" rev-parse --verify --quiet '@{u}' 2>/dev/null || true)"
  if [[ -z "${upstream}" ]]; then
    check_publish_guard "branch has no upstream — cannot tell whether it matches the remote"
  elif [[ "${fetched}" -eq 0 ]]; then
    : # already reported: the upstream ref may be stale, so do not claim a match
  elif [[ "${upstream}" == "$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)" ]]; then
    check_pass "HEAD matches its upstream"
  else
    check_publish_guard "HEAD differs from its upstream — pull or push so that what you publish is what is on the remote"
  fi
}

# With --skip-build the branch/dirty checks above describe the checkout, not what
# target/site was built from. build_site records that; compare it with HEAD.
# Also run right after a build, in case the source changed while it ran.
check_skip_build_source() {
  local stamp="${ROOT}/${BUILD_SOURCE_FILE}"
  local built_commit built_dirty head_commit
  if [[ ! -f "${stamp}" ]]; then
    check_publish_guard "no record of what ${SITE_DIR} was built from — rebuild without --skip-build"
    return
  fi
  read -r built_commit built_dirty <"${stamp}" || true
  head_commit="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || true)"
  if [[ -z "${head_commit}" ]] || [[ "${built_commit}" != "${head_commit}" ]]; then
    check_publish_guard "${SITE_DIR} was built from ${built_commit:0:7}, not the current commit ${head_commit:0:7}"
  elif [[ "${built_dirty}" != "clean" ]]; then
    check_publish_guard "${SITE_DIR} was built from a tree with uncommitted changes"
  else
    check_pass "${SITE_DIR} was built from the current commit (${head_commit:0:7})"
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
  check_git_hygiene
  check_no_clean_trap

  if [[ "${SKIP_BUILD}" -eq 1 ]]; then
    if [[ -d "${ROOT}/${SITE_DIR}" ]]; then
      check_pass "--skip-build: ${SITE_DIR} exists (will validate before publish)"
      check_skip_build_source
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
  echo "  Git : ${GIT_BRANCH:-unknown} @ ${GIT_COMMIT:-unknown}"
  if [[ "${MODE}" == "dry-run" ]]; then
    echo "  Mode: DRY RUN (no commit)"
  else
    echo "  Mode: LIVE commit to ASF SVN"
  fi
  echo ""
  echo -n "Type 'publish' to continue: " >&2
  local answer
  # shellcheck disable=SC2162
  read -r answer || answer=""
  if [[ "${answer}" != "publish" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
}

xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

MVN_SETTINGS=""
MVN_LOG=""
cleanup_mvn_settings() {
  if [[ -n "${MVN_SETTINGS}" ]]; then
    rm -f "${MVN_SETTINGS}"
  fi
  if [[ -n "${MVN_LOG}" ]]; then
    rm -f "${MVN_LOG}"
  fi
}
trap cleanup_mvn_settings EXIT

publish_site() {
  # Validate again: target/site may have changed while waiting at the prompts
  # (for example a preview.sh --local container regenerating it).
  validate_built_site
  CHECKS_FAILED=0
  check_skip_build_source
  finish_prerequisite_checks
  # scm-publish reads ${username} / ${password}. Supply them as profile properties in a
  # private global-settings file so the password stays off the mvn command line
  # (your own ~/.m2/settings.xml still applies).
  MVN_SETTINGS="$(mktemp)"
  chmod 600 "${MVN_SETTINGS}"
  {
    printf '<settings><profiles><profile><id>unomi-site-publish</id><properties>'
    printf '<username>%s</username>' "$(xml_escape "${ASF_USERNAME}")"
    printf '<password>%s</password>' "$(xml_escape "${ASF_PASSWORD}")"
    printf '</properties></profile></profiles>'
    printf '<activeProfiles><activeProfile>unomi-site-publish</activeProfile></activeProfiles></settings>\n'
  } >"${MVN_SETTINGS}"

  local mvn_args=(
    -gs "${MVN_SETTINGS}"
    install
    scm-publish:publish-scm
  )

  if [[ "${MODE}" == "dry-run" ]]; then
    mvn_args+=("-Dscmpublish.dryRun=true")
    echo "==> Maven scm-publish DRY RUN (no SVN commit)"
  else
    echo "==> Publishing to ${SVN_URL}"
  fi

  # Intentionally never: mvn clean
  # pipefail + set -e: a Maven failure still stops the script here.
  MVN_LOG="$(mktemp)"
  mvn "${mvn_args[@]}" 2>&1 | tee "${MVN_LOG}"

  echo ""
  if [[ "${MODE}" == "dry-run" ]]; then
    echo "==> Dry run finished (nothing committed)"
  elif ! grep -Eq 'Checked in [1-9][0-9]* file' "${MVN_LOG}"; then
    # Maven exits 0 when there was nothing to commit or the check-in was skipped.
    echo "==> Maven finished without checking any file in to SVN"
    echo "    Nothing was published (most likely no change since the last publish) — read the Maven output above"
    exit 3
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

# Re-check credential presence now that the password is available.
CHECKS_FAILED=0
echo "==> Post-prompt credential checks"
if [[ -z "${ASF_PASSWORD}" ]]; then
  check_fail "password still empty after prompt"
else
  check_password_shape
fi
finish_prerequisite_checks

if [[ "${SKIP_BUILD}" -eq 1 ]]; then
  echo "==> Skipping Jekyll build (--skip-build)"
  validate_built_site
else
  build_site
  # The build takes minutes: refuse to go on if the commit or tree changed meanwhile.
  CHECKS_FAILED=0
  check_skip_build_source
  finish_prerequisite_checks
fi

confirm_production_publish
publish_site
