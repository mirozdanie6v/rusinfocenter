# RusInfoCenter Telegram Mini App

Production React + TypeScript migration of the RIC Nha Trang demo.

## Stack
- React 19
- TypeScript 7
- Vite 8
- Node.js 22 build toolchain
- Cloudflare Workers Static Assets
- GitHub Actions CI/CD

## Production
- Cloudflare account: `viiversion`
- Worker: `rusinfocenter`
- Domain: `https://rusinfocenter.viiversion.com`
- Branch: `main`

Every push to `main` runs the production pipeline:
1. Restore verified TypeScript source and media bundles from permanent GitHub Releases.
2. Verify archive sizes/checksums.
3. Install dependencies.
4. Run TypeScript typecheck.
5. Build the Vite production bundle.
6. Deploy Worker/static assets with Wrangler.
7. Attach `rusinfocenter.viiversion.com` through the Cloudflare Workers Domains API.
8. Verify `/` and `/tours` over HTTPS with HTTP 200.

## Commands
```bash
npm install
npm run typecheck
npm run build
npm run dev
```

## Routing
The original multi-page HTML demo is exposed through the React application router/data layer. Clean routes are supported together with the original `.html` aliases. Cloudflare serves SPA fallback through `assets.not_found_handling = "single-page-application"`.

## Build inputs
Large generated source/media archives are stored as permanent GitHub Release assets (`source-v32`, `media-v32`) rather than temporary external storage. CI validates the source archive SHA-256 before extraction.

## Prototype boundary
The migrated project preserves the v32 demonstration UI and client-side scenarios. Payment, Telegram sending, CRM/backend persistence and other production integrations remain demo/mocked until their backend implementation phase.
