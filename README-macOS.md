# Banjo: Recompiled — macOS HighDPI fork

A macOS-focused fork of [Banjo: Recompiled](https://github.com/BanjoRecomp/BanjoRecomp) that adds
**true Retina/HiDPI rendering**, fixes the **crash on quit**, ships a **native Liquid Glass app
icon**, and smooths out several macOS rough edges. All changes are macOS-only and do not affect the
Windows or Linux builds.

> **This repository and its releases do not contain game assets.** A legally-obtained copy of the
> original Banjo-Kazooie ROM is required to build and run the project, exactly as with upstream.

## What this fork adds

### 🖥️ True Retina / HiDPI rendering
The game now renders at the display's native pixel resolution on Retina Macs instead of an upscaled,
point-resolution image. This required enabling high-DPI surfaces and fixing two coordinate bugs that
the change exposed:
- **Mouse/cursor hit-testing** — menu clicks now land where you point. (Mouse coordinates are scaled
  from logical points to physical pixels to match the UI surface.)
- **Fullscreen layout** — the UI no longer squishes into a corner when entering fullscreen. (The UI
  surface size is now driven solely by the render framebuffer, not by point-based window-resize
  events.)

### 💥 Fixed: crash on quit
The app previously crashed on every quit (the macOS "quit unexpectedly" dialog). Root cause was a
use-after-free in the Metal renderer: several Metal objects created by autoreleasing (`+0`) factory
methods were explicitly released without a balancing `retain()`, so the autorelease pool's deferred
release later ran on freed memory during shutdown. Fixed with four `retain()` calls in the Metal
backend. (This is an upstream RT64/plume bug; worth contributing back.)

### 💎 Native Liquid Glass app icon
The Dock/Finder icon no longer shows the grey placeholder tile on macOS 26 (Tahoe). The bundle now
compiles an [Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer)
`.icon` package with `actool` into a Liquid Glass icon (`Assets.car`), with an auto-generated `.icns`
fallback for older macOS.

### ⌨️ Fixed: accent-picker popup while moving
Holding a movement key (WASD) no longer pops up the macOS accent/diacritic picker. The app disables
the per-app `ApplePressAndHoldEnabled` default at startup (key repeat still works normally).

### 🛠️ Build fixes for macOS
- **SDL2 include paths** corrected so the frontend libraries find SDL headers (the codebase mixes
  `<SDL.h>` and `<SDL2/SDL.h>` styles).
- Minor `patches/Makefile` flag fix for newer clang.

## Engineering detail
See **[`MACOS_PORT_NOTES.md`](MACOS_PORT_NOTES.md)** for the full root-cause analysis of each fix, the
exact code changes, a macOS debugging playbook (NSZombie / lldb), and notes on porting these fixes to
other N64Recomp-based projects.

## Releases & prebuilt builds
Like the upstream project, **no build here contains game assets** — you always supply your own
legally-obtained ROM at build/run time.

- **Releases:** any tagged macOS builds will appear on the
  [Releases page](https://github.com/quarrel07/BanjoRecomp-macOS-HighDPI/releases). (None yet — build
  from source for now.)
- **CI builds:** the [`macOS build`](.github/workflows/macos-build.yml) GitHub Action can compile the
  app on an Apple Silicon runner and attach the `.app` as a downloadable artifact. It pulls the ROM
  from a private repo *you* configure (repo secrets `SECRET_NAME` / `SECRET_TOKEN`), so the ROM is
  never stored here. Without those secrets it simply skips the build.
- **From source:** see below.

## Building on macOS
Prerequisites: Homebrew `cmake`, `ninja`, `sdl2`; full Xcode (for the `actool` icon step, Xcode 26+
for Liquid Glass); the N64Recomp toolchain; and your own ROM. See `MACOS_PORT_NOTES.md` §1 and the
upstream `BUILDING`/`README` for the recompiler steps, then:

```bash
cmake -S . -B build-cmake -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
  -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-cmake --target BanjoRecompiled -j$(sysctl -n hw.ncpu) --config Release
```

> **Note on dependencies:** several fixes live in submodules (`lib/rt64`, `rt64/src/contrib/plume`,
> `lib/RecompFrontend`) and one in the `N64Recomp` build tool. See the
> [Dependency forks](#dependency-forks) section for how those are provided.

## Dependency forks
The macOS fixes live in submodules and one build tool, so this fork repoints its submodules at
forks that carry the changes. A recursive clone of this repository pulls everything needed:

| Submodule / tool | Fork | What changed | Upstream |
|---|---|---|---|
| `lib/rt64` | `quarrel07/rt64` (`macos-highdpi`) | SDL2/Retina CMake config; points `plume` at the fork below | [rt64/rt64](https://github.com/rt64/rt64) |
| `lib/rt64/src/contrib/plume` | `quarrel07/plume` (`macos-highdpi`) | Metal over-release fixes (crash on quit); force Retina | [renderbag/plume](https://github.com/renderbag/plume) |
| `lib/RecompFrontend` | `quarrel07/RecompFrontend` (`macos-highdpi`) | HiDPI mouse scaling + fullscreen UI-dimension fix | [N64Recomp/RecompFrontend](https://github.com/N64Recomp/RecompFrontend) |
| `N64Recomp` (build tool) | `quarrel07/N64Recomp` (`macos-highdpi`) | `teq` instruction handler (needed to recompile) | [N64Recomp/N64Recomp](https://github.com/N64Recomp/N64Recomp) |

> `plume` is a submodule **inside** `rt64`, so the chain is: this repo → `quarrel07/rt64` →
> `quarrel07/plume`. `N64Recomp` is a standalone build tool (not a submodule of this repo); build it
> from the fork above before running the recompiler.
>
> To track upstream later, add the original repos as a second remote in each fork
> (`git remote add upstream <url>`).

## Relationship to upstream
This fork tracks [BanjoRecomp/BanjoRecomp](https://github.com/BanjoRecomp/BanjoRecomp) and only adds
macOS platform fixes. Credit for the game port, RT64 renderer, and N64: Recompiled tooling goes to the
respective upstream projects. The intent is to upstream these fixes where appropriate.
