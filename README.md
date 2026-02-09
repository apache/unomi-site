
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

## Publish

To publish the local website to the production location (https://unomi.apache.org/), you have to use:
Do not use the `clean` maven goal to not remove the previous generated site.

```shell
mvn install scm-publish:publish-scm -Dusername=YOUR_APACHE_USERNAME -Dpassword=YOUR_APACHE_PASSWORD
```
