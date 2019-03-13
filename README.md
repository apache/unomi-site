
Apache Unomi Website source repository
======================================

This project contains the Apache Unomi Website.

## Build

You need a machine with Maven to build the website.

Checkout:

```
git clone https://github.com/apache/unomi-site
```

Run Build:

```
mvn clean install
```

## Publish

To publish the local website to the production location (https://unomi.apache.org/), you have to use:

```
mvn install scm-publish:publish-scm -Dusername=YOUR_APACHE_USERNAME -Dpassword=YOUR_APACHE_PASSWORD
```
