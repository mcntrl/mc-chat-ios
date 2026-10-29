# Mission Control Chat (MIS-103)

White-labelled Element X iOS for the Mission Control team. Upstream: element-hq/element-x-ios (remote `upstream`),
based on release/26.10.8. AGPL-3.0, as upstream.

Everything MC-specific is kept small so rebases stay easy:

| What | Where |
|---|---|
| Name, bundle ID `com.wearemissioncontrol.chat`, app group | `app.yml` (team ID comes from CI) |
| Homeserver pinned to wearemissioncontrol.com, no server picker, no sign-up, no QR, legal links, push gateway | `ElementX/Sources/AppHooks/Hooks/MissionControlHooks.swift` (+ 1 line in `AuthenticationStartScreenViewModel.swift`) |
| MC orange accent | `MissionControlCompoundHook` (same file) + `colors/accent-color`, `colors/background-color` |
| Icon | `ElementX/Resources/AppIcon.icon/Assets/AppIcon.png` (from `mark-orange-on-ink.svg`) |
| Element's Sentry/PostHog/rageshake/MapTiler keys removed | `Components/Secrets/Secrets.swift` |
| Element-only entitlements removed (associated domains, Element Classic groups, notification filtering) | `ElementX/SupportingFiles/target.yml`, `NSE/SupportingFiles/target.yml` |
| CI: archive and TestFlight upload | `.github/workflows/mc-testflight.yml` (upstream workflows removed) |

Push: Sygnal on missionserver (127.0.0.1:5000, shared with Rocket Android, MIS-87). App IDs
`com.wearemissioncontrol.chat.ios.prod` (TestFlight, production APNs) and `.ios.dev` (debug, sandbox).

Rebase: `git fetch upstream --tags && git rebase release/<new>` and resolve the files above.
