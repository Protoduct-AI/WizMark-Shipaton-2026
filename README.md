# WizMark

Save links. Keep the context. Find them when you need them.

WizMark is a native iPhone and iPad bookmark manager built with SwiftUI. Save a webpage from the share sheet, organize it into collections, add notes and tags, and enrich saved links with AI summaries and place information.

[App Store](https://apps.apple.com/app/id6784499093) · [Website](https://wizmark.protoductai.com) · [Shipaton project](https://devpost.com/software/wizmark)

## Features

- Native share extension for saving links from other apps.
- Searchable bookmarks, nested collections, notes, tags, and customizable collection colors and symbols.
- Local storage with SwiftData and personal sync through CloudKit.
- Shared collections backed by Convex and Clerk authentication.
- Pro AI enrichment through a server-side Gemini integration.
- RevenueCat subscriptions, purchase restoration, and a separate ad-removal purchase.
- English and Japanese interfaces, with light and dark appearances.

## Source layout

| Directory | Purpose |
| --- | --- |
| `Sources/WizMark` | SwiftUI app, services, resources, and asset catalog |
| `Sources/WizMarkShare` | iOS Share Extension |
| `Sources/WizMarkTests` | iOS smoke tests |
| `convex` | Authenticated sharing, AI actions, subscription checks, and webhooks |
| `web` | React / Vite marketing website |
| `Config` | Templates for local Xcode configuration |
| `tests` | Offline security regression tests |

This is the public source snapshot prepared for RevenueCat Shipaton 2026, including security improvements made for publication. It starts with a fresh Git history. Credentials, development logs, signing files, and app binaries are not distributed here. The public source requires sign-in and a verified Pro entitlement for AI enrichment; it does not describe the deployment status of previously released app versions.

## Requirements

- macOS with Xcode 26.3 or later and an iOS Simulator (iOS deployment target: 17.0).
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).
- Node.js 22.12 or later and pnpm 10.33.0.
- Your own Convex, Clerk, and RevenueCat projects for connected features.
- Your own Apple developer configuration for device signing and CloudKit.

## Install dependencies

```sh
corepack enable
corepack prepare pnpm@10.33.0 --activate
pnpm install --frozen-lockfile
```

## Configure and run the backend

Create your own Convex deployment:

```sh
pnpm exec convex dev
```

Configure a Clerk JWT template named `convex`, with application ID / audience `convex`, and add its issuer to the Convex deployment environment. Use your own project and keys; the published app's infrastructure is not a development environment.

| Convex environment variable | Purpose |
| --- | --- |
| `CLERK_JWT_ISSUER_DOMAIN` | Clerk development JWT issuer URL |
| `CLERK_JWT_ISSUER_DOMAIN_PROD` | Optional separate Clerk production JWT issuer URL |
| `CLERK_WEBHOOK_SECRET` | Server-only signing secret for `/clerk-users-webhook` |
| `GEMINI_API_KEY` | Server-only Gemini API credential for AI extraction |
| `REVENUECAT_API_KEY` | Server-side credential used to check RevenueCat subscriptions |

In Clerk, configure the Convex deployment's `/clerk-users-webhook` HTTP endpoint for user creation, update, and deletion events. The webhook uses Svix signature verification.

Create the RevenueCat `pro` and `ad_free` entitlements and associate your own store products and offering. The signed-in Clerk user ID must be associated with the RevenueCat customer through `Purchases.logIn`. AI access is checked against the verified user's identity. A missing credential, failed subscription lookup, or inactive Pro entitlement denies AI access.

Never put server secrets in Xcode configuration, `Info.plist`, the website, or Git. The iOS RevenueCat **public SDK key** and Clerk **publishable key** are different from server credentials.

## Configure and run iOS

```sh
cp Config/Debug.xcconfig.template Config/Debug.xcconfig
cp Config/Release.xcconfig.template Config/Release.xcconfig
```

Fill in the local configuration files with your deployment URL and public client SDK keys. These files are ignored by Git. Optional analytics and error-reporting fields can remain empty.

For device builds, replace the development team and signing settings in `project.yml` with your own. Update the app and extension bundle identifiers, App Group, CloudKit container, and associated domains consistently in the project and entitlement files. The existing product identifiers and domains identify WizMark and do not grant access to its Apple account.

```sh
xcodegen generate
open WizMark.xcodeproj
```

Select the `WizMark` scheme and an iPhone or iPad Simulator, then build and run. Configuration templates are placeholders; connected services require your own valid configuration. Simulator compilation does not require signing credentials.

## Run the website

```sh
pnpm --filter web dev
pnpm --filter web build
```

## Validate changes

```sh
pnpm exec tsc --noEmit -p convex/tsconfig.json
pnpm test:security
pnpm --filter web build
xcodebuild test -project WizMark.xcodeproj -scheme WizMark \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO TEST_HOST='' BUNDLE_LOADER=''
```

Choose an installed simulator if its name differs. The iOS command compiles the app and share extension, then runs the XCTest smoke test without launching the app's connected services. It is not an end-to-end feature test. CI also checks the backend, website, and offline security regressions without production credentials.

## License

WizMark's original source and original project assets are licensed under the [Apache License 2.0](LICENSE). Third-party dependencies and fonts retain their own licenses and notices; iOS dependency acknowledgements and font licensing are included in the app resources. See [NOTICE](NOTICE).
