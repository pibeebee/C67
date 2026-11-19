# Travelants public pages

Cloudflare Worker `travelants-support` serves [Travelants Support](https://travelants.giovanc.com/support/) at the temporary hostname `travelants.giovanc.com`. The root redirects to `/support/`. The Worker serves static files and has no application bindings.

The first deployment on 19 November 2026 returned HTTP 200 at `/support/`, with bytes matching the local source file, and HTTP 302 at the root. Cloudflare version `8f00891a-a0ca-4b3c-89d0-ef95d73d426a`. The Privacy Policy draft is still in [privacy-policy](../privacy-policy/README.md).

## Update the site

From this directory, run the official `cf` CLI with an account authorized for the hostname. Use a version that supports `cf deploy <directory>`. The initial deploy used `1.0.0-rc.1` installed in a temporary runner so `cloudflare.config.ts` could resolve `cf/config`.

```sh
runner="$(mktemp -d)"
assets="$runner/public"
mkdir -p "$assets/support"
cp cloudflare.config.ts "$runner/"
cp ../support/index.html "$assets/support/"
printf '/ /support/ 302\n' > "$assets/_redirects"
npm install --prefix "$runner" --ignore-scripts --no-audit --no-fund cf@1.0.0-rc.1
cd "$runner"
./node_modules/.bin/cf deploy "$assets" --dry-run --no-provision
./node_modules/.bin/cf deploy --prebuilt --no-provision
```

Stage both pages. Copy `../privacy-policy/index.html` into `$assets/privacy-policy/index.html` before the dry run. Both pages returned HTTP 200 with matching local content after deploying version `1130abdb-6bde-41eb-a6ea-198934416da5`.

When changing hosts, update the custom domain configuration and URLs used by the store and app. Keep the old policy address reachable while installed builds still point to it.

[Cloudflare static deployment](https://developers.cloudflare.com/cf/projects/#deploy-a-static-assets-directory) · [Custom Domains](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
