# Privacy review — v1.2.2

Reviewed on 2026-10-22. This is a focused inspection of the current source snapshot and the v1.2.2 release archives, not a certification or a complete security audit.

## Source behavior

- No embedded account credentials, API keys, tokens, personal email addresses, user-specific home-directory paths, or analytics endpoints were found in the tracked source and resources.
- Visibility uses the frontmost application's bundle identifier and hidden state. The app does not read window titles, record application-switch history, or request Accessibility access.
- Quota retrieval starts the separately installed Codex CLI over local standard input/output. The app does not bundle that CLI or its sign-in files. The CLI uses the current user's existing authentication and may communicate with its service; this review does not audit the CLI, its network traffic, or the service.
- Cached quota percentages, reset timestamps, and the successful read time are stored in the current user's local app preferences. They remain on that user's machine and are not included in a release archive.
- Service error messages can appear locally in the bar's tooltip. The app has no credential logging or telemetry implementation.

## Packaged files

- The universal app archive contains only the executable, app Info.plist, icon, package marker, and ad hoc signature files.
- The source archive is generated from the release commit with `git archive`; it includes tracked project files and documentation, without Git history or working-directory extras.
- Login helpers, GitHub CLI files, authentication configuration, local usage preferences, build logs, caches, and debugging symbols are excluded from both archives.
- ZIP entries omit extended attributes, resource forks, local owner identifiers, and Finder metadata. The app uses an ad hoc signature, which does not embed a personal Developer ID certificate.
- Standard SDK, Xcode, and build-OS version metadata remains in the app's Info.plist; it does not identify an account, machine name, or home directory.
- The README icon's EXIF contained image dimensions only. That optional metadata was removed without changing its compressed pixel data. The app icon's embedded images were also inspected.

## Checks performed

- Reviewed the Swift source, project configuration, launch-at-login plist, documentation, image metadata, and final archive member lists.
- Scanned file contents and executable bytes for common credential formats, private keys, JWTs, personal email addresses, and user-specific home-directory paths. No matches were found in the published snapshot or final packages.
- Inspected the final package manifests to exclude authentication files, local settings, debugging symbols, and build output outside the app itself.
- Built both `arm64` and `x86_64`, removed debugging/local symbols from the packaged executable, and verified its ad hoc signature. SHA-256 checksums accompany the app and source ZIPs.

These checks cover the release artifacts and current tracked snapshot. They do not prove that arbitrary secrets cannot evade pattern detection, audit repository history or previous releases, or replace runtime and cross-device testing. Intel hardware and all display/window configurations have not been fully tested.
