# What the Fork 🍴

A macOS-native tool that visualizes your build process as an interactive timeline, so you can spot slowdowns, serial bottlenecks, and wasted work.

Named after the `fork()` syscall.

## Usage

```bash
wtf make
wtf cargo build
wtf npm run build
wtf xcodebuild
```

Launches the app, which updates live as your build runs.

## How It Works

`wtf` uses Apple's [Endpoint Security Framework](https://developer.apple.com/documentation/endpointsecurity) to intercept `fork`, `exec`, and `exit` syscalls during your build, then reconstructs the full process tree and analyzes it for inefficiencies.

## Building

Requirements:
- macOS 13+
- Xcode 15+
- [xcodegen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

```bash
git clone https://github.com/you/what-the-fork
cd what-the-fork
xcodegen generate
open WhatTheFork.xcodeproj
```

> **ESF Note:** The daemon requires the `com.apple.developer.endpoint-security.client` entitlement, which must be approved by Apple for distribution. For local development, you can run on a machine with SIP disabled.

## Running Tests

```bash
cd WTFCore && swift test
```

## Architecture

- `WTFCore/` — Pure Swift package: tree building, parallelism analysis, gap detection, suggestions
- `WTFDaemon/` — Privileged helper: ESF subscription, XPC event server
- `WTFApp/` — SwiftUI app: timeline visualization, analysis panels
- `wtf/` — CLI tool: launches builds, connects daemon and app

## License

MIT
