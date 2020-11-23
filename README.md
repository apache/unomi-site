
Apache Unomi Website source repository
======================================

This project contains the Apache Unomi Website. The website is generated using Maven filtering (for version numbers) and
then is passed to Jenkins to build the pages using templates.

## Build

You need a machine with Maven installed to build the website.

Checkout:

```
git clone https://github.com/apache/unomi-site
```

Run Build:

```
mvn clean install
```

The generated site will be in target/generated-jekyll

## Publish

To publish the local website to the production location (https://unomi.apache.org/), you have to use:

```
mvn install scm-publish:publish-scm -Dusername=YOUR_APACHE_USERNAME -Dpassword=YOUR_APACHE_PASSWORD
```

## Generate jekyll site

`
mvn install
`

## Jekyll serve (from source)

`
mvn gem:exec@jekyll-serve-source
`

Note: the Jekyll serve will not filter the files so you will still see property references such as ${latest.stable.version}.
This is by design. If you want to see a final version you need to generate it using the `mvn clean install gem:exec@jekyll-serve-filtered` command.

It works as expected on Mac and Linux, but not on Windows the following stacktrace appears:
    
    [INFO] Configuration file: c:\Users\username\projects\jekyll-jruby-maven/src/main/webapp/_config.yml
    [INFO] Source: c:\Users\username\projects\jekyll-jruby-maven/src/main/webapp
    [INFO] Destination: c:\Users\username\projects\jekyll-jruby-maven\target\classes
    [INFO] Incremental build: disabled. Enable with --incremental
    [INFO] Generating...
    [INFO] C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/utils.rb:117:in `open': Permission denied - c
    :/Users/username/projects/jekyll-jruby-maven/src/main/resources/css (Errno::EACCES)
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/utils.rb:117:in `has_yaml_header?'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/reader.rb:43:in `block in read_directories'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/reader.rb:43:in `select'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/reader.rb:43:in `read_directories'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/reader.rb:17:in `read'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/site.rb:144:in `read'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/site.rb:57:in `process'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/command.rb:28:in `process_site'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/commands/build.rb:60:in `build'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/commands/build.rb:35:in `process'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/lib/jekyll/commands/build.rb:18:in `block in init_
    with_program'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/mercenary-0.3.5/lib/mercenary/command.rb:220:in `call'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/mercenary-0.3.5/lib/mercenary/command.rb:220:in `block in execute'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/mercenary-0.3.5/lib/mercenary/command.rb:220:in `each'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/mercenary-0.3.5/lib/mercenary/command.rb:220:in `execute'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/mercenary-0.3.5/lib/mercenary/program.rb:42:in `go'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/mercenary-0.3.5/lib/mercenary.rb:19:in `program'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/gems/jekyll-3.0.2/bin/jekyll:17:in `<top>'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/bin/jekyll:1:in `load'
    [INFO] from C:/Users/username/projects/jekyll-jruby-maven/target/rubygems/bin/jekyll:1:in `<top>'
    [INFO] from -e:1:in `load'
    [INFO] from -e:1:in `<top>'