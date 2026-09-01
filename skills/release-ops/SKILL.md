---
name: release-ops
description: "Use when a spine-toolkit methodology skill (ops-checklist / feature-requirements / feature-estimation) resolves topic release ops for an Apple project — App Store / TestFlight review, push transport (APNs), crash reporting, Keychain-backed secure storage, transport security, VoiceOver/Dynamic Type accessibility specifics, and the release-review estimation buffer."
---

# Release Ops

The Apple-specific answers behind spine-toolkit's **release ops** topic: what actually backs
"distribution-channel review", "push-provider token", "assistive-technology labels", "secure
storage" and "platform fragmentation" when the platform is Apple's.

> **Related skills:**
> - `error-architecture` — crash-reporter wiring is a `Logger`/`ErrorMapper` concern at the composition root
> - `di-composition-root` — where a crash reporter, push delegate, or Keychain wrapper gets bootstrapped
> - `arch-swiftui-navigation`, `arch-coordinator` — where a Universal Link's parsed route lands (see `nav-deeplinks` for the parser itself)

## Distribution-channel review

- App Store Review Guidelines: no private API use, no undisclosed data collection, no App Tracking
  Transparency (ATT) prompt bypass, no payment flow outside In-App Purchase for digital goods.
- Calendar buffer: **+1–3 calendar days** typical for an established app with no guideline changes;
  **+3–7 calendar days** for a first submission, a guideline-adjacent feature (payments, health
  data, ATT), or a resubmission after rejection. Enterprise / internal (Apple Business Manager)
  distribution skips review entirely — 0 days.
- TestFlight builds are not store-reviewed for internal testing; external TestFlight groups get a
  lightweight review (usually same-day to 24h).

## Platform fragmentation

Apple's device/OS matrix is narrow relative to a fragmented ecosystem's — few hardware SKUs, a
fast OS-adoption curve, one UI toolkit family per surface. Default: **skip the fragmentation
delta**. Apply a small one (**+5%–10%**, not the +20%–30% a genuinely fragmented ecosystem needs)
only when the feature depends on a hardware capability that varies within the supported baseline
(Dynamic Island / ProMotion / LiDAR / Always-On display) and the project's `## Axes baseline`
spans devices that differ on it.

## Push transport

- APNs (Apple Push Notification service) is the only transport — no split to handle.
- Token registration: request authorization, register for remote notifications, hand the device
  token to the backend on `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`;
  handle `didFailToRegisterForRemoteNotificationsWithError:` as a Secondary error state, not a
  silent drop.
- Token rotation: a device token can change on OS reinstall or backup restore — refresh it on
  every cold launch, not once at first install.
- Silent push: `content-available: 1` payload, capped at 30s background execution; the delegate
  still fires while backgrounded or terminated-and-relaunched-by-the-OS, but not force-quit by
  the user.

## Crash reporting

Pick one: Xcode Organizer + `MetricKit` (no third-party SDK, dSYM upload via Xcode Cloud/App
Store Connect), or a vendor SDK (Crashlytics, Sentry, Bugsnag) when cross-referencing crashes
against release/analytics data in one dashboard matters more than avoiding a third-party binary.
Either way: verify dSYM/BCSymbolMap upload is wired into the CI release lane — a build shipped
without its symbols produces unsymbolicated, useless crash reports.

## Secure storage & transport

- Secrets (tokens, credentials) live in the Keychain, never `UserDefaults` — `UserDefaults` is an
  unencrypted plist on disk.
- App Transport Security (ATS) is on by default; a cleartext (`NSAllowsArbitraryLoads`) exception
  needs a documented reason in the ops checklist, not a blanket entry in `Info.plist`.
- Certificate pinning: pin the public key (SPKI hash) in the `URLSession` delegate's
  `urlSession(_:didReceive:completionHandler:)`, not the leaf certificate, so a CA-signed renewal
  doesn't break the pin.
- App Privacy report (App Store Connect's "App Privacy" nutrition label) must list every SDK's
  data collection — audit third-party SDKs for what they actually send, not what their docs claim.

## Accessibility specifics

- VoiceOver: `accessibilityLabel` / `accessibilityHint` on every interactive element; group
  decorative elements out of the VoiceOver rotor with `accessibilityElementsHidden`.
- Dynamic Type: support at minimum up to `.accessibility3`; test with
  `UIContentSizeCategory.accessibilityExtraExtraExtraLarge` — a layout that only handles `.large`
  is not Dynamic Type support.
- Touch targets: minimum **44×44pt** (Apple HIG), not just the visible glyph — pad the hit area
  on a compact icon button.
