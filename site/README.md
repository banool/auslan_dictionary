# Site

The static info site for the app — landing page, privacy policy, and terms of service — served at https://auslandictionary.org. The deployable content is the `src/` tree as-is; there is no build step.

It's a Cloudflare Pages project named `auslan-dictionary`. There are two moving parts, each a single command, both run from this directory (`site/`).

## Deploy the site

```sh
npx wrangler@latest pages deploy
```

The project name and output dir come from `wrangler.toml`, so no flags are needed. The first deploy creates the `auslan-dictionary` Pages project (wrangler prompts for the production branch — use `master`); later deploys ship a new version of it. CI (`.github/workflows/pages.yaml`) runs the same command on pushes to `master` that touch `site/**`.

## Wire up the domains

```sh
bash scripts/attach-domains.sh
```

Points `auslandictionary.org` and `www.auslandictionary.org` at the Pages project: it clears any stale DNS record, creates a proxied CNAME to the project's `*.pages.dev` target, and attaches each host as a Pages custom domain. It's idempotent, so it's safe to re-run. **Run it after the first deploy**, since it needs the project to already exist.

## Credentials

Both commands need Cloudflare credentials. `attach-domains.sh` reads `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` from the environment, or from a gitignored `scripts/secrets.env` next to it (sourced automatically — one `KEY=value` per line). The token needs **Account → Cloudflare Pages: Edit**, **Zone → DNS: Edit**, and **Zone → Zone: Read**, with the zone permissions scoped to `auslandictionary.org`. The same two values are stored as GitHub Actions secrets so CI can deploy and attach domains too.

## Why a script for the domains?

The `auslandictionary.org` zone shipped with a dead `A → 2.31.150.138` placeholder record. Attaching a Pages custom domain on top of it isn't enough — the hostname keeps resolving to the stale record until it's deleted, so the site stays down. `attach-domains.sh` reconciles the record and the custom-domain binding in one idempotent step. This mirrors how the shared-lists backend handles its `api.*` / `share.*` hosts in dictionarylib (`lists/scripts/attach-domains.sh`); that script owns the lists backend, this one owns the apex site.
