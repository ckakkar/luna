# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
From a code review (issues #5–#16):
- **Turning displays off:** two quick clicks could turn off every display. Luna now always keeps one on. (#5)
- **Identical monitors:** after a reconnect, two of the same model could end up sharing one DDC channel. A channel is never handed out twice now. (#6)
- **Several DDC monitors:** dragging one monitor's slider held up DDC for the others; monitors now take turns. (#7)
- **Built-in and Apple displays:**
  - Brightness shortcuts did nothing on them, and with the keys set to all displays, the keys skipped them. (#8)
  - After the first auto-brightness glide, Luna's slider stopped following the brightness keys and Control Center. (#9)
- **Choosing XDR:** a glide in progress could undo it. (#9)
- **Software dimming:** volume and contrast did nothing on a monitor dimmed in software. (#10)
- **Panel height:** the panel could grow past the bottom of the screen; it now stops there and scrolls. (#11)
- **Advanced › Hardware (DDC):** choosing it on a monitor started in Software didn't connect until a restart. (#12)
- **Sun mode:** it asked for Location on its own; now only when you click **Use my location**. (#13)
- **Dim below 0%:** turning it off left the display dimmed. (#14)
- **Changes made while Luna reads from the monitor:** a volume or brightness change made at that moment could be undone. Test Controls also no longer discards a change made while it runs. (#15)
- **Reset This Display:** it left XDR on. (#16)

### Fixed
- With XDR on, the screen dimmed for a moment when switching Spaces, changing pages in Safari or playing Netflix.
  - **Apple XDR displays:** XDR now lifts the display's colour table into its HDR headroom instead of laying a multiplying window over the screen. The display pipeline applies the table after macOS has drawn everything, so the boost holds through Space swipes, Mission Control and full-screen video. The overlay remains only for displays without a colour table.
  - **HDR monitors:** XDR is no longer offered by default. In HDR mode macOS already runs normal content near the monitor's peak (about 1.2× left at full brightness), so XDR made macOS dim everything else, and the screen dipped wherever the boost couldn't reach. Opt in under Settings › Displays › Advanced.
- Luna 0.1.4 quit a second after opening on Macs where macOS reports brightness changes for the display: the brightness callback ran on DisplayServices' own thread and tripped Swift's main-thread check. Callbacks from macOS now hop to the main thread themselves.

### Changed
- Updates work like Trav's: Luna checks soon after it opens and every hour (was every six hours). An update found in the background puts a dot on the menu bar moon and an **Update** card in the panel, instead of a window popping up mid-task.
- The disk image opens to a designed window: Luna and Applications on a dusk sky, with an arrow between them and the one-time **Open Anyway** step spelled out.

### Added
- `make selftest` (`Luna --self-test`) checks every feature against your real displays.

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
