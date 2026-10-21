# Storage App

Storage App (temporary name) is an iPhone utility that helps people find unnecessary photos, screenshots, and large videos, then choose whether to remove them or compress supported media to free up storage.

This repository contains the marketing website and, later, the iOS app and content tooling. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the pieces fit together.

## Repository layout

| Folder | Contents |
| --- | --- |
| [`web/`](web) | Next.js marketing website and guides library (TypeScript, Tailwind CSS, App Router). Guides live in [`web/content/guides`](web/content). |
| [`ios/`](ios) | Native SwiftUI app (Phase 1: Demo Mode with simulated data). The Xcode project is generated with XcodeGen on macOS. |
| [`automation/`](automation) | Plan for the AI-assisted SEO/AEO content loop (not implemented yet). |
| [`docs/`](docs) | Project documentation. |

## Requirements

- **Git**
- **Node.js** 20.9 or newer (developed with Node 22 LTS) and **npm**
- For the iOS app: a Mac with Xcode 15.3+ and XcodeGen to build the app; the Swift toolchain on any OS to run the core logic tests

## Website: local development

All website commands run from `web/`.

```bash
cd web
npm install
cp .env.example .env.local   # first time only; on Windows PowerShell: Copy-Item .env.example .env.local
npm run dev
```

Then open http://localhost:3000.

### Checks

```bash
npm run lint        # ESLint
npm run typecheck   # TypeScript (generates Next.js route types first)
npm run build       # Production build
npm run start       # Serve the production build locally
```

### Environment variables

`web/.env.example` lists every variable the site reads, with safe defaults. Copy it to `web/.env.local` (Git-ignored) for local overrides. Production needs `NEXT_PUBLIC_SITE_URL` (canonical URLs and sitemap) and `WAITLIST_WEBHOOK_URL` (where signups go). Variables prefixed with `NEXT_PUBLIC_` are bundled into browser code, so never use that prefix for secrets.

## Deployment (website)

The site will deploy to [Vercel](https://vercel.com):

1. Push this repository to GitHub.
2. In Vercel, import the repository and set **Root Directory** to `web`. The Next.js framework preset and npm are detected automatically.
3. Add the variables from `web/.env.example` under Project Settings → Environment Variables.

Nothing is connected or deployed yet.

## iOS app

The app is native Swift and SwiftUI. Phase 1 runs entirely on a generated sample library (Demo Mode): it never accesses Photos, device files, or the network. Business logic lives in the `ios/StorageCore` Swift package, whose tests run on any OS with `swift test`; the app target builds on macOS (Xcode or the GitHub Actions workflow in `.github/workflows/ios.yml`). See [ios/README.md](ios/README.md) for build, run, and test instructions.
