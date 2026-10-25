# Codex Usage Bar

[简体中文](README.zh-CN.md) · [Changelog](CHANGELOG.md) · [Security review](SECURITY_REVIEW.md) · [Privacy](PRIVACY_REVIEW.md)

<img src="assets/icon.png" alt="Codex Usage Bar icon" width="96">

**Version 1.3.0 (build 7)** is an unofficial macOS quota bar for Codex / Work and Claude desktop. It follows the frontmost desktop application and displays that service's remaining subscription quota and reset times.

- Codex / Work (`com.openai.codex`) in front: show Codex quota.
- Claude desktop (`com.anthropic.claudefordesktop`) in front: show Claude quota.
- Other apps in front: hide the bar. Browser tabs and individual windows within the same app are not distinguished.
- `5hrs` means the five-hour window; `W` means the weekly window. Green percentages show **remaining**, not consumed, quota. Menus and status messages currently use Chinese.
- Each service has separate cached values, errors, and in-flight requests, so a late response cannot replace another service's display.

On notched displays, the bar sits immediately to the left of the notch with an 8-point gap. On other displays it stays centered at the top of the primary display. It repositions after display changes and recovers across Spaces, full-screen transitions, wake, and activation. Long text is truncated to fit.

## Download and install

Download the app, source, and checksums from [Release v1.3.0](https://github.com/ittiav/CodexUsageBar/releases/tag/v1.3.0). The `macos-universal` app contains Apple Silicon and Intel architectures and requires **macOS 13 or later**.

1. Quit the old `CodexUsageBar` process before replacing the app. If its menu is unavailable, quit that process in Activity Monitor.
2. Unzip the app and replace `/Applications/CodexUsageBar.app`.
3. Open that exact copy, then bring Codex / Work or Claude desktop to the front. This utility has no Dock icon or regular main window; launching it while another app is active can appear to do nothing.

Replacing files does not restart an existing process. Finder folder dates can retain an older time. Confirm the installed version with Finder's Get Info or:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/CodexUsageBar.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/CodexUsageBar.app/Contents/Info.plist
```

The results for this release are `1.3.0` and `7`. The app is **ad hoc signed, not notarized by Apple**. After downloading both ZIPs and `SHA256SUMS.txt` into the same directory, verify them with:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

## Codex setup

Codex requires a signed-in local CLI at `/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex`. The app calls its `account/rateLimits/read` method over local standard input/output; that interface may change with Codex updates. Credentials stay with the installed CLI and are not bundled in this utility.

## Connect Claude Pro / Max

1. Open the bar's menu and select **连接 Claude…** (Connect Claude), from either service's bar.
2. Sign in at `https://claude.ai/settings/usage` in the connection window. Use the same account as Claude desktop; its existing sign-in is not automatically imported. Claude Code CLI is not required.
3. Click the native **读取额度** (Read quota) button at the top of the window. If there are multiple workspaces, choose the one used by Claude desktop.
4. Wait for the connection confirmation, close the connection window, and bring Claude desktop to the front.

The bar reads the five-hour and all-model weekly subscription limits where available. Missing windows show unavailable data, never a fabricated zero or full quota. This does not cover API billing, third-party credits, or per-model weekly limits. Changes to the desktop account are not detected automatically: disconnect and reconnect to select the same account here.

**断开 Claude 连接** (Disconnect Claude) clears this app's WebKit session, workspace selection, and Claude quota cache. It does not sign out the desktop app or other browsers. See [Privacy](PRIVACY_REVIEW.md) for the local data that a Claude connection stores.

### Compatibility limits

Claude data is read from its website's **private, unversioned** `/api/organizations` and `/api/organizations/{id}/usage` endpoints. This is not a supported public subscription-quota API, and future site changes can break it. Sign-in challenges must be completed by the user. Some login providers may reject embedded browsers; this build does not bypass those restrictions. Unknown main-frame authentication redirects are blocked rather than silently trusted.

## Refresh and troubleshooting

- Normal refreshes occur about once per minute. After Claude has first been used, its checks continue in the background. Switching apps does not cause a request burst.
- On Claude HTTP 429 responses, requests pause for at least five minutes, or longer if requested by the service. Manual retries respect this cooldown.
- A `~` prefix marks cached values that have not been verified in this run, are old, or follow a failed request. Expired stale windows show pending update. Cached snapshots older than one day are ignored.
- If the bar is invisible, check that the matching **desktop app** is frontmost and that the expected process was reopened after upgrading.
- If Codex is unreadable, check the CLI path and sign-in. If Claude is unreadable, reopen its connection window, check the selected account/workspace, and click **读取额度**. Raw website error bodies are not shown in the bar.

## Build and checks

Use Xcode 16 or a compatible newer version:

```sh
xcodebuild -project CodexUsageBar.xcodeproj -scheme CodexUsageBar -configuration Release -derivedDataPath build 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
codesign --force --deep --sign - build/Build/Products/Release/CodexUsageBar.app
```

For a host-only build, omit `ARCHS` and `ONLY_ACTIVE_ARCH`. The app is created under `build/Build/Products/Release/`.

```sh
mkdir -p work
swiftc UsageModels.swift Tests/main.swift -o work/usage-model-tests
work/usage-model-tests
node Tests/claude-request.test.js
```

The checks cover quota parsing, cache separation, navigation boundaries, origin checks, redirects, workspace selection, data minimization, and error handling. Mock requests do not use an account or network. Authenticated Claude reading and both service displays were also verified locally on Apple Silicon. Intel hardware, every account/login provider, and all display/wake scenarios have not been fully tested.

## Start at login

Copy `LaunchAgents/local.codex.usagebar.login.plist` to `~/Library/LaunchAgents/`, then sign out and back in to macOS. It points to `/Applications/CodexUsageBar.app`. Choosing Quit ends the current run.

## Privacy and license

The app has no telemetry implementation or custom data-collection server. Claude authentication is stored by this app's own WebKit session, separately from the installed app bundle. Release archives exclude login state, quota caches, Git history, logs, and debugging symbols. Read the scoped [security review](SECURITY_REVIEW.md) and [privacy review](PRIVACY_REVIEW.md); these are not independent certifications.

Unofficial; not affiliated with OpenAI or Anthropic. Licensed under [MIT](LICENSE).
