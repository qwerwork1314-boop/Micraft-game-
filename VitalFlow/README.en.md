# VitalFlow · Native iPhone & Apple Watch wellness app

VitalFlow is a native **Swift / SwiftUI** app for iPhone and Apple Watch. It reads real data from Apple **HealthKit** and calculates personal, on-device **experimental wellness estimates**: recovery, stress, Body Battery, sleep quality and training readiness.

> ⚠️ **Important:** all VitalFlow scores are experimental wellness estimates. They are not clinically validated, are not medical measurements, and must not be used to diagnose, treat or prevent any condition.

- Languages in the app: **English**, **Traditional Chinese**, Simplified Chinese. The app follows your iPhone language; to choose a language just for VitalFlow open iPhone **Settings → Apps → VitalFlow → Language**.
- 繁體中文說明：[`README.zh-Hant.md`](README.zh-Hant.md) · 简体中文：[`README.md`](README.md)
- Formulas and limitations: [`docs/ALGORITHMS.md`](docs/ALGORITHMS.md) · Privacy policy: [`docs/PRIVACY.md`](docs/PRIVACY.md) · Tested / untested / planned: [`docs/FEATURE_STATUS.md`](docs/FEATURE_STATUS.md)
- The project lives in the `VitalFlow/` folder of this repository and is independent of the Blocklands game (no game files were changed).

---

## 1. Features

| Area | What it does |
|---|---|
| Today | Recovery, Body Battery, stress, training readiness, current and resting heart rate, HRV, last night's sleep, activity rings, calories, hydration, suggestions, interactive charts |
| Sleep | Stage timeline, duration, efficiency, consistency, wake-ups, sleeping heart rate and respiratory rate, day/week/month/year reports, suggestions; handles overlapping samples and multiple sources |
| Trends | 7-day / 30-day / 90-day / 1-year charts for HRV, resting HR, sleep, steps, energy, respiratory rate, blood oxygen, VO₂ max, weight, daylight and water |
| Coach | **AI coach on Apple Intelligence** (iOS 26+, iPhone 15 Pro or newer): runs on your iPhone, free, no API key, looks up your own sleep, heart, trend, workout and goal data before answering, plus a daily AI briefing on Today and “Ask Coach” on every score. On other iPhones a built-in assistant explains your trends. It never diagnoses or recommends medication. An optional external AI (Anthropic Claude) requires explicit consent and only receives rounded summary numbers |
| Garden | Daily goals (kept within healthy ranges), badges, weekly report, a virtual garden that grows with healthy habits, optional gentle reminders |
| Apple Watch | Score summary, heart rate, activity, water logging, workouts with live heart rate, complications, sync with iPhone |
| Widgets | Home screen (small/medium) and lock screen |

## 2. Ways to install

You do **not** need a Mac. GitHub's macOS computers build the app.

| | Free (Sideloadly) | Paid (TestFlight) |
|---|---|---|
| Cost | Free Apple ID | Apple Developer Program, US$99/year |
| Computer | Windows PC + USB cable | Any computer with a browser |
| Expires | **Every 7 days** (reinstall from the PC) | 90 days per build, updates any time |
| Apple Watch app & widgets | Probably not | Yes |
| Health data | Not tested with free signing | Yes |

### A. Free install with Sideloadly (Windows)

1. **Download the app file.** On GitHub open **Actions → VitalFlow unsigned IPA (free sideloading)** → the latest green run → **Artifacts** → `VitalFlow-unsigned-ipa` (you must be signed in). Unzip it. Use **`VitalFlow-iphone-only-unsigned.ipa`** first. (`VitalFlow-full-unsigned.ipa` also contains the Watch app and widgets but usually fails with a free Apple ID.)
2. **Install on Windows:** **iTunes** and **iCloud** from Apple's website (not the Microsoft Store versions), then **Sideloadly** from sideloadly.io.
3. Connect your iPhone with a USB cable and tap **Trust This Computer** on the iPhone.
4. Open Sideloadly, drag in the `.ipa`, enter your Apple ID and press **Start**. Enter your password and verification code only in Sideloadly — never in a chat or chatbot. A spare Apple ID is recommended.
5. On the iPhone: **Settings → General → VPN & Device Management** → tap your Apple ID → **Trust**.
6. On iOS 16 or later: **Settings → Privacy & Security → Developer Mode** → turn on and restart.
7. Open VitalFlow → **Connect Health**. Reinstall with Sideloadly every 7 days (your data stays).

If Health data doesn't appear, turn on **Settings → Demo mode** in VitalFlow to explore the app with clearly labelled sample data.

### B. TestFlight (paid Apple Developer account)

1. Join the **Apple Developer Program** at developer.apple.com/programs.
2. Pick a bundle prefix you own, e.g. `com.yourname.vitalflow` (called **PREFIX**). At developer.apple.com/account → **Identifiers**:
   - App Group: `group.PREFIX`
   - App IDs (explicit):

   | Bundle ID | Capabilities |
   |---|---|
   | `PREFIX` | HealthKit (+ Background Delivery), App Groups (`group.PREFIX`) |
   | `PREFIX.widgets` | App Groups |
   | `PREFIX.watchkitapp` | HealthKit, App Groups |
   | `PREFIX.watchkitapp.complications` | App Groups |

   - Note your 10-character **Team ID** (Membership page).
3. At appstoreconnect.apple.com: **My Apps → + → New App** (iOS, Bundle ID = PREFIX). Then **Users and Access → Integrations → App Store Connect API → Team Keys → +** with **Admin** access. Download `AuthKey_XXXX.p8` (only once) and note the **Key ID** and **Issuer ID**.
4. Convert the key to text. Windows PowerShell:
   `[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8")) | Set-Clipboard`
5. GitHub repository → **Settings → Secrets and variables → Actions → New repository secret**:
   `APPLE_TEAM_ID`, `VF_BUNDLE_PREFIX`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_BASE64`.
6. GitHub only shows the **Run workflow** button for workflows on the default branch. Merge branch `claude/vitalflow-health-app-fq5uk8` into `main` with a pull request first (it only adds the `VitalFlow/` folder and `vitalflow-*` workflows; the game is untouched).
7. **Actions → VitalFlow TestFlight → Run workflow**, enter a version such as `0.1.0`.
8. After 5–30 minutes the build appears in App Store Connect → **TestFlight**. Add yourself as an internal tester, install the **TestFlight** app on the iPhone and install VitalFlow. The Watch app installs on the paired Apple Watch.

🔐 No passwords, private keys or certificates are stored in the repository.

## 3. First launch

Accept the wellness disclaimer → **Connect Health** → choose the data to share. Scores need about **4 nights** of wearing Apple Watch to sleep before they appear; until then they show **“Not enough data”** instead of a made-up number.

## 4. Troubleshooting

- **No data at all** — open VitalFlow **Settings → Health connection**. It shows whether Health access was requested, how many samples it can read per data type, and the exact error. If it says *“This copy of VitalFlow can't use Apple Health”*, the free sideloaded install doesn't include the Health permission; use Demo mode or TestFlight.
- **AI coach not active** — needs iOS 26+, an iPhone that supports Apple Intelligence (iPhone 15 Pro or newer) and Apple Intelligence turned on in Settings → Apple Intelligence & Siri. The Coach screen says which requirement is missing.

- **All scores say “Not enough data”** — wear the watch to sleep for a few nights; check Health app → Profile → Apps → VitalFlow permissions. HealthKit doesn't tell apps which permissions were denied.
- **No sleep stages** — set up Sleep Focus / sleep tracking in the Health app and wear the watch in bed.
- **Blood oxygen or wrist temperature missing** — not available on every model or in every country; scores adjust and lower their confidence.
- **Sideloadly error** — copy the exact message and ask for help.

## 5. Project structure

```
VitalFlow/
├── project.yml              XcodeGen project definition (generates VitalFlow.xcodeproj in CI)
├── Packages/VitalFlowCore/  Platform-independent models, de-duplication, sleep merging, baselines, scores, assistant, garden (68 tests)
├── Shared/                  Code shared by iPhone, Watch and widgets; HealthKit service; String Catalog
├── iOS/  Watch/  Widgets/  WatchWidgets/  Tests/
├── scripts/                 Icon generator, localisation builder/checker
└── docs/
```

## 6. Verification status (honest)

- ✅ 68 VitalFlowCore unit tests pass on Linux and macOS (scores, missing data, duplicate records, midnight/DST boundaries, overlapping sleep sources).
- ✅ GitHub Actions on macOS: iPhone app (with embedded Watch app and both widget extensions) compiles, iPhone-simulator tests pass, watchOS app compiles, unsigned IPA builds.
- ❌ **Not yet tested on a real iPhone or Apple Watch.** HealthKit permissions, background updates, Watch sync, workouts, widgets and complications need checking on your devices.
