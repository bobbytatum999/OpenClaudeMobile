# OpenClaude Mobile

Native iPhone conversion of the uploaded OpenClaude TypeScript/Bun CLI into an iOS 26+ SwiftUI app.

## What this project includes

- iPhone-only SwiftUI app target for iOS 26+
- OpenAI-compatible remote inference provider
- Hugging Face model search, GGUF discovery, and GGUF download/install flow
- Local GGUF runtime using `llama.swift` / `llama.cpp`
- Built-in localhost API server with OpenAI-compatible endpoints
- File import, text/PDF preview, and prompt attachment support
- GitHub Actions workflow that generates the Xcode project with XcodeGen and exports an unsigned device IPA

## Architectural mapping from the reference project

The uploaded archive is a TypeScript/Bun CLI with server/provider/tool abstractions. This mobile conversion preserves the parts that fit iPhone:

- provider selection and model routing
- direct chat sessions
- local or remote inference
- local API surface for other apps / Shortcuts / proxies
- file ingestion and contextual prompting

It intentionally omits the desktop-terminal-specific primitives that cannot map cleanly into the iOS sandbox:

- shell / bash / PowerShell execution
- direct arbitrary filesystem traversal outside user-selected files
- process spawning and LSP server management
- MCP desktop/server orchestration

## Project layout

- `project.yml` — XcodeGen project specification
- `Sources/` — SwiftUI app, services, runtime, local server
- `Resources/Assets.xcassets` — minimal asset catalog
- `.github/workflows/build-unsigned-ipa.yml` — CI archive + IPA packaging

## Build locally

1. Install Xcode 26+
2. Install XcodeGen (`brew install xcodegen`)
3. Run `xcodegen generate`
4. Open `OpenClaudeMobile.xcodeproj`
5. Build for a real iPhone or archive using the included GitHub Actions workflow

## CI output

The GitHub Action builds an unsigned `.xcarchive` and packages an unsigned `.ipa` for sideload workflows.
