# macOS Port & Fixes — Engineering Notes

This document records the macOS-specific problems found in this project and exactly how they were
solved. It is written to be **portable to other N64Recomp-based apps** (anything built on the same
stack: `librecomp` / `ultramodern` / `RT64` + `plume` / `RecompFrontend`), because the root causes
live in those shared libraries and submodules — a sibling recomp project will almost certainly hit
the same build failure, the same Retina bugs, and the same quit crash, with the same fixes.

Stack reference (from the recomp architecture):

```
<App>Recompiled (executable)
├── RecompiledFuncs / PatchesLib        (generated MIPS → C)
├── rt64                                renderer (Metal on macOS) → src/contrib/plume (metal-cpp backend)
├── N64ModernRuntime                    librecomp + ultramodern + recompinput/recompui (RecompFrontend)
```

---

## 1. Building on macOS

### Prerequisites
- Homebrew toolchain: `cmake` (3.20+), `ninja`, `llvm`/clang with C++20, and **`sdl2`** (`brew install sdl2`).
- Submodules initialized: `git submodule update --init --recursive`.
- Recomp tooling present in the project root: `N64Recomp`, `RSPRecomp`, `file_to_c` (built from N64Recomp),
  and the decompressed ROM.
- **Full Xcode** (not just Command Line Tools) is required for the app icon step — it uses `actool`
  (see §4). Xcode 26+ for Liquid Glass `.icon` support.

### Preparing the decompressed ROM
The recompiler consumes `banjo.us.v10.decompressed.z64` — your Banjo-Kazooie ROM with its overlays
decompressed. Produce it once, from your own legally-obtained ROM, with MittenzHugg's tool (Rust):
```bash
git clone https://github.com/MittenzHugg/bk_rom_compressor
cd bk_rom_compressor && cargo build --release
# bk_rom_decompress <compressed/original rom> <output decompressed rom>
./target/release/bk_rom_decompress /path/to/your/banjo-kazooie.us.z64 banjo.us.v10.decompressed.z64
```
Put the output in the project root. It's a one-time, host-only step: `bk_rom_compressor` is **not** a
dependency of this repo (don't vendor it into `lib/`) — just a tool you run once to prep the ROM, the
same way `N64Recomp` is a standalone build tool rather than a submodule.

### Configure & build
```bash
cmake -S . -B build-cmake \
  -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang \
  -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-cmake --target BanjoRecompiled -j$(sysctl -n hw.ncpu) --config Release
```
Output bundle: `build-cmake/<App>Recompiled.app`.

### Build gotcha #1 — SDL2 include paths (the first-build blocker)
**Symptom:** `fatal error: 'SDL2/SDL_video.h' file not found` while compiling `recompui`.

**Why:** Upstream only *fetches* SDL2 on Windows. On macOS/Linux it relies on a system/Homebrew SDL2.
The macOS branch of the top-level `CMakeLists.txt` hard-coded:
```cmake
set(SDL2_INCLUDE_DIRS "/opt/homebrew/include/SDL2")   # <-- only the SDL2 subdir
```
But the codebase **mixes two SDL include styles**:
- `#include <SDL.h>` / `<SDL_video.h>`   → needs `.../include/SDL2` on the search path
- `#include <SDL2/SDL.h>` / `<SDL2/SDL_video.h>` → needs `.../include` on the search path

With only the `SDL2` subdir on the path, the `SDL2/`-prefixed includes can't resolve. The frontend
sublibraries (`recompui`, `recompinput`) consume `${SDL2_INCLUDE_DIRS}`, so they failed.

**Fix** (top-level `CMakeLists.txt`, `if (APPLE)` block) — put **both** directories on the path:
```cmake
set(SDL2_INCLUDE_DIRS "/opt/homebrew/include" "/opt/homebrew/include/SDL2")
```
> On Intel Macs the Homebrew prefix is `/usr/local` instead of `/opt/homebrew`. A more portable form
> is `execute_process(COMMAND brew --prefix sdl2 ...)`, but the project hard-codes Apple-Silicon paths.

The `rt64` submodule's `CMakeLists.txt` has the *same* Homebrew-SDL2 assumption (its `else()` branch
calls `find_package(SDL2)`), already patched there to set the Homebrew paths on Apple.

### Build gotcha #2 — outdated icon pipeline
The original bundle icon used `iconutil` on a hand-built **2-entry** iconset (just `icon_512x512.png`
and `icon_512x512@2x.png`, both copies of one PNG). That's an outdated approach and produced a
non-conforming icon on modern macOS. Replaced with an `actool` pipeline — see §4.

---

## 2. Retina / HiDPI

### Enabling native-resolution rendering
Two changes make the Metal drawable render at native (2×) pixels instead of an upscaled point-sized
buffer:
- `src/main/main.cpp`, `create_window()`: add `SDL_WINDOW_ALLOW_HIGHDPI` to the window flags.
- `plume` (`PLUME_APPLE_RETINA_ENABLED`): forced **ON** (in `rt64/CMakeLists.txt` and
  `rt64/src/contrib/plume/CMakeLists.txt`). With it, plume's `getWindowAttributes()` returns
  `contentView.frame * backingScaleFactor`, i.e. physical pixels, and sets the `CAMetalLayer`
  drawable size to match. (The real `NSWindow` reaches plume because `main.cpp` passes
  `wmInfo.info.cocoa.window`, not the `SDL_Window*`.)

Enabling HiDPI is what then exposed the two coordinate bugs below: the swap-chain framebuffer (and
therefore the UI) is now sized in **pixels**, while SDL still reports window geometry in **points**.

### Bug 2a — cursor can't hit menu items (hit-testing offset)
**Symptom:** you must move the cursor well to the *right* of an item to actually click it.

**Why:** the RmlUi UI context is sized from the swap-chain framebuffer (**pixels**), but SDL mouse
events arrive in **logical points**. RmlUi maps the point coordinate straight into its pixel-sized
context, so the effective hit point lands at roughly half the intended X/Y.

**Fix** (`RecompFrontend/recompui/src/base/ui_state.cpp`): compute the point→pixel ratio once and
scale `SDL_MOUSEMOTION` coordinates before handing them to RmlUi. Only motion events carry a
position into RmlUi (buttons reuse the last move), so that's the single place needed. Ratio is 1.0 on
non-HiDPI displays, so it's a no-op on Windows/Linux.
```cpp
int win_w, win_h, px_w, px_h;
SDL_GetWindowSize(window, &win_w, &win_h);
SDL_GetWindowSizeInPixels(window, &px_w, &px_h);
float sx = win_w ? (float)px_w / win_w : 1.0f, sy = win_h ? (float)px_h / win_h : 1.0f;
// ... in the event loop, for SDL_MOUSEMOTION: cur_event.motion.x *= sx; .y *= sy;
```

### Bug 2b — fullscreen squishes the UI into a ¼-size corner
**Symptom:** entering fullscreen crams all UI into a small box in a corner (~½ width × ½ height).

**Why:** `sdl_event_filter`'s `default:` branch queues **all** SDL events, including
`SDL_WINDOWEVENT`. In the recompui dequeue loop those reach `RmlSDL::InputEventHandler`, whose
`SDL_WINDOWEVENT_SIZE_CHANGED` handler calls `context->SetDimensions(window.data1, data2)` — the
window size in **points**, i.e. half the pixel framebuffer. The render hook sizes the context from
the framebuffer (**pixels**) but only when that size *changes*, so the resize event's half-size value
sticks and the UI renders into a quarter of the surface.

**Fix** (`RecompFrontend/recompui/src/base/ui_state.cpp`): handle `SDL_WINDOWEVENT` in the dequeue
switch — forward `SDL_WINDOWEVENT_LEAVE` to `ProcessMouseLeave()` but **do not** forward to RmlUi, so
the pixel-based render hook stays the single owner of the context dimensions. (Also had to brace-wrap
the preceding `SDL_CONTROLLERAXISMOTION` case so the new `case` label could be added without a
"jump to case label crosses initialization" error.)

> ⚠️ **Dead end worth remembering:** routing macOS fullscreen through
> `SDL_SetWindowFullscreen(SDL_WINDOW_FULLSCREEN_DESKTOP)` instead of plume's native Cocoa
> `app->setFullScreen()` caused a **5–10 s freeze** on every toggle/launch. It was reverted. Native
> Cocoa fullscreen (the same path as the green window-button) is smooth, and once Bug 2b is fixed it
> does **not** squish. Keep `app->setFullScreen()`.

---

## 3. Input — "press and hold" accent popup while moving (WASD)

**Symptom:** holding a movement key (W/A/S/D, etc.) pops up the macOS accent/diacritic picker
(`à á â ä …` with number hints) in the top-left, as if typing into a text field.

**Why:** SDL keeps a Cocoa **text input context** (`NSTextInputContext`) active. With the system
"press and hold" feature on (`ApplePressAndHoldEnabled`, the default), holding a letter key in a text
context makes macOS show the accent picker instead of repeating the key. The game has no visible text
field, but the input context is still there, so movement keys trigger it.

**Fix** (`src/main/main.cpp`, very start of `main()`, before any window/text context exists): set the
per-app default to disable press-and-hold. This is the programmatic equivalent of
`defaults write -app <App> ApplePressAndHoldEnabled -bool false`; it keeps normal key **repeat** and
only suppresses the accent popup.
```cpp
#if defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>   // (near the top, under __APPLE__)
// ... at the top of main():
CFPreferencesSetAppValue(CFSTR("ApplePressAndHoldEnabled"), kCFBooleanFalse, kCFPreferencesCurrentApplication);
CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
#endif
```
CoreFoundation links transitively (via SDL/Metal); no extra `-framework` needed. Verify with
`defaults read <bundleid> ApplePressAndHoldEnabled` → `0` after launch. (An alternative, more
invasive fix is to call `SDL_StopTextInput()` whenever not in a UI text field, but the per-app
default is simpler and bulletproof.)

## 4. App icon — grey box → Liquid Glass

**Symptom:** on macOS 26 (Tahoe) the Dock/Finder icon showed a **grey rounded tile** around the
artwork.

**Why:** the source icon was a blue **circle on a transparent background**. Tahoe places every app
icon on its default tile and reveals it through the transparent corners → "grey box."

**Fix:** use an **Icon Composer `.icon`** package (authored in Icon Composer, which ships with
Xcode 26) and compile it with `actool`. This is the current, supported way to ship a Liquid Glass
icon, and it slots into the existing CMake/Ninja build — **no Xcode project needed**.

`actool` (run via `xcrun`) takes the `.icon` and emits everything:
- `Assets.car` — compiled catalog with the Liquid Glass icon (macOS 26+)
- `appicon.icns` — a flattened fallback it auto-generates (older macOS)
- a partial Info.plist (we set the keys ourselves instead of consuming it)

`.github/macos/apple_bundle.cmake` now does (replacing the old `iconutil` block):
```cmake
xcrun actool icons/appicon.icon \
  --compile <dir> --app-icon appicon \
  --output-partial-info-plist <plist> \
  --platform macosx --target-device mac \
  --minimum-deployment-target ${CMAKE_OSX_DEPLOYMENT_TARGET} \
  --errors --warnings
```
Both `Assets.car` and `appicon.icns` are copied into `Contents/Resources/`. `Info.plist.in` sets
`CFBundleIconName` = `appicon` (and `CFBundleIconFile` = `appicon` for the fallback).

> Requires **full Xcode** installed (for `actool`). If only Command Line Tools are present, fall back
> to a full-bleed (edge-to-edge, opaque) PNG → `iconutil` `.icns`; that also removes the grey box,
> just without the Liquid Glass material.
>
> **Icon caching:** macOS caches Dock/Finder icons aggressively. If a rebuilt icon doesn't update,
> log out/in, or `sudo rm -rf /Library/Caches/com.apple.iconservices.store && killall Dock Finder`.

---

## 5. Crash on quit — Metal over-release (the big one)

**Symptom:** every quit triggered the macOS "quit unexpectedly" dialog. Crash report: `SIGSEGV` on
the **"RT64 Workload"** thread in `objc_release` ← `AutoreleasePoolPage::releaseUntil` ←
`objc_autoreleasePoolPop`, while the main thread waits in `ultramodern::join_event_threads()`.

**Root cause:** in plume's Metal backend (`rt64/src/contrib/plume/plume_metal.cpp`), several Metal
objects are created with **autoreleasing (+0) factory methods** but then **explicitly `release()`d
without a balancing `retain()`**. That drops the refcount to zero early; the autorelease pool's
*deferred* release then runs on freed memory when the pool drains on quit → use-after-free. The
compute and render encoders right next to them already did this correctly (`retain()` after
creation) — four siblings just missed it.

**The four fixes** (each: add `->retain()` right after creation, matching the working encoders):

| Object (driver class seen in zombie log)        | Factory call                               | Function |
|--------------------------------------------------|--------------------------------------------|----------|
| Blit encoder (`AGXG16XFamilyBlitContext`)        | `blitCommandEncoder()`                     | `MetalCommandList::checkActiveBlitEncoder()` |
| Resolve compute encoder                          | `computeCommandEncoder()`                  | `MetalCommandList::checkActiveResolveTextureComputeEncoder()` |
| Command buffer (`AGXG16XFamilyCommandBuffer`)    | `commandBufferWithUnretainedReferences()`  | `MetalCommandList::begin()` |
| Texture descriptor (`MTLTextureDescriptorInternal`) | `TextureDescriptor::textureBufferDescriptor()` | `MetalBufferFormattedView` ctor |

**metal-cpp ownership rule (the general lesson):** factory accessors like `xxxDescriptor(...)`,
`commandBuffer()`, `*CommandEncoder()`, `NS::String::string()` return **autoreleased (+0)** — you do
**not** own them; never `release()` them unless you first `retain()`. Only `alloc()->init()` and
`newXxx()` return **owned (+1)** objects you must release. Auditing rule: every `->release()` on a
metal-cpp object must pair with a preceding `alloc/init`, `newXxx`, or an explicit `retain()`.

> A `Application::end()` teardown-reorder (stop queue threads before freeing render resources) was
> tried as a hypothesis and **reverted** — it's harmless but unnecessary; the over-releases were the
> real bug, and the corruption pre-dated shutdown.

This is an **upstream RT64/plume bug**, not specific to this fork — worth contributing back.

---

## 6. macOS debugging playbook (how the crash was actually found)

Reusable recipe for these "crash deep in `objc_release` at shutdown" problems:

1. **Reproduce a clean shutdown from the CLI.** SDL converts `SIGTERM`/`SIGINT` into `SDL_QUIT`
   (→ `ultramodern::quit()`), so you can trigger the real quit path without the GUI:
   ```bash
   "<App>.app/Contents/MacOS/<App>" & P=$!; sleep 10; kill -TERM $P
   ```
2. **NSZombie is the winner for over-releases.** It stops freed objects from being reused and logs
   the **exact class** on the extra release:
   ```bash
   NSZombieEnabled=YES NSDeallocateZombies=NO "<App>.app/Contents/MacOS/<App>" 2>&1 | tee /tmp/z.log
   # then quit; grep for:  *** -[CLASS release]: message sent to deallocated instance
   ```
   Fix the named class, rebuild, repeat — each fix surfaces the next dangling object until clean.
3. **lldb needs the hardened-runtime signature relaxed.** The build signs with `--options=runtime`,
   which blocks debugger attach ("Not allowed to attach"). Re-sign the binary with a
   `get-task-allow` entitlement first:
   ```bash
   printf '<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>com.apple.security.get-task-allow</key><true/></dict></plist>' > /tmp/dbg.entitlements
   codesign -f -s - --entitlements /tmp/dbg.entitlements "<binary>"
   lldb -b -k "bt" -k "register read x0" -k "quit" -o run -- "<binary>"   # send SIGTERM from a side process to crash it
   ```
   Restore the normal signature afterward (or just rebuild).
4. **Crash reports are deduped.** macOS suppresses repeated `.ips` reports with the same signature,
   so "no new crash report" is not proof of a fix — confirm with NSZombie (0 messages) and a clean
   exit code (`0`).
5. **`MallocStackLogging` lite mode was insufficient** here (it only showed reused VM regions, not
   the object's own alloc/free). NSZombie was the decisive tool.

---

## 7. File-by-file change summary

Main repo:
- `CMakeLists.txt` — SDL2 include dirs (both `/opt/homebrew/include` and `.../include/SDL2`).
- `src/main/main.cpp` — `SDL_WINDOW_ALLOW_HIGHDPI` on the window; disable `ApplePressAndHoldEnabled`
  at `main()` start (accent-popup fix, §3).
- `.github/macos/apple_bundle.cmake` — `actool` icon pipeline (replaces `iconutil`).
- `.github/macos/Info.plist.in` — `CFBundleIconName` / `CFBundleIconFile` = `appicon`.
- `icons/appicon.icon/` — the Icon Composer package (artwork authored separately).

Submodule `RecompFrontend`:
- `recompui/src/base/ui_state.cpp` — mouse point→pixel scaling; `SDL_WINDOWEVENT` no longer
  overrides UI dimensions.

Submodule `rt64`:
- `CMakeLists.txt` — Homebrew SDL2 on Apple; `PLUME_APPLE_RETINA_ENABLED ON`.

Sub-submodule `rt64/src/contrib/plume`:
- `CMakeLists.txt` — force `PLUME_APPLE_RETINA_ENABLED ON` on Apple.
- `plume_metal.cpp` — **four `->retain()` fixes** for the over-released Metal objects (§5).

---

## 8. Applying this to another N64Recomp-based app

The Retina bugs and the quit crash live in **shared code** (`RecompFrontend/recompui`, `rt64/plume`),
so a sibling recomp app very likely needs the **same fixes**, subject to its submodule versions:

1. **Build:** apply the SDL2 dual-include-dir fix (§1) and the icon pipeline (§4). Replace the app
   target name (`BanjoRecompiled`) with that app's target.
2. **Retina:** add `SDL_WINDOW_ALLOW_HIGHDPI` + `PLUME_APPLE_RETINA_ENABLED`, then port the two
   `ui_state.cpp` fixes (mouse scaling, `SDL_WINDOWEVENT` handling). Watch for whether that app's
   recompui already differs.
3. **Accent popup:** port the one-liner `ApplePressAndHoldEnabled` disable at `main()` start (§3) —
   it's app-agnostic.
4. **Quit crash:** if `plume_metal.cpp` is at a similar revision, the four `retain()` sites apply
   directly. Otherwise, re-run the NSZombie recipe (§6) — the over-released class names tell you
   exactly which factory-method results need a `retain()`.

The fastest path for the sibling app is to diff its `plume_metal.cpp` / `ui_state.cpp` against this
project's and carry over the same hunks, then validate with the NSZombie + clean-quit test.
