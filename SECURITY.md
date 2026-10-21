# Security policy

## Reporting a vulnerability

Please report security issues privately to **cyrus@kkrwhofrags.xyz** (or a
GitHub private security advisory on this repository) rather than opening a
public issue. Include a description, reproduction steps and the affected
version. You should receive an acknowledgement within 72 hours.

## Scope and design notes

Luna runs unsandboxed (it has to reach displays through IOKit) and asks for as
little as it can:

- **Keys.** The Accessibility permission is used for one event tap that
  receives only system-defined events (the media keys). It doesn't receive
  ordinary key presses, and it stores nothing. Global shortcuts use Carbon hot
  keys, which need no permission.
- **Location** is asked for only when you click *Use my location*, is used
  only to compute sunrise and sunset, and stays on the Mac
  (`UserDefaults`). Without it, Luna estimates from the time zone.
- **Network.** The only connections are Sparkle's update checks to GitHub
  (`releases/latest/download/appcast.xml`) and the update download itself.
  An update installs only if its EdDSA signature verifies against the public
  key built into the app (`SUPublicEDKey`).
- **Private APIs** (DisplayServices, CoreDisplay, IOAVService, SkyLight) are
  looked up at runtime in `Sources/CPrivate`. A missing symbol disables the
  feature that needs it rather than crashing the app.
- **Display state.** Dimming, overlays and turned-off displays are undone when
  Luna quits (including on SIGTERM) and again when it next starts, so a crash
  can't leave a display dark.

Supported versions: the latest release (the app updates itself to it).
