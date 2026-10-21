# Credits

Luna is original code under the [MIT License](LICENSE). It stands on what these projects worked out and
shared. Where a technique came from one of them, the source file says so.

| Project | License | What Luna learned from it |
|---|---|---|
| [MonitorControl](https://github.com/MonitorControl/MonitorControl) | MIT | DDC/CI on Apple Silicon through IOAVService; matching framebuffers to displays by EDID; write timing; gamma and shade dimming; the media key tap. |
| [MediaKeyTap](https://github.com/MonitorControl/MediaKeyTap) | MIT | Reading the brightness and volume keys from `NX_SYSDEFINED` events. |
| [xdr-boost](https://github.com/levelsio/xdr-boost) | MIT | XDR brightness with an extended-range Metal layer composited with *multiply*. |
| [Rounder](https://github.com/nisesimadao/Rounder) | MIT | Rounded screen corners from four small click-through windows. |
| [HideNotch](https://github.com/niklasravnsborg/HideNotch) | MIT | Building and signing a Sparkle-updated menu bar app with SwiftPM alone. |
| [Sparkle](https://sparkle-project.org) | MIT-style ([license](https://github.com/sparkle-project/Sparkle/blob/2.x/LICENSE)) | Updates. Bundled. |
| NOAA solar calculator (Meeus, *Astronomical Algorithms*) | Public domain | The sun's position for *Sun* auto brightness. |

[Lunar](https://github.com/alin23/Lunar) by Alin Panaitiu showed what a Mac display app can do and is the
inspiration for Luna's feature set; none of its code is used.
