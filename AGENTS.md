# Apache Unomi website — instructions for AI agents

Jekyll site for https://unomi.apache.org. Sources are in `src/main/webapp`, the build goes to
`target/site`, and `README.md` describes the build, preview and publish commands.

## Never load a resource from a third-party host

The ASF web servers send a Content Security Policy (https://infra.apache.org/csp.html) that blocks
every script, stylesheet, font, image, frame and `fetch` target that is not served by the site
itself or by an ASF host (`*.apache.org`, `www.apachecon.com`, `www.communityovercode.org`,
`*.scarf.sh`). A blocked stylesheet leaves the published site unstyled. This has broken the live
site more than once, because the page looks fine locally where no such policy applies.

- Do not add `<link>`, `<script>`, `<img>`, `<iframe>`, `<video>`, `@import`, CSS `url(...)` or
  `fetch(...)` pointing at a CDN (jsDelivr, unpkg, cdnjs), Google Fonts, Gravatar, YouTube, or any
  other outside host. Also do not add `preconnect` hints for them.
- To use a library, font or image, download a pinned version into
  `src/main/webapp/assets/vendor/<name>/` (with its LICENSE file) or `assets/images/`, reference it
  with a `/assets/...` path, and add it to the table in the README section "Third-party resources".
- Check what a vendored CSS or JS file loads itself (fonts, source maps, other URLs).
- Plain `<a href>` links to other sites are fine: the policy only covers resources the page loads.

## Check before you call a change done

- Run `./preview.sh --build-only`. The validation fails when a built page loads a resource from a
  host outside the policy. Do not weaken or bypass that check.
- That check only reads HTML tags. For changes to CSS, JavaScript or the layout, also load the
  built page in a browser with the production policy applied and confirm the console is empty.
  Netlify previews (`./preview.sh`) send the same policy through `netlify.toml`; keep that header
  identical to the one returned by `curl -sI https://unomi.apache.org/`.
