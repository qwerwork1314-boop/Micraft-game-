# VitalFlow · 原生 Apple Watch 健康与健身应用

VitalFlow 是一款用 **Swift / SwiftUI** 编写的原生 iPhone + Apple Watch 应用，基于 Apple 官方 **HealthKit** 读取真实健康数据，在设备端计算个性化的恢复、压力、身体电量、睡眠与训练准备度等**实验性健康估算**。

> ⚠️ **重要声明**：VitalFlow 的所有评分都是实验性健康估算，未经临床验证，不是医学测量，也不能用于诊断、治疗或预防任何疾病。

- 本项目放在仓库的 `VitalFlow/` 目录中，与仓库里原有的 Blocklands 游戏完全独立（游戏文件没有被修改）。如何把它搬到独立仓库见 [第 9 节](#9-迁移到独立的-github-仓库)。
- 算法公式与局限：[`docs/ALGORITHMS.md`](docs/ALGORITHMS.md)
- 隐私政策：[`docs/PRIVACY.md`](docs/PRIVACY.md)
- 功能状态（已实现 / 已测试 / 未测试 / 计划中）：[`docs/FEATURE_STATUS.md`](docs/FEATURE_STATUS.md)

---

## 1. 功能概览

| 模块 | 内容 |
|---|---|
| 今日仪表盘 | 恢复分数、身体电量、压力、训练准备度、当前/静息心率、HRV、昨晚睡眠、活动圆环、卡路里、饮水进度、个性化建议、可交互图表 |
| 睡眠 | 睡眠阶段时间线、总时长、效率、规律性、中途醒来、睡眠心率、睡眠呼吸频率、日/周/月/年报告、睡眠建议；正确处理重叠样本与多数据源 |
| 趋势 | HRV、静息心率、睡眠、步数、活动能量、呼吸频率、血氧、最大摄氧量、体重、日照、饮水的 7 天/30 天/90 天/1 年图表，本周与上周对比 |
| 教练（AI 助手） | 完全在设备端运行的对话助手，可回答“为什么我今天恢复分数较低？”等问题；可选的外部 AI（Anthropic Claude）需明确知情同意，仅发送最少的汇总数字 |
| 花园（游戏化） | 每日目标、徽章、每周报告、可自定义目标（限制在健康范围内）、会随健康习惯成长的虚拟花园、可选的温和提醒 |
| Apple Watch | 恢复/身体电量/压力摘要、心率、活动进度、饮水记录、体能训练（含训练中的实时心率）、表盘复杂功能、与 iPhone 同步 |
| 小组件 | 主屏幕小/中尺寸，锁定屏幕圆形/矩形/行内 |
| 其他 | 简体中文、繁体中文、英文；浅色/深色模式；动态字体；VoiceOver 标签；iOS 26 上使用 Liquid Glass（更早版本自动回退为毛玻璃材质） |

## 2. 技术架构

```
VitalFlow/
├── project.yml                 # XcodeGen 工程定义（生成 VitalFlow.xcodeproj）
├── Config/Base.xcconfig        # Bundle ID 前缀、版本号（无任何密钥）
├── Packages/VitalFlowCore/     # 纯 Swift 包：模型、去重、睡眠合并、基线、全部评分算法、助手、游戏化、演示数据
│   └── Tests/                  # 63 个单元测试（缺失数据、重复记录、日期边界、夏令时等）
├── Shared/Common/              # iPhone/Watch/小组件共用：品牌色、快照、Localizable.xcstrings
├── Shared/Health/              # HealthKit 封装 + 数据仓库（真实数据 / 演示数据）
├── iOS/                        # iPhone App（SwiftUI + Swift Charts + SwiftData）
├── Watch/                      # watchOS App（HKWorkoutSession、WatchConnectivity）
├── Widgets/                    # iOS WidgetKit 小组件
├── WatchWidgets/               # Apple Watch 表盘复杂功能（WidgetKit）
├── Tests/                      # iOS 单元测试（HealthKit 映射等）
├── scripts/                    # 图标生成、多语言字符串生成与检查
└── docs/                       # 算法、隐私政策、功能状态
```

- **最低系统**：iOS 17、watchOS 10（SwiftData、`timeInDaylight` 等需要）。在 iOS 26 / watchOS 26 上自动启用 Liquid Glass 等新特性。
- **数据流**：HealthKit → `HealthKitDataProvider`（统计查询自动按来源优先级去重）→ `VitalFlowCore`（离散样本去重、睡眠合并、基线、评分）→ SwiftUI。结果写入 App Group 快照供小组件使用，并通过 `WCSession.updateApplicationContext` 发给手表。
- **演示模式**：在“设置”中单独开启，所有页面都会显示醒目的“演示数据”标签；演示数据绝不会写入“健康”，也不会与真实数据混合。生产路径从不生成随机健康数值。
- **电池与后台**：手表上只在用户主动开始体能训练时运行 `HKWorkoutSession`，结束即停止；平时只读取 watchOS 已记录的心率（`HKAnchoredObjectQuery`），不会为了持续采集传感器而保持假训练会话。iPhone 使用 HealthKit 后台推送（每小时，由系统控制）。

## 3. 你需要准备什么

| 项目 | 说明 |
|---|---|
| GitHub 账号 | 用于存放代码和运行 GitHub Actions（macOS 运行器负责编译）。公开仓库的 macOS 运行器免费；私有仓库会按 macOS 分钟数（10 倍系数）消耗额度。 |
| Apple ID + iPhone（+ Apple Watch） | 必需。 |
| **Apple Developer Program 会员（99 美元/年）** | **没有 Mac 时必需**。HealthKit 能力、App Group、TestFlight 分发都需要付费开发者账号。免费账号只能用 Xcode 直接安装到设备，而这需要 Mac。 |
| App Store Connect API 密钥 | 让 GitHub Actions 自动签名并上传到 TestFlight。 |

不需要 Mac：编译、签名、上传全部在 GitHub 的 macOS 云端运行器上完成；安装通过 iPhone 上的 **TestFlight** App。

## 4. 第一步：确认 CI 编译通过

1. 打开仓库页面 → **Actions** → **VitalFlow CI**。每次推送 `VitalFlow/` 下的改动都会自动运行：
   - `Core algorithms (Linux)`：运行 VitalFlowCore 的全部单元测试，并检查三种语言的翻译是否齐全。
   - `iOS + watchOS build & test (macOS)`：用 XcodeGen 生成工程，编译 iPhone App（含内嵌的 Watch App 和小组件），在 iPhone 模拟器中运行单元测试，再单独编译 watchOS App。
2. 运行结束后，可在该次运行页面底部的 **Artifacts** 下载 `VitalFlow-xcodeproj`（生成好的 Xcode 工程）和测试结果。

## 5. 第二步：在 Apple Developer 网站注册标识符

登录 <https://developer.apple.com/account> → **Certificates, Identifiers & Profiles**。

1. 选一个你自己的反向域名前缀，例如 `com.zhangsan.vitalflow`（下文称 **PREFIX**）。
2. **Identifiers → App Groups → “+”**：创建 `group.PREFIX`（例如 `group.com.zhangsan.vitalflow`）。
3. **Identifiers → App IDs → “+” → App**，依次创建 4 个（Bundle ID 选 Explicit）：

| Bundle ID | 需要勾选的 Capabilities |
|---|---|
| `PREFIX` | HealthKit（同时勾选 Background Delivery）、App Groups（选择 `group.PREFIX`） |
| `PREFIX.widgets` | App Groups（`group.PREFIX`） |
| `PREFIX.watchkitapp` | HealthKit、App Groups（`group.PREFIX`） |
| `PREFIX.watchkitapp.complications` | App Groups（`group.PREFIX`） |

> 使用自动签名时 Xcode 也能自动创建这些标识符，但手动创建更不容易出错。

4. 记下你的 **Team ID**（页面右上角 Membership 中的 10 位字符）。

## 6. 第三步：在 App Store Connect 创建 App 和 API 密钥

1. 登录 <https://appstoreconnect.apple.com> → **我的 App → “+” → 新建 App**：平台 iOS，名称 VitalFlow（若重名可加后缀），Bundle ID 选 `PREFIX`，SKU 随意填写。
2. **用户和访问 → 集成 → App Store Connect API → 团队密钥 → “+”**：
   - 名称：`GitHub Actions`
   - 访问权限：**Admin**（GitHub 运行器没有你的证书，需要 Admin 权限让 Xcode 通过云端自动创建/使用分发证书和描述文件；如你更想手动管理证书，见第 8 节）。
   - 生成后**只能下载一次** `AuthKey_XXXXXXXXXX.p8`，妥善保存。记下 **Key ID** 和页面上方的 **Issuer ID**。

## 7. 第四步：配置 GitHub Secrets 并发布到 TestFlight

1. 把 `.p8` 文件转成 base64（在任意电脑上）：
   - Windows PowerShell：`[Convert]::ToBase64String([IO.File]::ReadAllBytes("AuthKey_XXXX.p8")) | Set-Clipboard`
   - Linux/macOS：`base64 -w0 AuthKey_XXXX.p8`（macOS 用 `base64 -i AuthKey_XXXX.p8`）
2. GitHub 仓库 → **Settings → Secrets and variables → Actions → New repository secret**，添加：

| Secret 名称 | 值 |
|---|---|
| `APPLE_TEAM_ID` | 10 位 Team ID |
| `VF_BUNDLE_PREFIX` | 你的 PREFIX，例如 `com.zhangsan.vitalflow` |
| `ASC_KEY_ID` | API Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_PRIVATE_KEY_BASE64` | 上一步得到的 base64 字符串 |

3. **Actions → VitalFlow TestFlight → Run workflow**，填写版本号（如 `0.1.0`）后运行。工作流会：生成工程 → 用 API 密钥自动签名并 Archive → 导出并上传到 App Store Connect。构建号自动使用 GitHub 运行编号。
4. 上传后约 5–30 分钟，App Store Connect 的 **TestFlight** 标签页会出现该构建。首次需要填写“出口合规”（项目已声明 `ITSAppUsesNonExemptEncryption = false`，通常会自动跳过）。
5. 在 **TestFlight → 内部测试** 中创建群组并把自己（Apple ID）加进去。
6. 在 iPhone 上安装 **TestFlight** App，用同一 Apple ID 登录，安装 VitalFlow。配对的 Apple Watch 上会自动出现 VitalFlow（或在手表的 App Store/“Watch” App 中安装）。
7. 首次打开 VitalFlow：阅读声明 → “连接‘健康’” → 在系统弹窗中选择要共享的数据类型。

> 🔐 安全：仓库中**没有任何**密码、私钥或证书。`.gitignore` 已忽略 `*.p8`、`*.p12`、`*.mobileprovision`。工作流在结束时删除临时写入的 API 密钥文件。

## 8. 常见问题

- **CI 报 “No profiles for … were found”**：确认第 5 节的 4 个 App ID 已创建且 Capabilities 勾选正确，API 密钥为 Admin 权限，`VF_BUNDLE_PREFIX` 与注册的一致。
- **想手动管理证书**：在开发者网站创建 Apple Distribution 证书和 4 个 App Store 描述文件，把 `.p12`（base64）和描述文件作为 Secrets 导入运行器钥匙串，并将 `CODE_SIGN_STYLE` 改为 Manual。默认的自动签名方式更简单。
- **所有分数都显示“数据不足”**：需要至少 4 天佩戴 Apple Watch（含睡眠）的数据来建立个人基线；请在“健康”App → 个人资料 → App → VitalFlow 中确认已允许读取。HealthKit 不会告诉 App 哪些读取权限被拒绝，所以被拒绝和没有数据看起来一样。
- **没有睡眠阶段**：需要在“健康”App 中设置睡眠专注模式，并佩戴 Apple Watch 入睡。
- **血氧 / 手腕温度缺失**：部分型号和地区不支持；评分会自动降低可信度而不是编造数值。
- **模拟器里没有数据**：模拟器没有 Apple Watch，请在设置中开启“演示模式”。

## 9. 迁移到独立的 GitHub 仓库

当前会话的权限只允许写入本仓库，因此项目放在 `VitalFlow/` 子目录中。迁移到新仓库（保留提交历史）：

```bash
# 1. 在 GitHub 网页上新建空仓库，例如 vitalflow
git clone https://github.com/<你的用户名>/Micraft-game-.git
cd Micraft-game-
git checkout claude/vitalflow-health-app-fq5uk8
git subtree split --prefix=VitalFlow -b vitalflow-only
git push https://github.com/<你的用户名>/vitalflow.git vitalflow-only:main
```

迁移后把 `.github/workflows/vitalflow-*.yml` 复制到新仓库的 `.github/workflows/`，删除其中的 `working-directory: VitalFlow` 和 `paths` 前缀 `VitalFlow/`。

## 10. 本地开发（如果以后有 Mac）

```bash
brew install xcodegen
cd VitalFlow
xcodegen generate          # 生成 VitalFlow.xcodeproj
open VitalFlow.xcodeproj    # 在 Signing & Capabilities 中选择你的 Team
swift test --package-path Packages/VitalFlowCore   # 运行算法单元测试
python3 scripts/build_strings.py                  # 修改界面文字后重新生成 String Catalog
```

在 `Config/Base.xcconfig` 中把 `VF_BUNDLE_PREFIX` 改成你自己的前缀即可本地签名。

## 11. 测试与验证状态（诚实说明）

- ✅ **VitalFlowCore 63 个单元测试**在 Linux（Swift 6.0）上已运行并全部通过：健康评分、缺失数据、重复记录、跨午夜与夏令时日期边界、睡眠重叠样本、多数据源、游戏化、助手意图识别。
- ✅ **iOS / watchOS 编译与模拟器测试**已在 GitHub Actions macOS 运行器上通过（CI 第 4 次运行）：iPhone App（含内嵌 Watch App 与两个小组件扩展）编译成功，iPhone 模拟器单元测试通过，watchOS App 单独编译成功。
- ❌ **尚未在真机（iPhone / Apple Watch）上测试**。HealthKit 授权流程、后台推送、WatchConnectivity 同步、体能训练会话、小组件和复杂功能在真机上的表现都需要你通过 TestFlight 安装后验证。

## 12. 许可

源代码由你所有。图标与品牌由脚本 `scripts/make_icon.py` 原创生成，未使用任何第三方受版权保护的素材。
