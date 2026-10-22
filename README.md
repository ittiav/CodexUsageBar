# Codex Usage Bar

<img src="assets/icon.png" alt="Codex Usage Bar icon" width="96">

Current source version: **1.2.2 (build 5)**. See [更新说明 / Changelog](CHANGELOG.md) for changes and upgrade notes. GitHub Releases are versioned separately; check the release tag before downloading an archive.

An unofficial macOS utility that displays your remaining Codex quota at the top of the primary display. On displays with a camera notch, it automatically places the text immediately to the left of the notch with an 8-point gap; on other displays, it stays centered. Placement uses the display's reported safe area, so no model selection is needed, and updates when the display configuration changes. It shows a five-hour percentage and reset time, followed by a weekly percentage and reset time. The current interface uses Chinese labels.

The green percentages show the remaining quota for the five-hour and weekly windows. Click the text to refresh immediately or quit. The app refreshes every minute. If the service is temporarily unavailable, it marks the last successful values with `~` until their respective reset times.

The bar is visible only while Codex / Work (application identifier `com.openai.codex`, including the app named `ChatGPT.app`) is the frontmost application. Switching to another application hides it to avoid covering that application's menus; switching back shows it again. In addition to application-switch notifications, the app checks visibility every half second to recover from startup and activation timing changes. Quota refreshes continue in the background. This checks the active application, not individual window titles, and requires no Accessibility permission.

## 显示规则（1.2.2）

- 刘海屏：使用 macOS 报告的屏幕安全区域，将整条文字放在刘海左侧，预留 8 点间距；无需选择机型。无刘海屏继续在顶部居中显示。
- 仍显示在主屏幕；更换显示器或分辨率后自动重新定位。空间不足时文字保持单行并截断，避免伸进刘海区域。
- 仅当前台应用是 Codex / Work 时显示。判断依据是应用标识 `com.openai.codex`，不是窗口标题；同一应用内的其他窗口也适用。
- 切换到其他应用时隐藏，切回后恢复。应用切换通知之外，每 0.5 秒复核一次前台状态，避免启动或切换时机导致一直隐藏。用量数据仍每分钟刷新一次。
- 这是后台菜单栏工具，没有 Dock 图标或常规主窗口；在其他应用前台时双击启动，没有可见窗口属于正常行为。

## Requirements

- macOS 13 or later.
- An executable Codex CLI at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`.
- A local Codex CLI session that can read account rate limits.

The app calls the local Codex CLI's `account/rateLimits/read` method. This interface may change with Codex updates.

## Build from source

Use Xcode 16 or a compatible version. Run these commands from the repository root:

```sh
xcodebuild -project CodexUsageBar.xcodeproj -scheme CodexUsageBar -configuration Release -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - build/Build/Products/Release/CodexUsageBar.app
```

The resulting app is at `build/Build/Products/Release/CodexUsageBar.app`. Copy it to `/Applications`, then open it from Finder.

The default build targets the current Mac's architecture. To build both Apple Silicon and Intel, add `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` to the `xcodebuild` command.

Release archives labelled `macos-universal` contain Intel and Apple Silicon binaries. They have an ad hoc signature and are not notarized by Apple. Build from this repository if you prefer to inspect or modify the app yourself. A source update on `main` does not replace an older GitHub Release archive.

## Install, upgrade, and troubleshoot

1. Quit the running Codex Usage Bar from its menu while Codex / Work is in front. If the bar is unavailable, use Activity Monitor to quit the process named `CodexUsageBar`.
2. Replace `/Applications/CodexUsageBar.app` with the newly built or downloaded app. Replacing files alone does not restart an already running process.
3. Open that exact copy from `/Applications`, then bring Codex / Work to the front. The bar should appear after the next visibility check; quota data may take longer to load. Switching to another application should hide it.

To verify the installed version, use Finder's Get Info or run:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/CodexUsageBar.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/CodexUsageBar.app/Contents/Info.plist
```

For this version the results are `1.2.2` and `5`. Finder folder timestamps can retain an earlier build time; the bundle version identifies the installed files, while quitting and reopening ensures the running process uses them. Avoid opening old copies from backup volumes or build folders.

If the bar says quota is temporarily unreadable, check the Codex CLI path and sign-in listed under Requirements. This is a data-read failure, separate from the foreground-only visibility rule.

## Start at login

Copy `LaunchAgents/local.codex.usagebar.login.plist` to `~/Library/LaunchAgents/`, then sign out and back in to macOS. The configuration points to `/Applications/CodexUsageBar.app`. Choosing Quit from the menu bar text ends only the current run.

## Privacy and data

The app contains no embedded tokens, account details, or analytics service and does not log credentials. It launches the local Codex CLI, which uses your existing sign-in to obtain quota data. The app caches only the last successfully read percentages, reset times, and read time in the current user's app preferences so it can show marked stale values during a temporary service failure.

This project is not affiliated with OpenAI and is not an official Codex app.

## License

MIT. See [LICENSE](LICENSE).
