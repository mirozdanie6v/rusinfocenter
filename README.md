# rusinfocenter

React + TypeScript migration of the RIC Nha Trang Telegram Mini App demo.

## Stack
- React 19
- TypeScript
- Vite / Node.js build toolchain
- Cloudflare Workers Static Assets

## Commands
```bash
npm install
npm run typecheck
npm run build
npm run dev
```

`npm run build` extracts the bundled media into `public/` and writes the production app to `dist/`.

## Cloudflare production
- Worker: `rusinfocenter`
- Custom domain: `rusinfocenter.viiversion.com`
- Deploy config: `wrangler.jsonc`
- CI: `.github/workflows/deploy-cloudflare.yml`

Required GitHub Actions secrets:
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

The Cloudflare account must own the `viiversion.com` zone. The hostname must not already be occupied by a conflicting CNAME before Wrangler creates the Worker Custom Domain.

## Prototype boundary
Payment, Telegram sending and backend writes remain demo/mocked. The UI and client-side scenarios are preserved from v32 and now compile through the React/TypeScript application layer.
