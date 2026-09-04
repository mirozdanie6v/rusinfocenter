# rusinfocenter

React + TypeScript migration of the RIC Nha Trang Telegram Mini App demo.

## Stack
- React 19
- TypeScript
- Vite / Node.js build toolchain
- Cloudflare Workers Static Assets
- Wrangler 4

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

### Manual deploy
```bash
npm install
npx wrangler login
npx wrangler whoami
npm run deploy
```

### Automatic deploy from GitHub
Every push to `main` runs typecheck, builds the Vite application and deploys it with Wrangler.

Required GitHub Actions repository secrets:
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`

The Cloudflare account must own the `viiversion.com` zone. The hostname `rusinfocenter.viiversion.com` must not be occupied by a conflicting DNS record before Wrangler creates the Worker Custom Domain.

## Prototype boundary
Payment, Telegram sending and backend writes remain demo/mocked. The UI and client-side scenarios are preserved from v32 and now compile through the React/TypeScript application layer.
