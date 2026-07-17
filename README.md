
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

```shell
docker run --rm \
  --volume="$PWD:/site" \
  bretfisher/jekyll \
  build
```

The generated site will be in the folder `target/site`.

### Local development server with Docker

Serves the site at http://localhost:4000/ with live-reload on source changes:

```shell
docker run --rm \
  --volume="$PWD:/site" \
  -p 4000:4000 \
  bretfisher/jekyll-serve
```

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

## Staging preview (Netlify)

`./preview.sh` builds the site with Docker Jekyll and can publish a **personal/community** staging URL on Netlify (same approach as the UNOMI-932 preview at `https://unomi-v3-site.netlify.app/`).

This is **not** how `https://unomi.apache.org/` is published. Production still uses Maven scm-publish (see [Publish](#publish) below). Do not commit Netlify tokens or `.netlify/` state into git.

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
| (default) | Script creates/links a site named `unomi-v3-site` on first deploy |
| `NETLIFY_SITE_NAME` | Override the Netlify site name (default: `unomi-v3-site`) |
| `NETLIFY_SITE_ID` | Use an existing site id and skip interactive link |
| `.netlify/state.json` | Created after a successful link; reused on later runs (gitignored) |

Example:

```shell
export NETLIFY_AUTH_TOKEN=...          # optional if already logged in
export NETLIFY_SITE_NAME=unomi-v3-site # optional
export NETLIFY_SITE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx  # optional
```

Other optional env vars:

| Variable | Default | Purpose |
|---|---|---|
| `JEKYLL_IMAGE` | `bretfisher/jekyll` | Docker image used to build |
| `JEKYLL_SERVE_IMAGE` | `bretfisher/jekyll-serve` | Docker image used for `--local` |

`netlify.toml` in this repo sets `publish = "target/site"`. The script builds locally first; Netlify only hosts the static output.

### Usage

From the repository root:

```shell
chmod +x ./preview.sh   # once

./preview.sh --check-only   # validate Docker, layout, Netlify tooling/auth hints
./preview.sh                # build + Netlify *draft* deploy (unique preview URL)
./preview.sh --prod         # build + deploy to the linked site’s production URL
./preview.sh --local        # build + serve at http://localhost:4000 (no Netlify)
./preview.sh --build-only   # build only → target/site
./preview.sh --open         # after a Netlify deploy, open the URL (macOS)
```

Flags can be combined where it makes sense, e.g. `./preview.sh --prod --open`.

Typical first-time flow:

1. Start Docker Desktop (or your Docker daemon).
2. `./preview.sh --check-only` and fix any `[FAIL]` lines.
3. `./preview.sh` — complete Netlify login / site link if prompted.
4. Share the printed `https://….netlify.app/` URL for review.
5. Later deploys to the same linked site: `./preview.sh --prod`.

### What the script does

1. Runs prerequisite checks (`[ok]` / `[warn]` / `[FAIL]`).
2. Builds with Docker Jekyll into `target/site`.
3. For Netlify modes: authenticates, links/creates the site if needed, deploys `target/site`, prints the preview URL.

## Publish

To publish the local website to the production location (https://unomi.apache.org/), you have to use:
Do not use the `clean` maven goal to not remove the previous generated site.

Credentials: your **ASF LDAP username and password** (not Netlify).

```shell
mvn install scm-publish:publish-scm -Dusername=YOUR_APACHE_USERNAME -Dpassword=YOUR_APACHE_PASSWORD
```
