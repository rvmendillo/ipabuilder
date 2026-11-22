# ReyForge 3.0

**Design, vibe-code and build native iOS apps entirely on your iPhone.** No Mac, no GitHub runner needed to make apps:
ReyForge assembles, signs (with your own certificate) and installs real IPAs on device.

<p align="center"><img src="App/Builder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" alt="ReyForge icon"></p>

## What's inside

| | |
|---|---|
| **Visual builder** | Live SwiftUI canvas in a device frame. Every element is selectable, **draggable** (move handle → reorder, nest, or position freely inside a Free Layout) and **resizable** (corner handle). Library with drag-and-drop from 53 native components, layers tree (reorder, nest/unnest), undo/redo. |
| **Inspector** | Auto-generated for every component: content, data binding, repeat-for-each, visibility conditions, size, spacing, position, typography, fills & gradients, borders, shadows, Liquid Glass. |
| **Logic** | Visual logic editor: events (tap, long press, change, submit, appear, swipe-delete, refresh) → actions (navigate, alerts, toasts, variables, lists, if/else, validation, API requests, open URL, share, copy, haptics, notifications) with nested branches and one-tap recipes. Variables (persisted or computed), REST endpoints with a test console. |
| **ReyForge AI** | Claude-style vibe coding: describe screens or changes, watch the plan and the ReyForge Script stream in, review highlights, undo. Engines: **built-in Qwen3.5 2B** (Apache-2.0, llama.cpp on the GPU, offline), downloadable 0.8B / 4B models, Apple Intelligence (iOS 26), Claude (your API key), any OpenAI-compatible server, or the instant offline design engine. |
| **Templates** | 16 full apps including an **iOS Component Catalog** with every native component and style variant (charts, gauges, maps, video, web, pickers, forms, lists with swipe actions, pagers, menus, Sign in with Apple, QR, timers…). |
| **Branding** | Brand Studio: app name, bundle ID, version, icon designer (symbol / emoji / text / photo, gradients, shine), 12 theme presets plus custom colors and fonts, animated launch screen, Home Screen widget. |
| **On-device builds** | Runtime template → project + icons + widget → **zsign** with your .p12 + .mobileprovision → IPA → install via the system installer (localhost + itms-services), or share the IPA (signed or unsigned). |
| **Updates** | GitHub Actions builds ReyForge on every push; the in-app updater downloads the release, re-signs it with your certificate on device and installs it over the current copy (projects are kept). |

## Install ReyForge on your iPhone

1. Get an IPA from **Releases** (`nightly` is rebuilt on every push to the default branch) or from the workflow run's **ReyForge-IPAs** artifact:
   - `ReyForge-3.0-unsigned.ipa` — full build with the built-in AI model (~1.3 GB)
   - `ReyForge-3.0-lite-unsigned.ipa` — without the model (download one in *Settings › ReyForge AI*)
2. Sign and install it with any signer you already use (ESign, Feather, Sideloadly, AltStore, TrollStore…), **or** let GitHub sign it for you:
   add these repository secrets (*Settings › Secrets and variables › Actions*) and the workflow also publishes `…-signed.ipa`:

   | Secret | Value |
   |---|---|
   | `SIGNING_P12_BASE64` | `base64 -i cert.p12` |
   | `SIGNING_P12_PASSWORD` | the .p12 password |
   | `SIGNING_PROFILE_BASE64` | `base64 -i profile.mobileprovision` |
   | `SIGNING_BUNDLE_ID` | optional, e.g. `com.you.reyforge` (defaults to your explicit profile's App ID) |

3. Optional one-tap install page: with the signing secrets set, enable **Settings › Pages › Source: GitHub Actions** and each
   release also deploys a page with `itms-services` install links — open it in Safari on your iPhone.
4. Once ReyForge is installed, add your certificate in **Settings › Signing certificates**. From then on updates install from **Settings › Updates** with one tap (download → re-sign on device → install).

## Build an app on device

1. **New app** → pick a template, start blank, or *Describe your app* and let ReyForge AI build it.
2. Edit on the canvas: tap to select, drag the ✥ handle to move, drag the corner to resize, long-press for more. Use the bottom bar for **Add**, **Layers**, **Design**, **Logic**, **AI**, **Data**, **Screens** and **Brand**.
3. **▶︎ Preview** runs the app with all logic. **Build** signs and installs it on your iPhone (or exports an unsigned IPA).

Certificates: a wildcard profile (`TEAMID.*`) signs any bundle ID and the widget extension. With an explicit profile, ReyForge uses the profile's bundle ID automatically and leaves the widget out if the profile doesn't cover `<bundle-id>.widget`.

## Architecture

```
Core/                     ReyForgeCore — platform-independent Swift package (tested on Linux + macOS)
  Model/                  Project, screens, nodes, components (53), actions, theme/brand, drop planning
  Logic/                  Expression engine (functions, templates {{…}}), action runner
  AI/                     Request analyzer, design engine (36 archetypes × 21 domains), ReyForge Script compiler,
                          prompts + GBNF grammars, Claude / OpenAI-compatible engines, knowledge base
  Build/                  App assembler, ZIP reader/writer, provisioning/certificate parsing
  Install/                Localhost HTTP + itms-services helpers
  Templates/              16 app templates
  ReyForgeLlama/          llama.cpp engine (prefix state caching, grammar-constrained sampling)
App/Shared/               SwiftUI renderer shared by the builder canvas, preview and generated apps
App/Runtime/              Player app embedded as RuntimeTemplate.zip (what every built app runs)
App/Widget/               WidgetKit extension shipped inside built apps
App/Builder/              The ReyForge app (editor, AI, signing vault, build service, updater)
App/Tests/                Unit tests (build pipeline, zsign signing, installer, editor, on-device LLM) + UI tests
```

How an IPA is made on device: the precompiled runtime app is unpacked, `ReyForgeProject.json` and imported images are embedded,
`Info.plist` is rebranded (bundle ID, name, version, URL scheme, icons rendered from your icon design), the widget is
re-identified or removed, then [zsign](https://github.com/zhlynn/zsign) signs the bundle with your certificate and
the result is zipped into an IPA that iOS installs through a short-lived localhost server.

## Develop

Requirements: Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
scripts/build-llama.sh Vendor/llama                 # llama.cpp static libs for iOS + Simulator
scripts/fetch-model.sh App/Builder/Resources/Models # optional: bundle Qwen3.5 2B (Apache-2.0)
xcodegen generate && open ReyForge.xcodeproj
cd Core && swift test                               # core tests (also run on Linux)
```

CI (`.github/workflows/build.yml`) runs core tests on Linux and macOS, builds the app, runs unit and UI tests on the
iOS Simulator (screenshots are uploaded as artifacts), packages full and lite IPAs, optionally signs them, and publishes releases.

What the tests cover:

- **Core (96 tests, Linux + macOS):** project model and migration, expressions and the logic runner, ReyForge Script,
  the AI request analyzer / design engine / agent, templates, drag-and-drop planning, ZIP, provisioning parsing, IPA assembly.
- **App unit tests (21, iOS Simulator):** embedded runtime template, icon rendering, unsigned IPA build, zsign signing with
  an imported certificate + profile, wrong-password rejection, ZIP certificate import, localhost installer (full + ranged
  downloads), editor add/edit/undo/redo/drag/resize/free layout/library drop/script console/import-export, runtime
  navigation and feedback, and the built-in Qwen3.5 model generating grammar-constrained JSON and UI elements via llama.cpp.
- **UI tests (9, iOS Simulator):** template gallery, add and edit elements, inspector, drag from the library onto the canvas,
  move handles, logic recipes running in Preview, vibe coding a new screen with AI, Brand Studio and screens, and building
  an IPA on device.

## Licenses

ReyForge source in this repository. Bundled/linked open source: Qwen3.5 (Apache-2.0), llama.cpp (MIT),
zsign (MIT), OpenSSL (Apache-2.0).
