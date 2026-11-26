
Apache Unomi Website source repository
======================================

This project contains the Apache Unomi Website. The website is generated using [Jekyll](https://jekyllrb.com/) 4.4
with [Liquid](https://shopify.github.io/liquid/) templates.

## Configuration

### Jekyll Config
Can be found in [_config](_config.yml) YAML file
```yaml
source: src/main/webapp
destination: target/site
```

### Data config
Can be found in [_data folder](src/main/webapp/_data/unomi.yml)
This contains some variables used to replace placeholders in the site.

## Third-party resources (Content Security Policy)

The ASF web servers send a [Content Security Policy](https://infra.apache.org/csp.html) that only lets pages load
scripts, styles, fonts, images and frames from the site itself and from a few ASF hosts (`*.apache.org`). Anything
served by a CDN, Google Fonts, Gravatar, etc. is blocked in the browser. Keep such files in the repository instead:

| Path | Content |
|---|---|
| `src/main/webapp/assets/vendor/bootstrap` | Bootstrap 5.3.8 (CSS and JS bundle) |
| `src/main/webapp/assets/vendor/bootstrap-icons` | Bootstrap Icons 1.11.3 (CSS and fonts) |
| `src/main/webapp/assets/vendor/inter` | Inter variable font (declared in `assets/css/unomi.css`) |
| `src/main/webapp/assets/vendor/mermaid` | Mermaid 11.17.2 (loaded only by pages with `mermaid: true`) |
| `src/main/webapp/assets/images/team` | Team page avatars |

The build validation fails when a built page loads a resource from another host, and Netlify previews send the same
policy (`netlify.toml`), so a blocked resource shows up in the browser console before publishing.

## Build

You need either Docker (recommended) or a local Ruby/Jekyll installation to build the website.

Checkout the current project:

```shell
git clone https://github.com/apache/unomi-site
```

### Build with Docker (recommended)

Using the [bretfisher/jekyll](https://hub.docker.com/r/bretfisher/jekyll) Docker image.
No local Ruby or Jekyll installation required.

Because this repo includes a `Gemfile`, run `bundle install` inside the container
before building (otherwise Bundler may raise `GemNotFound` against a local `Gemfile.lock`):

```shell
docker run --rm \
  --volume="$PWD:/site" \
  -w /site \
  --entrypoint bash \
  bretfisher/jekyll \
  -lc 'bundle install && bundle exec jekyll build'
```

The generated site will be in the folder `target/site`.

### Local development server with Docker

Serves the site at http://localhost:4000/ and rebuilds on source changes (reload the page to see them):

```shell
docker run --rm \
  --volume="$PWD:/site" \
  -p 4000:4000 \
  -w /site \
  --entrypoint bash \
  bretfisher/jekyll-serve \
  -lc 'bundle install && bundle exec jekyll serve --host 0.0.0.0 --port 4000'
```

`./preview.sh` / `./preview.sh --local` use the same Docker + `bundle install` flow.
### Build with local Jekyll

Requires Ruby 2.7+ and Bundler. Install dependencies once, then build:

```shell
bundle install
bundle exec jekyll build
```

Or serve locally, rebuilding on source changes:

```shell
bundle exec jekyll serve
```

## Which command should I use?

| Goal | Command | Resulting URL | Credentials |
|---|---|---|---|
| Quick review (throwaway link) | `./preview.sh` | Unique draft, e.g. `https://<deploy-id>--unomi-preview.netlify.app` | Netlify account |
| Stable link to share with reviewers | `./preview.sh --prod` | `https://unomi-preview.netlify.app` | Netlify account |
| Local, rebuilds on change | `./preview.sh --local` | `http://localhost:4000` | none |
| **Official** Apache site | `./publish.sh` | `https://unomi.apache.org` | **ASF LDAP** (not Netlify) |

Important distinctions:

- **`./preview.sh --prod` ≠ Apache production.** “Prod” here only means Netlify’s primary URL for the **preview** project (`unomi-preview`). It never updates `unomi.apache.org`.
- **`./publish.sh` ≠ Netlify.** It publishes via Maven scm-publish to ASF SVN. That is the only path for the official site.
- Netlify staging is for personal/community review only. Do not commit Netlify tokens or `.netlify/` state into git.
- Preview copies are served with `X-Robots-Tag: noindex, nofollow` (see `netlify.toml`) and do not report to the ASF Matomo instance, which only runs on `unomi.apache.org`.

## Staging preview (Netlify)

`./preview.sh` builds the site with Docker Jekyll and deploys a **personal/community** staging copy on Netlify (same idea as the earlier UNOMI-932 preview at `https://unomi-v3-site.netlify.app/`).

### Draft vs `--prod` (both are Netlify-only)

| | `./preview.sh` (draft) | `./preview.sh --prod` |
|---|---|---|
| Purpose | Safe experiment / PR-style preview | Cleaner URL for reviewers |
| URL shape | `https://<id>--unomi-preview.netlify.app` (new each deploy) | `https://unomi-preview.netlify.app` (stable) |
| Overwrites previous share link? | No — old drafts remain until expired/removed | Yes — replaces the site’s main Netlify URL |
| Affects `unomi.apache.org`? | No | No |

Use draft while iterating; switch to `--prod` when you want one stable link to paste in email/JIRA/Slack.

### Prerequisites

| Requirement | Needed for | Notes |
|---|---|---|
| [Docker](https://docs.docker.com/get-docker/) + running daemon | All modes | Pulls `bretfisher/jekyll` / `bretfisher/jekyll-serve` |
| [Node.js](https://nodejs.org/) (includes `npx`) **or** [Netlify CLI](https://docs.netlify.com/cli/get-started/) | Netlify deploy (`./preview.sh`, `--prod`) | Script uses `netlify` if installed, otherwise `npx netlify-cli` |
| Netlify account | Netlify deploy | Free personal account is enough |
| Network access | Image pull + Netlify API | First build downloads the Jekyll image |

Optional:

- `curl` — used in prerequisite checks for Netlify reachability
- `open` (macOS) — used with `--open` to launch the preview URL
- `lsof` — warns if port 4000 is already taken for `--local`

Verify tooling before building:

```shell
./preview.sh --check-only
```

### Credentials and configuration

**Auth (pick one):**

1. **Interactive login** (simplest):

   ```shell
   npx netlify-cli login
   # or: netlify login
   ```

   Opens a browser and stores credentials in your user Netlify CLI config (`~/Library/Preferences/netlify` on macOS, `~/.config/netlify` on Linux).

2. **Personal access token** (CI / non-interactive):

   Create a token in the Netlify UI: **User settings → Applications → Personal access tokens**, then:

   ```shell
   export NETLIFY_AUTH_TOKEN=your_token_here
   ```

**Site linking (pick one):**

| Variable / file | Purpose |
|---|---|
| (default) | Script creates/links a site named `unomi-preview` on first deploy |
| `NETLIFY_ACCOUNT_SLUG` | Team to create the site in, when your Netlify account has several teams and no default one |
| `NETLIFY_SITE_NAME` | Override the Netlify site name (default: `unomi-preview`). Netlify site names are global, so `unomi-preview` belongs to whichever account created it first. For anyone else Netlify creates `unomi-preview-NNN` instead and the script prints that share URL; set a name of your own to avoid the suffix. Ignored once `.netlify/state.json` exists or `NETLIFY_SITE_ID` is set (delete `.netlify/` to link a different site) |
| `NETLIFY_CLI_VERSION` | `netlify-cli` major version used through `npx` (default: `27`, which needs Node 22.13 or later) |
| `NETLIFY_SITE_ID` | Use an existing site id and skip interactive link |
| `.netlify/state.json` | Created after a successful link; reused on later runs (gitignored) |

Example:

```shell
export NETLIFY_AUTH_TOKEN=...          # optional if already logged in
export NETLIFY_SITE_NAME=unomi-preview # optional
export NETLIFY_SITE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  # optional
```

Other optional env vars:

| Variable | Default | Purpose |
|---|---|---|
| `JEKYLL_IMAGE` | `bretfisher/jekyll` | Docker image used to build |
| `JEKYLL_SERVE_IMAGE` | `bretfisher/jekyll-serve` | Docker image used for `--local` |

`netlify.toml` in this repo sets `publish = "target/site"`. The script builds locally first; Netlify only hosts the static output. It does **not** connect GitHub or configure ASF repo webhooks — decline any Netlify prompt asking for GitHub authorization.

### Usage

From the repository root:

```shell
chmod +x ./preview.sh ./publish.sh   # once

./preview.sh --check-only   # validate Docker, layout, Netlify tooling/auth hints
./preview.sh                # build + Netlify *draft* deploy (unique preview URL)
./preview.sh --prod         # build + Netlify *site* URL (e.g. https://unomi-preview.netlify.app)
./preview.sh --local        # build + serve at http://localhost:4000 (no Netlify)
./preview.sh --build-only   # build only → target/site
./preview.sh --open         # after a Netlify deploy, open the URL (macOS)
```

`--prod` = Netlify site production for the preview project only. For Apache production see [Publish](#publish-production-unomiapacheorg) / `./publish.sh`.

Flags can be combined where it makes sense, e.g. `./preview.sh --prod --open`.

Typical first-time flow:

1. Start Docker Desktop (or your Docker daemon).
2. `./preview.sh --check-only` and fix any `[FAIL]` lines.
3. `./preview.sh` — complete Netlify login / site link if prompted; open the draft URL yourself.
4. When ready to share one stable link: `./preview.sh --prod` → send `https://unomi-preview.netlify.app/`.
5. When the content is approved for the official site: `./publish.sh` (ASF LDAP) → `https://unomi.apache.org/`.

### What the script does

1. Runs prerequisite checks (`[ok]` / `[warn]` / `[FAIL]`).
2. Builds with Docker Jekyll into `target/site` and validates the output.
3. Authenticates to Netlify, links/creates the site if needed, deploys a draft (or `--prod` site URL), prints the share link.

Shared helpers live in `scripts/lib/site-common.sh` (also used by `./publish.sh`).

## Publish (production: unomi.apache.org)

This is the **official** Apache Unomi website. It is **not** Netlify and is unrelated to `./preview.sh --prod`.

Use `./publish.sh`, which builds with Docker Jekyll, runs strong validations, then publishes via Maven `scm-publish` to ASF SVN (`https://svn.apache.org/repos/asf/unomi/website/`).

Do **not** use the Maven `clean` goal — it deletes `target/`, including the site that was just built and validated and the scm-publish working copy. (The published `docs/`, `manual/`, etc. trees are preserved on SVN by `ignorePathsToDelete` in `pom.xml`.)

Credentials: your **ASF LDAP username and password** (not Netlify). Let the script prompt for the password (or set `ASF_PASSWORD`). `-p` also works, but it puts the password in your shell history and in the process list. The script passes the password to Maven through a private temporary settings file, which keeps it off the `mvn` command line, and never prints it. Maven's SCM provider still hands it to the `svn` child process as an argument while that runs, so do not publish from a host shared with untrusted users. The temporary file replaces Maven's global settings for the run: `~/.m2/settings.xml` still applies, a mirror or proxy set in the Maven installation's `conf/settings.xml` does not. The username must be a lowercase ASF id. Passwords containing `${` or leading/trailing whitespace are refused because Maven would alter them, and passwords shorter than 8 characters are refused as implausible (`--force` overrides neither); use the manual command below for those.

```shell
./publish.sh --check-only --username YOUR_APACHE_USERNAME
./publish.sh --dry-run -u YOUR_APACHE_USERNAME
./publish.sh -u YOUR_APACHE_USERNAME
```

| Flag / env | Purpose |
|---|---|
| `-u` / `--username` | ASF LDAP username (or `ASF_USERNAME` / `APACHE_USERNAME`) |
| `-p` / `--password` | ASF LDAP password (or `ASF_PASSWORD` / `APACHE_PASSWORD`; prompts if omitted) |
| `--check-only` | Run prerequisite checks only (no build/publish) |
| `--dry-run` | Full build + validate + Maven scm-publish dry run (no SVN commit) |
| `--skip-build` | Reuse an existing `target/site` (still validated) |
| `--yes`, `-y` | Skip typing `publish` to confirm (required for non-interactive runs) |
| `--force` | Override the publish guards: dirty git tree, branch other than `master`, `HEAD` different from its upstream (or a failed fetch, or no upstream), not a git checkout, unrendered Liquid tags in the built site, `_config.yml` `url` not `https://unomi.apache.org`, and a `target/site` not built from the current clean commit |

Before publishing, the script checks project layout, Jekyll config, `pom.xml` scm-publish settings, Docker, Maven/Java, the `svn` client, SVN reachability, the git state (it refuses a dirty tree or a branch other than `master` unless `--force` is given; it also fetches and refuses a `HEAD` that differs from its upstream, and it refuses a `target/site` that was not built from the current clean commit, whether just built or reused with `--skip-build`), and the built site contents (required pages, file counts, no Jekyll source dirs). It cannot verify the password: SVN only checks it at commit time, so a wrong one fails at the final Maven step. The script exits with status `3` when Maven succeeds but checks nothing in to SVN (typically no change since the last publish), so a wrapper can tell that from a real publish.

Manual Maven command. It is **not** equivalent to the script: it skips the Jekyll build, the site validation, the git checks and the confirmation, and publishes whatever is in `target/site`. Build and check `target/site` first (`./preview.sh --build-only`):

```shell
mvn install scm-publish:publish-scm -Dusername=YOUR_APACHE_USERNAME -Dpassword=YOUR_APACHE_PASSWORD
```

This form exposes the password in your shell history and the process list.
