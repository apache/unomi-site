
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

Serves the site at http://localhost:4000/ with live-reload on source changes:

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

Or serve locally with live-reload:

```shell
bundle exec jekyll serve
```

## Which command should I use?

| Goal | Command | Resulting URL | Credentials |
|---|---|---|---|
| Quick review (throwaway link) | `./preview.sh` | Unique draft, e.g. `https://<deploy-id>--unomi-preview.netlify.app` | Netlify account |
| Stable link to share with reviewers | `./preview.sh --prod` | `https://unomi-preview.netlify.app` | Netlify account |
| Local live-reload | `./preview.sh --local` | `http://localhost:4000` | none |
| **Official** Apache site | `./publish.sh` | `https://unomi.apache.org` | **ASF LDAP** (not Netlify) |

Important distinctions:

- **`./preview.sh --prod` ≠ Apache production.** “Prod” here only means Netlify’s primary URL for the **preview** project (`unomi-preview`). It never updates `unomi.apache.org`.
- **`./publish.sh` ≠ Netlify.** It publishes via Maven scm-publish to ASF SVN. That is the only path for the official site.
- Netlify staging is for personal/community review only. Do not commit Netlify tokens or `.netlify/` state into git.

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

   Opens a browser and stores credentials in your user Netlify CLI config (`~/.netlify` / `~/.config/netlify`).

2. **Personal access token** (CI / non-interactive):

   Create a token in the Netlify UI: **User settings → Applications → Personal access tokens**, then:

   ```shell
   export NETLIFY_AUTH_TOKEN=your_token_here
   ```

**Site linking (pick one):**

| Variable / file | Purpose |
|---|---|
| (default) | Script creates/links a site named `unomi-preview` on first deploy |
| `NETLIFY_SITE_NAME` | Override the Netlify site name (default: `unomi-preview`) |
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

Do **not** use the Maven `clean` goal — it would remove previously published trees that scm-publish intentionally preserves (`docs/`, `manual/`, etc.).

Credentials: your **ASF LDAP username and password** (not Netlify). Pass them as parameters (or env vars); the password is never printed.

```shell
./publish.sh --check-only --username YOUR_APACHE_USERNAME
./publish.sh --dry-run -u YOUR_APACHE_USERNAME -p 'YOUR_APACHE_PASSWORD'
./publish.sh -u YOUR_APACHE_USERNAME -p 'YOUR_APACHE_PASSWORD'
```

| Flag / env | Purpose |
|---|---|
| `-u` / `--username` | ASF LDAP username (or `ASF_USERNAME` / `APACHE_USERNAME`) |
| `-p` / `--password` | ASF LDAP password (or `ASF_PASSWORD` / `APACHE_PASSWORD`; prompts if omitted) |
| `--check-only` | Run prerequisite checks only (no build/publish) |
| `--dry-run` | Full build + validate + Maven scm-publish dry run (no SVN commit) |
| `--skip-build` | Reuse an existing `target/site` (still validated) |
| `--yes` | Skip typing `publish` to confirm (required for non-interactive runs) |

Before publishing, the script checks project layout, Jekyll config, `pom.xml` scm-publish settings, Docker, Maven/Java, SVN reachability, optional live SVN auth (if `svn` is installed), git dirty-tree warnings, and the built site contents (required pages, file counts, no Jekyll source dirs).

Equivalent manual Maven command (prefer the script):

```shell
mvn install scm-publish:publish-scm -Dusername=YOUR_APACHE_USERNAME -Dpassword=YOUR_APACHE_PASSWORD
```
