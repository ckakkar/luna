# Contributing

## Setup

- macOS 14+ with Swift 6.2+: Xcode 26, or only the Command Line Tools (`xcode-select --install`). There is no Xcode project; everything is a Swift package plus scripts.

```bash
make            # list every task
make run        # a debug Luna.app, opened (quit the installed Luna first)
make preview    # the panel with made-up displays: ARGS="--dark --displays 3 --expanded"
make check      # lint, build and unit tests: what CI runs
make selftest   # the real app against your displays: brightness, dimming, XDR, corners, windows
make install    # build Luna.app and install it in /Applications
make dmg        # universal Luna.app and Luna.dmg in build/
make icons      # re-render the app icon from scripts/app-icon.swift
```

`make selftest` (`Luna --self-test`) drives the real app against the connected displays, checks each feature (brightness through macOS or DDC, following outside changes, dimming below 0%, XDR, rounded corners, the panel, indicator and Settings, and a clean restore on quit) and exits with the number of failures. The screen flickers while it runs.

`make preview` touches no hardware. Its options: `--dark`/`--light`, `--displays 1…3`, `--expanded` (cards show their extra options), `--sun`, `--backdrop` (a gradient behind the glass, for screenshots), `--settings [general|displays|auto|keyboard|about]`, `--welcome`, `--hud`.

## Expectations

- `make check` must pass: `swift format lint --strict` (config in `.swift-format`), a warning-free build in the Swift 6 language mode, and the tests. CI enforces all three.
- Logic that can be tested without hardware lives in `LunaCore` and gets tests in `Tests/LunaCoreTests`. That covers DDC packets, display matching, slider zones, curves, solar maths and settings.
- UI changes: look at them with `make preview` in light and dark, with one and three displays.
- Hardware changes: run `make selftest` on a real display.
- Callbacks from macOS (C function pointers, DisplayServices, Carbon) are plain `nonisolated` functions that hop to the main actor. A closure written inside main-actor code inherits that isolation, and Swift 6 traps at runtime when macOS calls it from another thread; Luna 0.1.4 crashed at launch this way.
- Private macOS APIs go through `Sources/CPrivate` only, looked up with `dlsym`, so a missing symbol degrades a feature instead of crashing.
- Code from other projects must be MIT-compatible and credited in [CREDITS.md](CREDITS.md). Lunar's source is not used.
- Record user-facing changes in `CHANGELOG.md` under *Unreleased*.

### Notes on the code

- `@ViewState` is SwiftUI's `State`. In the macOS 27 SDK `@State` is a macro whose plugin ships only with Xcode, so the property wrapper is named directly to keep Command Line Tools builds working.
- `Display` holds one display's state. How its brightness is controlled (`Control`) is separate from its DDC channel: Apple-controlled monitors can still have contrast, volume and input over DDC.
- All DDC traffic goes through one serial queue (`DDCChannel`); writes coalesce so dragging a slider never floods a monitor.
- Software dimming has one owner (`Dimmer`), whether it uses the gamma table or a shade window.

## Releases

There is nothing to do by hand: every push to `main` that passes CI is released by `.github/workflows/release.yml` as version `<major.minor>.<commits on main>`. The major.minor is `CFBundleShortVersionString` in `Resources/Info.plist`; bump it there for a bigger step. Each release carries:
- a universal `Luna.dmg`, whose window (`scripts/dmg-background.swift`, `scripts/dmg-settings.py`, laid out by [dmgbuild](https://github.com/dmgbuild/dmgbuild) in `.build/dmg-venv`) shows Luna, an arrow and Applications;
- `Luna.zip`, the archive Sparkle installs;
- `appcast.xml`.

Installed apps check the appcast soon after they open and then every hour, like Trav. Run the workflow by hand (Actions › Release › Run workflow) to rebuild the current commit if a release failed.

### Keys

Run `scripts/release-keys.sh` once on the maintainer's Mac. It creates both keys and prints the `gh secret set` commands.

- **Update key (Sparkle EdDSA).**
  - The public half is `Resources/SparklePublicKey.txt` (committed), which `scripts/build-app.sh` writes into the app.
  - The private half is the `SPARKLE_PRIVATE_KEY` repository secret, with a backup in `~/.luna/sparkle-private.key`.
  - Keep that backup: without it no future update can be signed, and installed apps would need a manual reinstall.
  - Local builds carry the public key too and check for updates, but their build number (commits on your branch) is never behind a release of the same commit.
- **Signing certificate ("Luna Self-Signed").**
  - Repository secrets `LUNA_CERT_P12` (base64) and `LUNA_CERT_PASSWORD`, with a backup in `~/.luna/`.
  - Signing every release with the same certificate keeps the app's identity stable, so macOS keeps the Accessibility permission (for the brightness keys) across updates. An ad-hoc signature changes with every build.
  - Import the `.p12` into your login keychain and `scripts/build-app.sh` uses it for local builds too.

### Apple code signing (optional)

Without an Apple Developer ID the app isn't notarized, so users click **Open Anyway** once (System Settings › Privacy & Security). To sign with a Developer ID and notarize, add these repository secrets; the release workflow picks them up when set:
- `APPLE_CERTIFICATE` (base64 .p12)
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_ID`
- `APPLE_PASSWORD` (app-specific)
- `APPLE_TEAM_ID`
