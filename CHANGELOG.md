# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **The panel.** A Liquid Glass panel from the menu bar (frosted material before macOS 26), with a card per display. Each card has a Control Center–style brightness slider; volume, SDR/XDR and input appear only where the display supports them. **All displays** appears with more than one display, and **Auto** and **Rounded corners** sit at the bottom. The menu bar moon fills out with brightness.
- **Brightness for every display.**
  - The built-in screen and Apple monitors through macOS.
  - Other monitors over DDC/CI: through IOAVService on Apple Silicon and the framebuffer's I2C bus on Intel. The serial queue coalesces writes, retries garbled replies and waits after the Mac wakes.
  - Software dimming (colour table or overlay) for displays without DDC.
- **Below 0%:** the slider continues into software dimming, with a haptic tick at 0%.
- **XDR:** displays with HDR headroom go past 100%, up to about three times as bright, through an extended-range overlay.
- **Volume, mute, input and contrast** over DDC. Switching the input of your only display asks first. Monitors that answer DDC without reporting their values (common with LG) can show these controls on request.
- **Keys.** The brightness and volume keys work on every display, with a glass indicator; ⌥⇧ gives quarter steps. Global shortcuts for brighter, dimmer, XDR and rounded corners.
- **Auto brightness.** *Match Mac* follows the built-in display; *Sun* follows daylight from your location or your time zone. Both learn from your adjustments.
- **Rounded corners** on every screen, with an adjustable radius, kept out of screenshots.
- **Turn a display off** (and back on) without unplugging it, when there's another display.
- **Settings:** General, Displays (name, brightness range, contrast, Test Controls, Advanced), Auto Brightness (with today's daylight curve), Keyboard and About. A welcome window on first launch, and open at login.
- **Updates** with Sparkle, signed with EdDSA; universal releases built and published by CI on every push to `main`.
