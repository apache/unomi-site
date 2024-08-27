
Apache Unomi Website source repository
======================================

This project contains the Apache Unomi Website. The website is generated using [Jekyll](https://jekyllrb.com/) framework
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

You need a machine with Jekyll or Docker to build the website.

Checkout the current project:

```shell
git clone https://github.com/apache/unomi-site
```

### Build with Jekyll 
```shell
jekyll build
```

### Build with Docker
See Jekyll Docker's images [documentation](https://github.com/envygeeks/jekyll-docker/blob/master/README.md#server).
The Docker image provides all Ruby and Jekyll resources to avoid to install them locally. 
Note that the version used of Jekyll is set to 4.2.0 as the newer images have an issue with a missing dependency. 
```shell
 docker run --rm \
  --volume="$PWD:/srv/jekyll:Z" \
  -p 4000:4000 \
  jekyll/jekyll:4.2.0 \
  jekyll build 
```

The generated site will be in the folder `target/site`

## Publish

To publish the local website to the production location (https://unomi.apache.org/), you have to use:
Do not use the `clean` maven goal to not remove the previous generated site.
```shell
mvn install scm-publish:publish-scm -Dusername=YOUR_APACHE_USERNAME -Dpassword=YOUR_APACHE_PASSWORD
```

## Local build with local server
Run the following command
```shell
docker run --rm \
  --volume="$PWD:/srv/jekyll:Z" \
  -p 4000:4000 \
  jekyll/jekyll:4.2.0 \
  jekyll serve 
```

Then access to http://localhost:4000/ to access the site. Note that source changes are detected and apply automatically.
