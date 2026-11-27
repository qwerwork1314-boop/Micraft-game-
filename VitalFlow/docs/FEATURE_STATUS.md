# VitalFlow 功能状态 / Feature status

图例 / Legend:
- ✅ **已实现并已自动测试** — implemented and covered by automated tests that were run and passed
- 🟢 **已实现，已编译** — implemented; compiles in CI (macOS runner) but has no automated behavioural test
- 🟡 **已实现，未测试** — implemented, not yet verified beyond compilation
- 📱 **需真机验证** — requires a real iPhone / Apple Watch; **no real-device testing has been performed**
- 📝 **计划中** — planned, not implemented

> 真机测试状态 / Real-device testing: **未进行 / not performed.** 本项目由云端环境开发，没有 iPhone 或 Apple Watch。

## Core algorithms (VitalFlowCore, Swift package)

| Feature | Status |
|---|---|
| Discrete-sample de-duplication (UUID + cross-source) | ✅ |
| Cumulative multi-source merge (HealthKit-style priority) | ✅ |
| Day boundaries: midnight split, DST 23 h/25 h, month/year/leap-day | ✅ |
| Sleep merge: overlapping samples, multiple sources, gap filling, duplicates, naps, interruptions | ✅ |
| Sleep consistency (midnight wrap-safe) | ✅ |
| Sleep score | ✅ |
| Robust 28-day baselines (min 4 days, today excluded) | ✅ |
| Recovery score + “not enough data” + confidence | ✅ |
| Stress estimate (workout/active-hour exclusion, future hours ignored) | ✅ |
| Body Battery | ✅ |
| Training load (TRIMP), ACWR, readiness, activity/recovery balance | ✅ |
| Weekly trends | ✅ |
| Goals (healthy-range clamping), garden, achievements, weekly report | ✅ |
| On-device assistant (EN / 简 / 繁 intents, medical refusal) | ✅ |
| Minimised external-AI payload (no identifiers/timestamps) | ✅ |
| Deterministic, labelled demo data | ✅ |

63 tests (incl. a 365-day performance test), run on Linux (Swift 6.0) in the development container — all passing. CI also runs them on Linux and macOS.

## iPhone app

| Feature | Status |
|---|---|
| HealthKit authorization, reads of all requested types, water write | 🟢 📱 |
| HealthKit ↔ core type/unit/sleep-stage mapping | ✅ (simulator unit tests in CI) |
| Background delivery + observer queries | 🟡 📱 |
| Dashboard (scores, heart, sleep, rings, calories, hydration, stress & battery charts, suggestions) | 🟢 |
| Score detail screens with components & confidence | 🟢 |
| Sleep page: stage timeline, day/week/month/year, consistency, sleep HR, resp. rate, suggestions | 🟢 |
| Trends page with interactive charts | 🟢 |
| Coach (on-device) + chat history in SwiftData | 🟢 |
| Optional external AI (consent, Keychain key, minimised payload) | 🟢 — not tested against the live API |
| Garden, goals editor, badges, weekly report | 🟢 |
| Gentle reminders (local notifications) | 🟡 📱 |
| Settings, demo mode, privacy policy, delete-all-data | 🟢 |
| Onboarding | 🟢 |
| Widgets (home + lock screen) | 🟢 📱 |
| Localization EN / zh-Hans / zh-Hant (272 strings, CI coverage check) | ✅ coverage check |
| Light/dark mode, Dynamic Type, VoiceOver labels | 🟡 (not audited on device) |
| Liquid Glass on iOS 26 (material fallback earlier) | 🟡 |

## Apple Watch

| Feature | Status |
|---|---|
| Summary (recovery / battery / stress from iPhone) | 🟢 📱 |
| Heart rate (latest recorded, anchored query — no continuous polling) | 🟢 📱 |
| Activity progress, hydration logging | 🟢 📱 |
| Workout tracking with live heart rate (HKWorkoutSession, user-started only) | 🟢 📱 |
| Complications (circular, corner, rectangular, inline) | 🟢 📱 |
| WatchConnectivity sync (application context + user info) | 🟢 📱 |

## Build & distribution

| Feature | Status |
|---|---|
| XcodeGen project (iOS, watchOS, 2 widget extensions, unit tests) | 🟢 |
| HealthKit / App Group entitlements, privacy usage strings (localized) | 🟢 |
| GitHub Actions CI (Linux core tests, macOS build + simulator tests) | see Actions tab |
| TestFlight workflow (API-key automatic signing, upload) | 🟡 — needs your Apple Developer secrets; not yet run |

## Planned / not implemented

| Item | Status |
|---|---|
| Per-day historical score browsing (scores for past days) | 📝 |
| Export of reports (PDF/CSV) | 📝 |
| HealthKit `HKAnchoredObjectQuery`-based incremental sync cache (currently full re-query) | 📝 |
| Siri / App Intents shortcuts, Live Activity during workouts | 📝 |
| On-device LLM (Apple Foundation Models) for free-form assistant answers | 📝 |
| Snapshot/UI tests and accessibility audit | 📝 |
