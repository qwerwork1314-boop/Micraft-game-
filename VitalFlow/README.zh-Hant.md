# VitalFlow · 原生 Apple Watch 健康與健身 App

VitalFlow 是一款用 **Swift / SwiftUI** 編寫的原生 iPhone + Apple Watch 應用，基於 Apple 官方 **HealthKit** 讀取真實健康資料，在裝置端計算個性化的恢復、壓力、身體電量、睡眠與訓練準備度等**實驗性健康估算**。

> ⚠️ **重要聲明**：VitalFlow 的所有評分都是實驗性健康估算，未經臨床驗證，不是醫學測量，也不能用於診斷、治療或預防任何疾病。

- 本專案放在儲存庫的 `VitalFlow/` 目錄中，與儲存庫裡原有的 Blocklands 遊戲完全獨立（遊戲檔案沒有被修改）。如何把它搬到獨立儲存庫見 [第 9 節](#9-遷移到獨立的-github-儲存庫)。
- English guide: [`README.en.md`](README.en.md) · 简体中文：[`README.md`](README.md)
- 演算法公式與限制：[`docs/ALGORITHMS.md`](docs/ALGORITHMS.md)
- 隱私政策：[`docs/PRIVACY.md`](docs/PRIVACY.md)
- 功能狀態（已實現 / 已測試 / 未測試 / 計劃中）：[`docs/FEATURE_STATUS.md`](docs/FEATURE_STATUS.md)

---

## 1. 功能概覽

| 模組 | 內容 |
|---|---|
| 今日儀表盤 | 恢復分數、身體電量、壓力、訓練準備度、當前/靜息心率、HRV、昨晚睡眠、活動圓環、卡路里、飲水進度、個性化建議、可互動圖表 |
| 睡眠 | 睡眠階段時間線、總時長、效率、規律性、中途醒來、睡眠心率、睡眠呼吸頻率、日/周/月/年報告、睡眠建議；正確處理重疊樣本與多資料來源 |
| 趨勢 | HRV、靜息心率、睡眠、步數、活動能量、呼吸頻率、血氧、最大攝氧量、體重、日照、飲水的 7 天/30 天/90 天/1 年圖表，本週與上週對比 |
| 教練（AI 助手） | 完全在裝置端執行的對話助手，可回答「為什麼我今天恢復分數較低？」等問題；可選的外部 AI（Anthropic Claude）需明確知情同意，僅傳送最少的彙總數字 |
| 花園（遊戲化） | 每日目標、徽章、每週報告、可自定義目標（限制在健康範圍內）、會隨健康習慣成長的虛擬花園、可選的溫和提醒 |
| Apple Watch | 恢復/身體電量/壓力摘要、心率、活動進度、飲水記錄、體能訓練（含訓練中的實時心率）、錶盤複雜功能、與 iPhone 同步 |
| 小工具 | 主螢幕小/中尺寸，鎖定螢幕圓形/矩形/行內 |
| 其他 | 簡體中文、繁體中文、英文；淺色/深色模式；動態字型；VoiceOver 標籤；iOS 26 上使用 Liquid Glass（更早版本自動回退為毛玻璃材質） |

## 2. 技術架構

```
VitalFlow/
├── project.yml                 # XcodeGen 工程定義（生成 VitalFlow.xcodeproj）
├── Config/Base.xcconfig        # Bundle ID 字首、版本號（無任何金鑰）
├── Packages/VitalFlowCore/     # 純 Swift 套件：模型、去重、睡眠合併、基線、全部評分演算法、助手、遊戲化、示範資料
│   └── Tests/                  # 63 個單元測試（缺失資料、重複記錄、日期邊界、夏令時等）
├── Shared/Common/              # iPhone/Watch/小工具共用：品牌色、快照、Localizable.xcstrings
├── Shared/Health/              # HealthKit 封裝 + 資料倉儲（真實資料 / 示範資料）
├── iOS/                        # iPhone App（SwiftUI + Swift Charts + SwiftData）
├── Watch/                      # watchOS App（HKWorkoutSession、WatchConnectivity）
├── Widgets/                    # iOS WidgetKit 小工具
├── WatchWidgets/               # Apple Watch 錶盤複雜功能（WidgetKit）
├── Tests/                      # iOS 單元測試（HealthKit 對映等）
├── scripts/                    # 圖示生成、多語言字串生成與檢查
└── docs/                       # 演算法、隱私政策、功能狀態
```

- **最低系統**：iOS 17、watchOS 10（SwiftData、`timeInDaylight` 等需要）。在 iOS 26 / watchOS 26 上自動啟用 Liquid Glass 等新特性。
- **資料流**：HealthKit → `HealthKitDataProvider`（統計查詢自動按來源優先順序去重）→ `VitalFlowCore`（離散樣本去重、睡眠合併、基線、評分）→ SwiftUI。結果寫入 App Group 快照供小工具使用，並透過 `WCSession.updateApplicationContext` 發給手錶。
- **示範模式**：在「設定」中單獨開啟，所有頁面都會顯示醒目的「示範資料」標籤；示範資料絕不會寫入「健康」，也不會與真實資料混合。生產路徑從不生成隨機健康數值。
- **電池與背景**：手錶上只在使用者主動開始體能訓練時執行 `HKWorkoutSession`，結束即停止；平時只讀取 watchOS 已記錄的心率（`HKAnchoredObjectQuery`），不會為了持續採集感測器而保持假訓練會話。iPhone 使用 HealthKit 背景推送（每小時，由系統控制）。

## 3. 你需要準備什麼

| 專案 | 說明 |
|---|---|
| GitHub 帳號 | 用於存放程式碼和執行 GitHub Actions（macOS 執行器負責編譯）。公開儲存庫的 macOS 執行器免費；私有儲存庫會按 macOS 分鐘數（10 倍係數）消耗額度。 |
| Apple ID + iPhone（+ Apple Watch） | 必需。 |
| **Apple Developer Program 會員（99 美元/年）** | **沒有 Mac 時必需**。HealthKit 能力、App Group、TestFlight 分發都需要付費開發者帳號。免費帳號只能用 Xcode 直接安裝到裝置，而這需要 Mac。 |
| App Store Connect API 金鑰 | 讓 GitHub Actions 自動簽名並上傳到 TestFlight。 |

不需要 Mac：編譯、簽名、上傳全部在 GitHub 的 macOS 雲端執行器上完成；安裝透過 iPhone 上的 **TestFlight** App。

## 4. 第一步：確認 CI 編譯通過

1. 開啟儲存庫頁面 → **Actions** → **VitalFlow CI**。每次推送 `VitalFlow/` 下的改動都會自動執行：
   - `Core algorithms (Linux)`：執行 VitalFlowCore 的全部單元測試，並檢查三種語言的翻譯是否齊全。
   - `iOS + watchOS build & test (macOS)`：用 XcodeGen 生成工程，編譯 iPhone App（含內嵌的 Watch App 和小工具），在 iPhone 模擬器中執行單元測試，再單獨編譯 watchOS App。
2. 執行結束後，可在該次執行頁面底部的 **Artifacts** 下載 `VitalFlow-xcodeproj`（生成好的 Xcode 工程）和測試結果。

## 5. 第二步：在 Apple Developer 網站註冊識別碼

登入 <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles**。

1. 選一個你自己的反向域名字首，例如 `com.zhangsan.vitalflow`（下文稱 **PREFIX**）。
2. **Identifiers → App Groups → 「+」**：建立 `group.PREFIX`（例如 `group.com.zhangsan.vitalflow`）。
3. **Identifiers → App IDs → 「+」 → App**，依次建立 4 個（Bundle ID 選 Explicit）：

| Bundle ID | 需要勾選的 Capabilities |
|---|---|
| `PREFIX` | HealthKit（同時勾選 Background Delivery）、App Groups（選擇 `group.PREFIX`） |
| `PREFIX.widgets` | App Groups（`group.PREFIX`） |
| `PREFIX.watchkitapp` | HealthKit、App Groups（`group.PREFIX`） |
| `PREFIX.watchkitapp.complications` | App Groups（`group.PREFIX`） |

> 使用自動簽名時 Xcode 也能自動建立這些識別碼，但手動建立更不容易出錯。

4. 記下你的 **Team ID**（頁面右上角 Membership 中的 10 位字元）。

## 6. 第三步：在 App Store Connect 建立 App 和 API 金鑰

1. 登入 <https://appstoreconnect.apple.com> → **我的 App → 「+」 → 新建 App**：平臺 iOS，名稱 VitalFlow（若重名可加字尾），Bundle ID 選 `PREFIX`，SKU 隨意填寫。
2. **使用者和訪問 → 整合 → App Store Connect API → 團隊金鑰 → 「+」**：
   - 名稱：`GitHub Actions`
   - 存取權限：**Admin**（GitHub 執行器沒有你的憑證，需要 Admin 權限讓 Xcode 透過雲端自動建立/使用分發憑證和描述檔；如你更想手動管理憑證，見第 8 節）。
   - 生成後**只能下載一次** `AuthKey_XXXXXXXXXX.p8`，妥善儲存。記下 **Key ID** 和頁面上方的 **Issuer ID**。

## 7. 第四步：配置 GitHub Secrets 並發布到 TestFlight

1. 把 `.p8` 檔案轉成 base64（在任意電腦上）：
   - Windows PowerShell：`[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8")) | Set-Clipboard`
   - Linux/macOS：`base64 -w0 AuthKey_XXXX.p8`（macOS 用 `base64 -i AuthKey_XXXX.p8`）
2. GitHub 儲存庫 → **Settings → Secrets and variables → Actions → New repository secret**，新增：

| Secret 名稱 | 值 |
|---|---|
| `APPLE_TEAM_ID` | 10 位 Team ID |
| `VF_BUNDLE_PREFIX` | 你的 PREFIX，例如 `com.zhangsan.vitalflow` |
| `ASC_KEY_ID` | API Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY_BASE64` | 上一步得到的 base64 字串 |

3. **注意**：GitHub 只會為預設分支（main）上的工作流顯示 「Run workflow」 按鈕。請先在 GitHub 上把分支 `claude/vitalflow-health-app-fq5uk8` 透過 Pull Request 合併到 `main`（只會新增 `VitalFlow/` 資料夾和 `.github/workflows/vitalflow-*.yml`，不會改動遊戲檔案）。
4. **Actions → VitalFlow TestFlight → Run workflow**，填寫版本號（如 `0.1.0`）後執行。工作流會：生成工程 → 用 API 金鑰自動簽名並 Archive → 匯出並上傳到 App Store Connect。構建號自動使用 GitHub 執行編號。
5. 上傳後約 5–30 分鐘，App Store Connect 的 **TestFlight** 標籤頁會出現該構建。首次需要填寫「出口合規」（專案已宣告 `ITSAppUsesNonExemptEncryption = false`，通常會自動跳過）。
6. 在 **TestFlight → 內部測試** 中建立群組並把自己（Apple ID）加進去。
7. 在 iPhone 上安裝 **TestFlight** App，用同一 Apple ID 登入，安裝 VitalFlow。配對的 Apple Watch 上會自動出現 VitalFlow（或在手錶的 App Store/「Watch」 App 中安裝）。
8. 首次開啟 VitalFlow：閱讀宣告 → 「連線‘健康’」 → 在系統彈窗中選擇要共享的資料類型。

> 🔐 安全：儲存庫中**沒有任何**密碼、私鑰或憑證。`.gitignore` 已忽略 `*.p8`、`*.p12`、`*.mobileprovision`。工作流在結束時刪除臨時寫入的 API 金鑰檔案。

## 7b. 免費安裝（沒有 99 美元開發者帳號，使用 Windows 電腦）

可以用免費 Apple ID + Windows 上的 **Sideloadly** 把 App 裝到自己的 iPhone 上，但有明顯限制：

| 限制 | 說明 |
|---|---|
| 每 7 天過期 | 免費 Apple ID 的簽名只有 7 天有效，到期後 App 打不開，需要用電腦重新安裝一次（資料會保留）。 |
| 最多 3 個側載 App | 免費帳號同時最多 3 個。 |
| Apple Watch App、小工具 | 很可能無法使用，建議先裝「僅 iPhone」版本。 |
| 健康資料（HealthKit） | 安裝包已包含 HealthKit 權限宣告，但免費簽名下能否讀取健康資料**未經測試**。若無法讀取，仍可在設定中開啟「示範模式」體驗介面。 |
| 背景重新整理、同一組共享資料 | 不可用（需要付費帳號的 App Group）。 |

步驟：

1. **下載安裝包**：GitHub 儲存庫 → **Actions** → **VitalFlow unsigned IPA (free sideloading)** → 最新一次成功的執行 → 頁面底部 **Artifacts** → 下載 `VitalFlow-unsigned-ipa`（需要登入 GitHub），解壓得到兩個檔案：
   - `VitalFlow-iphone-only-unsigned.ipa`（推薦先用這個）
   - `VitalFlow-full-unsigned.ipa`（含 Apple Watch App 和小工具，免費帳號多半裝不上）
2. **在 Windows 上安裝**：
   - 從 Apple 官網安裝 **iTunes**（不要用 Microsoft Store 版本，Sideloadly 推薦官網版）和 **iCloud**。
   - 從 sideloadly.io 下載安裝 **Sideloadly**。
3. 用 USB 線連接 iPhone，在 iPhone 上點「信任此電腦」。
4. 開啟 Sideloadly：把 `.ipa` 拖進去 → 輸入你的 Apple ID → 點 **Start**，按提示輸入密碼和雙重認證驗證碼。
   - 建議使用一個專門的 Apple ID，而不是主帳號。Apple ID 密碼只輸入到 Sideloadly 中，不要發給任何聊天機器人。
5. iPhone：**設定 → 通用 → VPN 與裝置管理** → 點你的 Apple ID → **信任**。
6. iOS 16 及以上還需開啟：**設定 → 隱私與安全性 → 開發者模式** → 開啟並重啟。
7. 開啟 VitalFlow → 連接「健康」。每 7 天用 Sideloadly 重新安裝一次。

> 這種方式完全不需要 Mac，也不需要往 GitHub 新增任何金鑰。

## 8. 常見問題

- **CI 報 「No profiles for … were found」**：確認第 5 節的 4 個 App ID 已建立且 Capabilities 勾選正確，API 金鑰為 Admin 權限，`VF_BUNDLE_PREFIX` 與註冊的一致。
- **想手動管理憑證**：在開發者網站建立 Apple Distribution 憑證和 4 個 App Store 描述檔，把 `.p12`（base64）和描述檔作為 Secrets 匯入執行器鑰匙串，並將 `CODE_SIGN_STYLE` 改為 Manual。預設的自動簽名方式更簡單。
- **所有分數都顯示「資料不足」**：需要至少 4 天佩戴 Apple Watch（含睡眠）的資料來建立個人基線；請在「健康」App → 個人資料 → App → VitalFlow 中確認已允許讀取。HealthKit 不會告訴 App 哪些讀取權限被拒絕，所以被拒絕和沒有資料看起來一樣。
- **沒有睡眠階段**：需要在「健康」App 中設定睡眠專注模式，並佩戴 Apple Watch 入睡。
- **血氧 / 手腕溫度缺失**：部分型號和地區不支援；評分會自動降低可信度而不是編造數值。
- **模擬器裡沒有資料**：模擬器沒有 Apple Watch，請在設定中開啟「示範模式」。

## 9. 遷移到獨立的 GitHub 儲存庫

當前會話的權限只允許寫入本儲存庫，因此專案放在 `VitalFlow/` 子目錄中。遷移到新儲存庫（保留提交歷史）：

```bash
# 1. 在 GitHub 網頁上新建空儲存庫，例如 vitalflow
git clone https://github.com/<你的使用者名稱>/Micraft-game-.git
cd Micraft-game-
git checkout claude/vitalflow-health-app-fq5uk8
git subtree split --prefix=VitalFlow -b vitalflow-only
git push https://github.com/<你的使用者名稱>/vitalflow.git vitalflow-only:main
```

遷移後把 `.github/workflows/vitalflow-*.yml` 複製到新儲存庫的 `.github/workflows/`，刪除其中的 `working-directory: VitalFlow` 和 `paths` 字首 `VitalFlow/`。

## 10. 本地開發（如果以後有 Mac）

```bash
brew install xcodegen
cd VitalFlow
xcodegen generate          # 生成 VitalFlow.xcodeproj
open VitalFlow.xcodeproj    # 在 Signing & Capabilities 中選擇你的 Team
swift test --package-path Packages/VitalFlowCore   # 執行演算法單元測試
python3 scripts/build_strings.py                  # 修改介面文字後重新生成 String Catalog
```

在 `Config/Base.xcconfig` 中把 `VF_BUNDLE_PREFIX` 改成你自己的字首即可本地簽名。

## 11. 測試與驗證狀態（誠實說明）

- ✅ **VitalFlowCore 63 個單元測試**在 Linux（Swift 6.0）上已執行並全部通過：健康評分、缺失資料、重複記錄、跨午夜與夏令時日期邊界、睡眠重疊樣本、多資料來源、遊戲化、助手意圖識別。
- ✅ **iOS / watchOS 編譯與模擬器測試**已在 GitHub Actions macOS 執行器上通過（CI 第 4 次執行）：iPhone App（含內嵌 Watch App 與兩個小工具擴充套件）編譯成功，iPhone 模擬器單元測試通過，watchOS App 單獨編譯成功。
- ❌ **尚未在真機（iPhone / Apple Watch）上測試**。HealthKit 授權流程、背景推送、WatchConnectivity 同步、體能訓練會話、小工具和複雜功能在真機上的表現都需要你透過 TestFlight 安裝後驗證。

## 12. 許可

原始碼由你所有。圖示與品牌由指令碼 `scripts/make_icon.py` 原創生成，未使用任何第三方受版權保護的素材。
