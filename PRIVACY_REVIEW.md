# Privacy review — v1.3.1

[简体中文](PRIVACY_REVIEW.zh-CN.md) · [Security review](SECURITY_REVIEW.md)

Reviewed on **2026-10-27**, for the current source and v1.3.1 release archives. This focused review is not an independent certification or a complete security audit. The historical v1.2.3 review remains available at [its release tag](https://github.com/ittiav/CodexUsageBar/blob/v1.2.3/PRIVACY_REVIEW.md).

## Data used on the local Mac

| Data | Purpose and storage |
| --- | --- |
| Foreground application's bundle identifier and hidden state | Choose the visible provider. Window titles and an app-switch history are not read or recorded. |
| This quota panel’s window ID and on-screen flag | Queried locally from WindowServer to recover an invisible panel. Only this app’s window is requested; no pixels, other window titles, history, or persistent log are collected. No Screen Recording permission is requested. |
| Codex quota and reset timestamps | Read through the separately installed, signed-in Codex CLI. Authentication stays with that CLI; it may communicate with its service. |
| Claude login session | Created by the user's sign-in inside this app's separate WebKit window and retained in its local website-data store. No login cookies, OAuth tokens, or passwords are copied from other browsers, the desktop app, Keychain, or conversation files. |
| Claude workspace choices | Minimal IDs/names are presented for local selection. Only the selected workspace ID is saved in app preferences; workspace names are not logged or cached by native code. |
| Last successful quotas | Each service's used percentages, reset timestamps, and successful read time are cached separately in app preferences. Snapshots older than one day are ignored; quitting alone does not erase them. |
| Error state | Claude errors use fixed messages and HTTP status numbers, without raw server bodies. Codex CLI errors can appear in local tooltips. The app does not implement credential logging or telemetry. |

## Network and authentication boundary

Claude reading uses same-origin website requests to `/api/organizations` and `/api/organizations/{id}/usage` from `https://claude.ai`. The script runs in an isolated WebKit world, rejects request redirects, and returns only the needed quota fields and workspace selection information to Swift. Cookie values stay with WebKit rather than crossing the bridge. The app does not request conversations or send data to a custom collection server.

The sign-in page and its allowed authentication providers still have their own network behavior and privacy policies; the utility does not audit their traffic or the Codex CLI's internals. These website quota APIs are private and can change.

## Disconnect and account changes

**Disconnect Claude** clears this app's WebKit website data, selected workspace ID, and Claude quota cache. It does not sign out the desktop app or another browser and does not clear Codex preferences. New reads are blocked while cleanup completes. The utility cannot detect a different account selected inside Claude desktop, so reconnect with the matching account after changing it.

## Release contents and inspection

- The app ZIP contains only five app files: executable, Info.plist, icon, package marker, and ad hoc signature resources. It does not include local WebKit data or preferences.
- The source ZIP is produced from the release Git commit and excludes Git history and local working materials. `inputs/`, `work/`, and `outputs/` are explicitly ignored by Git.
- No login helpers, authentication configuration, account/session files, quota caches, build logs, or debugging symbols are packaged. ZIP metadata omits resource forks, extended attributes, local owner identifiers, and Finder metadata.
- Standard SDK, Xcode, and build-OS versions remain in Info.plist; they do not identify a user's account, host name, or home directory. Ad hoc signing does not embed a personal Developer ID certificate.
- The current source, resources, binary bytes, archive names, and extracted files are inspected for common credential patterns, private keys, personal home paths, email addresses, and unintended files. The synthetic URL-credential fixture in navigation tests is intentional, not personal data. No real embedded credentials or personal account data were identified within this inspection's scope.
- App signatures, both architectures, archive integrity, and SHA-256 checksums are checked. Uploaded asset digests are compared with local files before publication.

Scans cannot prove the absence of arbitrary secrets. This review covers the current release snapshot and packages, not all repository history, older releases, the full websites/CLIs, or every runtime/login scenario. See the [security review](SECURITY_REVIEW.md) for residual risks.
