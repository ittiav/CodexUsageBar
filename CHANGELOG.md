# Changelog

## 1.2.3 (build 6) — 2026-10-23

- Allow the quota panel to accompany full-screen applications as an auxiliary window.
- Restore the panel when Codex becomes active, the active Space changes, the Mac wakes, or the user session becomes active again.
- Recheck whether the panel belongs to the active Space instead of treating `isVisible` alone as proof that it is currently on screen. Foreground-only visibility and notch avoidance remain unchanged.

### Upgrade and validation

- Quit the previous process before replacing the app, then reopen it. The installed version is **1.2.3 (build 6)**.
- The universal archive supports Apple Silicon and Intel on macOS 13 or later, is ad hoc signed, and is not notarized by Apple.
- On the affected Apple Silicon Mac, the old process was running while its panel was absent from the current screen. After installing this fix, the panel was confirmed on screen with Codex in the foreground. Both architectures compile successfully; all wake, full-screen, multi-display, and Intel hardware scenarios have not been fully tested.
- Source and package privacy checks are documented in [Privacy review](PRIVACY_REVIEW.md). App and source ZIPs include SHA-256 checksums.

## 1.2.2 (build 5) — 2026-10-22

### Display placement

- Fix the quota bar being obscured by the camera housing on MacBook displays with a notch.
- Use the display's reported safe area to place the entire bar to the left of the notch with an 8-point gap, without a model list or manual model selection.
- Keep top-center placement on displays without a notch. The bar remains on the primary display and repositions when the display configuration changes.
- Keep long titles on one line and truncate them to fit the available area.

### Foreground visibility and recovery

- Show the bar only while Codex / Work (`com.openai.codex`, including the app installed as `ChatGPT.app`) is the frontmost application and is not hidden, avoiding overlap with other applications' menus.
- Identify the active application by its bundle identifier. No window titles are read, and Accessibility permission is not required. Other windows belonging to the same application also qualify.
- Hide the bar when switching away and restore it when switching back. Quota refreshes continue once per minute in the background.
- Recheck visibility every half second in addition to application-switch notifications, recovering from startup and activation timing that could otherwise leave the bar hidden.

### Upgrade notes

1. Quit the previous process before replacing `/Applications/CodexUsageBar.app`. If the bar is unavailable, quit `CodexUsageBar` in Activity Monitor.
2. Open the replaced app and bring Codex / Work to the front. This background utility has no regular main window or Dock icon; launching it while another application is active can appear to do nothing.
3. Verify **1.2.2 (build 5)** in the installed app's bundle metadata. Finder folder timestamps can retain an older date and do not identify the running version.

The existing login launch configuration continues to use the same installation path. Five-hour and weekly quota calculations, reset times, cached values, and the once-per-minute refresh interval retain their existing behavior.

### Release and validation

- The macOS app archive contains both Apple Silicon (`arm64`) and Intel (`x86_64`) executables in one universal binary and requires macOS 13 or later.
- The app is ad hoc signed and has not been notarized by Apple. A source archive and SHA-256 checksums are provided alongside the app.
- Both architectures compile successfully, and the packaged app passes signature verification. Display visibility was confirmed on an Apple Silicon Mac; Intel hardware, displays without a notch, multiple displays, and every application-switch scenario have not been fully tested.
- See [Privacy review](PRIVACY_REVIEW.md) for the scope and limits of the source and release-package inspection.
