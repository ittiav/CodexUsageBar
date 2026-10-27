# Security review — v1.3.1

[简体中文](SECURITY_REVIEW.zh-CN.md) · [Privacy review](PRIVACY_REVIEW.md)

Reviewed on **2026-10-27**. Scope: the current Swift source, embedded request script, Xcode project, launch plist, resources, tests, and final v1.3.1 app/source archives. This is a focused source and packaging review, not an independent audit, penetration test, notarization, or guarantee that every vulnerability has been found.

## 1.3.1 visibility recovery review

The release delta adds a main-thread check of this panel’s own WindowServer metadata. It requests only the panel window ID, examines its on-screen flag, and resets ordering if absent while a supported app is foreground. It does not capture pixels, inspect other window titles, persist window metadata, add network requests, or change authentication. If the query is unavailable, the existing AppKit visibility/Space checks remain in use. The affected user confirmed recovery; the original triggering event and all wake/Space combinations have not been reproduced. The existing Claude security controls below were retained and rechecked.

## Findings addressed before release

| Area | Finding and change |
| --- | --- |
| Embedded navigation | The development login view accepted arbitrary HTTPS main-frame destinations. The release limits embedded main-frame navigation to explicit Claude/authentication hosts, rejects insecure/local schemes and URL credentials, and sends user-clicked external HTTPS links to the default browser. Unknown automatic authentication redirects are blocked. HTTPS subframes remain allowed for the site's normal sign-in flow. |
| Script boundary | The reader previously ran in the page script world. It now runs in WebKit's isolated client world, checks the exact `https://claude.ai` origin, and uses same-origin credentials with no request redirects. Cookies are handled by WebKit and are not returned to native code. |
| Data minimization | The development bridge returned the whole usage response. The release passes only the selected workspace ID, the two quota windows' utilization/reset fields, and minimal workspace choices when selection is needed. Billing extras and unrelated response fields are excluded. |
| Workspace changes | A missing saved workspace could silently fall back to a different sole workspace. The release requires selection again instead. Desktop account changes still cannot be detected automatically; users must reconnect with the matching account. |
| Disconnect cleanup | New reads or connection attempts could race asynchronous website-data removal. The release blocks those actions during cleanup and invalidates outstanding callbacks before clearing the local session and cache. |
| Accidental publication | Repository ignore rules explicitly exclude `inputs/`, `work/`, and `outputs/`. Source packages come from the release Git commit; app packages come from a clean build, not an installed app with user data. |

No unresolved high-severity issue was identified within this review's scope. That statement is limited to the inspected implementation and checks; it is not a blanket safety assurance.

## Other controls inspected

- Native provider selection uses exact desktop bundle identifiers; it does not inspect window titles or app-switch history. Separate provider state prevents late responses from overwriting the other service's quota.
- Claude JSON parsing rejects nonnumeric, Boolean, nonfinite, and out-of-range percentages and invalid reset values. Missing windows stay unavailable. Cached Codex integer values remain readable.
- Requests are deduplicated and normally refreshed once per minute. Claude HTTP 429 responses impose at least a five-minute cooldown, including manual retries, and honor longer service delays.
- Raw Claude response/error bodies are not logged or displayed. Codex CLI errors may appear locally in tooltips. There is no custom telemetry or collection server.
- The utility runs the installed Codex executable directly, without shell interpolation. Codex authentication stays with that CLI. This review does not audit the separately installed CLI or the service.
- No existing browser/desktop cookies, Keychain credentials, or conversation files are read. Claude login happens in the utility's separate WebKit session. The user completes authentication and site challenges.

## Validation

- **36** model/navigation checks and **10** mocked request scenarios cover origin and redirect boundaries, navigation hosts/schemes, workspace selection, response minimization, percentage/reset validation, cache separation, missing fields, and errors. Mock tests make no network calls.
- Both `arm64` and `x86_64` Release architectures compile. The final packaged app is stripped of debugging/local symbols, ad hoc signed, and verified again after extraction.
- Real Claude Pro quota reading and the separate native Codex/Claude displays were checked locally on Apple Silicon. No real account values, emails, workspace IDs, or login state are used as committed test fixtures.
- The final archive manifests and contents are inspected for credentials, personal home paths, email addresses, private keys, caches, metadata, and unintended files. A synthetic URL-credential fixture in the navigation test is intentional and is not a real credential or email.
- GitHub asset sizes and SHA-256 digests are compared with the local files before public release.

## Residual risks and limits

Claude's website endpoints are private and unversioned; compatibility or rate-limit behavior can change. WebKit login state is sensitive local data: the app's process and websites in its allowed authentication flow must be trusted, and a compromised macOS user account is outside this review's protection. The app cannot prove that its Claude login matches the desktop app's current account. Embedded authentication providers may reject the flow; restrictions are not bypassed. Intel hardware, every login provider, all quota/account types, and all display/wake scenarios have not been fully tested. The app is ad hoc signed and **not notarized by Apple**.

The scan covers this release snapshot and its archives, not all repository history, previous releases, arbitrary future builds, or the internals of Claude, Codex, and macOS. Pattern scans cannot prove the absence of arbitrary secrets.
