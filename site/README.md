# Site

The static info site for the app — landing page, privacy policy, and terms of service — served at https://auslandictionary.org. The deployable content is the `src/` tree as-is; there is no build step.

It's a Cloudflare Pages project named `auslan-dictionary`. There are two moving parts, each a single command, both run from this directory (`site/`).

## Deploy the site

```sh
npx wrangler@latest pages deploy
```

The project name and output dir come from `wrangler.toml`, so no flags are needed. The first deploy creates the `auslan-dictionary` Pages project (wrangler prompts for the production branch — use `master`); later deploys ship a new version of it. CI (`.github/workflows/pages.yaml`) runs the same command on pushes to `master` that touch `site/**`.

## Wire up the domains

Domain reconciliation for this apex site now lives in the private backend repo's consolidated Cloudflare CLI, so all the Cloudflare logic has one home. From a checkout of `dictionary_backend`:

```sh
bun scripts/cf.ts apex
```

It points `auslandictionary.org` and `www.auslandictionary.org` at the `auslan-dictionary` Pages project: clears any stale DNS record, creates a proxied CNAME to the project's `*.pages.dev` target, and attaches each host as a Pages custom domain. Idempotent, so it's safe to re-run. **Run it once after the first deploy** (it needs the project to already exist); a redeploy never detaches an attached domain, so it isn't part of CI here.

## Credentials

The deploy command needs `CLOUDFLARE_API_TOKEN` (+ `CLOUDFLARE_ACCOUNT_ID`), stored as GitHub Actions secrets for CI. The `cf apex` domain step — run from the backend repo — needs a token with **Account → Cloudflare Pages: Edit**, **Zone → DNS: Edit**, and **Zone → Zone: Read**, scoped to `auslandictionary.org`; see that repo's `MANUAL_SETUP.md`.

## Why a script for the domains?

The `auslandictionary.org` zone shipped with a dead `A → 2.31.150.138` placeholder record. Attaching a Pages custom domain on top of it isn't enough — the hostname keeps resolving to the stale record until it's deleted, so the site stays down. The `cf apex` command reconciles the record and the custom-domain binding in one idempotent step, next to the shared-lists `api.*` / `share.*` reconciliation (`cf domains`) — every Cloudflare binding the account needs now lives in one typed CLI in the backend repo.
