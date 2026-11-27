import Foundation

public enum AssistantLanguage: String, Codable, Sendable, CaseIterable {
    case english = "en", simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant"

    /// Maps a BCP-47 identifier (e.g. "zh-Hant-TW", "zh-HK", "en-GB") to a supported language.
    public static func from(localeIdentifier id: String) -> AssistantLanguage {
        let l = id.lowercased().replacingOccurrences(of: "_", with: "-")
        guard l.hasPrefix("zh") else { return .english }
        if l.contains("hant") || l.contains("-tw") || l.contains("-hk") || l.contains("-mo") { return .traditionalChinese }
        return .simplifiedChinese
    }
}

public enum AssistantIntent: String, Codable, Sendable, CaseIterable {
    case recoveryWhy, sleepLastNight, restingHRTrend, hrvTrend, activityBalance, stress, bodyBattery
    case activityToday, hydration, readiness, medical, help
}

/// Everything the assistant may read. Built from local data only.
public struct AssistantContext: Sendable {
    public var today: DailyAssessment?
    public var history: [DailyMetrics]
    public var waterGoalML: Double
    public var calendar: Calendar

    public init(today: DailyAssessment?, history: [DailyMetrics], waterGoalML: Double = 2000, calendar: Calendar) {
        self.today = today
        self.history = history
        self.waterGoalML = waterGoalML
        self.calendar = calendar
    }
}

/// Fully on-device, deterministic wellness assistant. It only explains the user's own data
/// and never diagnoses, prescribes or replaces professionals.
public struct WellnessAssistant: Sendable {
    public var language: AssistantLanguage
    public init(language: AssistantLanguage) { self.language = language }

    // MARK: Intent classification (keyword based, EN + 简 + 繁)

    static let keywords: [(AssistantIntent, [String])] = [
        (.medical, ["diagnos", "disease", "medication", "medicine", "prescri", "drug", "dose", "cancer", "diabetes",
                    "heart attack", "arrhythmia", "afib", "诊断", "診斷", "疾病", "药", "藥", "处方", "處方", "剂量", "劑量", "癌", "糖尿病", "心脏病", "心臟病"]),
        (.activityBalance, ["balance", "strain", "load", "平衡", "负荷", "負荷"]),
        (.restingHRTrend, ["resting heart", "resting hr", "rhr", "静息心率", "靜息心率", "安静心率", "安靜心率"]),
        (.hrvTrend, ["hrv", "variability", "心率变异", "心率變異"]),
        (.recoveryWhy, ["recovery", "recover", "恢复", "恢復"]),
        (.sleepLastNight, ["sleep", "slept", "睡", "眠"]),
        (.stress, ["stress", "压力", "壓力"]),
        (.bodyBattery, ["battery", "energy level", "电量", "電量", "能量"]),
        (.readiness, ["readiness", "train today", "workout today", "ready", "训练", "訓練", "准备", "準備"]),
        (.activityToday, ["steps", "activity", "calorie", "exercise", "步", "活动", "活動", "卡路里", "运动", "運動"]),
        (.hydration, ["water", "hydrat", "drink", "喝水", "饮水", "飲水", "水分"]),
    ]

    public static func classify(_ text: String) -> AssistantIntent {
        let t = text.lowercased()
        for (intent, words) in keywords where words.contains(where: { t.contains($0) }) {
            return intent
        }
        return .help
    }

    // MARK: Answers

    public func answer(_ question: String, context: AssistantContext) -> String {
        let intent = Self.classify(question)
        let body: String
        switch intent {
        case .medical: return t(medical: ())
        case .help: return helpText
        case .recoveryWhy: body = recoveryWhy(context)
        case .sleepLastNight: body = sleep(context)
        case .restingHRTrend: body = monthlyTrend(context, key: "restingHeartRate", unit: "bpm", value: { $0.restingHeartRate })
        case .hrvTrend: body = monthlyTrend(context, key: "hrv", unit: "ms", value: { $0.hrv })
        case .activityBalance: body = balance(context)
        case .stress: body = stress(context)
        case .bodyBattery: body = battery(context)
        case .readiness: body = readiness(context)
        case .activityToday: body = activity(context)
        case .hydration: body = hydration(context)
        }
        return body + "\n\n" + disclaimer
    }

    // MARK: Localisation helper

    func l(_ en: String, _ hans: String, _ hant: String) -> String {
        switch language {
        case .english: return en
        case .simplifiedChinese: return hans
        case .traditionalChinese: return hant
        }
    }

    var notEnough: String {
        l("Not enough data yet. Wear your Apple Watch to sleep for a few nights so VitalFlow can learn your personal baseline.",
          "数据还不够。请佩戴 Apple Watch 睡眠几晚，让 VitalFlow 建立你的个人基线。",
          "資料還不夠。請佩戴 Apple Watch 睡眠幾晚，讓 VitalFlow 建立你的個人基線。")
    }

    var disclaimer: String {
        l("VitalFlow scores are experimental wellness estimates, not medical measurements.",
          "VitalFlow 评分为实验性健康估算，并非医学测量。",
          "VitalFlow 評分為實驗性健康估算，並非醫學測量。")
    }

    func t(medical: Void) -> String {
        l("I can't diagnose conditions or advise on medication. If you're worried about a symptom or a reading, please contact a doctor or other qualified health professional. In an emergency, call your local emergency number.",
          "我无法诊断疾病或提供用药建议。如果你担心某个症状或数据，请咨询医生或其他合格的医疗专业人员。紧急情况请拨打当地急救电话。",
          "我無法診斷疾病或提供用藥建議。如果你擔心某個症狀或數據，請諮詢醫生或其他合格的醫療專業人員。緊急情況請撥打當地急救電話。")
    }

    var helpText: String {
        l("You can ask me things like:\n• Why is my recovery lower today?\n• How well did I sleep last night?\n• How has my resting heart rate changed this month?\n• What is my activity and recovery balance?",
          "你可以这样问我：\n• 为什么我今天的恢复分数较低？\n• 我昨晚睡得怎么样？\n• 这个月我的静息心率有什么变化？\n• 我现在的活动与恢复平衡如何？",
          "你可以這樣問我：\n• 為什麼我今天的恢復分數較低？\n• 我昨晚睡得怎麼樣？\n• 這個月我的靜息心率有什麼變化？\n• 我現在的活動與恢復平衡如何？")
    }

    func componentName(_ key: String) -> String {
        switch key {
        case "hrv": return l("heart rate variability", "心率变异性", "心率變異性")
        case "restingHeartRate": return l("resting heart rate", "静息心率", "靜息心率")
        case "sleep": return l("sleep quality", "睡眠质量", "睡眠品質")
        case "respiratoryRate": return l("respiratory rate", "呼吸频率", "呼吸頻率")
        case "wristTemperature": return l("wrist temperature", "手腕温度", "手腕溫度")
        default: return key
        }
    }

    func fmt(_ v: Double, _ digits: Int = 0) -> String { String(format: "%.\(digits)f", v) }

    func hm(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600, m = (Int(seconds) % 3600) / 60
        return l("\(h)h \(m)m", "\(h)小时\(m)分钟", "\(h)小時\(m)分鐘")
    }

    // MARK: Intents

    func recoveryWhy(_ c: AssistantContext) -> String {
        guard let a = c.today, let score = a.recovery.score else { return notEnough }
        let comps = a.recovery.components.sorted { $0.effect * $0.weight < $1.effect * $1.weight }
        var lines = [l("Your recovery today is \(score)/100.", "你今天的恢复分数为 \(score)/100。", "你今天的恢復分數為 \(score)/100。")]
        let negatives = comps.filter { $0.effect < -0.3 }
        let positives = comps.filter { $0.effect > 0.3 }.reversed()
        for comp in negatives.prefix(2) { lines.append("• " + describe(comp, good: false)) }
        for comp in positives.prefix(2) { lines.append("• " + describe(comp, good: true)) }
        if negatives.isEmpty && positives.isEmpty {
            lines.append(l("All inputs are close to your personal baseline.", "所有指标都接近你的个人基线。", "所有指標都接近你的個人基線。"))
        }
        if score < 50 {
            lines.append(l("Consider lighter activity, hydration and an earlier bedtime tonight.",
                           "今天可以考虑轻量活动、多补水，并早点睡。",
                           "今天可以考慮輕量活動、多補水，並早點睡。"))
        }
        return lines.joined(separator: "\n")
    }

    func describe(_ comp: ScoreComponent, good: Bool) -> String {
        let name = componentName(comp.key)
        var detail = ""
        if let v = comp.value, let b = comp.baseline {
            let unit = comp.key == "hrv" ? " ms" : comp.key == "restingHeartRate" ? " bpm" : ""
            let digits = comp.key == "wristTemperature" || comp.key == "respiratoryRate" ? 1 : 0
            detail = l(" (\(fmt(v, digits))\(unit) vs. your usual \(fmt(b, digits))\(unit))",
                       "（\(fmt(v, digits))\(unit)，你的常态为 \(fmt(b, digits))\(unit)）",
                       "（\(fmt(v, digits))\(unit)，你的常態為 \(fmt(b, digits))\(unit)）")
        } else if let v = comp.value {
            detail = " (\(fmt(v)))"
        }
        return good
            ? l("Your \(name) helped\(detail).", "你的\(name)表现良好\(detail)。", "你的\(name)表現良好\(detail)。")
            : l("Your \(name) lowered the score\(detail).", "你的\(name)拉低了分数\(detail)。", "你的\(name)拉低了分數\(detail)。")
    }

    func sleep(_ c: AssistantContext) -> String {
        guard let a = c.today, let n = a.metrics.sleep else { return notEnough }
        var lines = [l("Last night you slept \(hm(n.asleep)) (\(fmt(n.efficiency * 100))% efficiency, \(n.interruptions) interruptions).",
                       "昨晚你睡了 \(hm(n.asleep))（睡眠效率 \(fmt(n.efficiency * 100))%，中途醒来 \(n.interruptions) 次）。",
                       "昨晚你睡了 \(hm(n.asleep))（睡眠效率 \(fmt(n.efficiency * 100))%，中途醒來 \(n.interruptions) 次）。")]
        if n.hasStageData {
            lines.append(l("Deep \(hm(n.deep)), REM \(hm(n.rem)), core \(hm(n.core)).",
                           "深睡 \(hm(n.deep))，REM \(hm(n.rem))，核心睡眠 \(hm(n.core))。",
                           "深睡 \(hm(n.deep))，REM \(hm(n.rem))，核心睡眠 \(hm(n.core))。"))
        }
        if let s = a.sleepScore.score {
            lines.append(l("Sleep score: \(s)/100.", "睡眠分数：\(s)/100。", "睡眠分數：\(s)/100。"))
        }
        if let cons = a.sleepConsistency.score, cons < 60 {
            lines.append(l("Your sleep timing has varied this week; a steadier bedtime usually helps.",
                           "本周你的入睡时间变化较大，固定作息通常会有帮助。",
                           "本週你的入睡時間變化較大，固定作息通常會有幫助。"))
        }
        return lines.joined(separator: "\n")
    }

    func monthlyTrend(_ c: AssistantContext, key: String, unit: String, value: (DailyMetrics) -> Double?) -> String {
        guard let day = c.today?.day ?? c.history.map(\.day).max() else { return notEnough }
        let tr = TrendAnalyzer.trend(metric: key, day: day, period: 30, history: c.history, value: value, calendar: c.calendar)
        guard tr.direction != .insufficient, let cur = tr.currentAverage, let prev = tr.previousAverage, let ch = tr.changePercent else {
            // Fall back to a 14-day comparison if a full month isn't available.
            let short = TrendAnalyzer.trend(metric: key, day: day, period: 14, history: c.history, value: value, calendar: c.calendar)
            guard short.direction != .insufficient, let cur = short.currentAverage, let prev = short.previousAverage else { return notEnough }
            return trendSentence(key: key, unit: unit, cur: cur, prev: prev, change: short.changePercent ?? 0, direction: short.direction, days: 14)
        }
        return trendSentence(key: key, unit: unit, cur: cur, prev: prev, change: ch, direction: tr.direction, days: 30)
    }

    func trendSentence(key: String, unit: String, cur: Double, prev: Double, change: Double, direction: TrendDirection, days: Int) -> String {
        let name = componentName(key)
        let dir: String
        switch direction {
        case .improving: dir = l("a favourable change", "向好的变化", "向好的變化")
        case .declining: dir = l("a less favourable change", "不太理想的变化", "不太理想的變化")
        default: dir = l("essentially stable", "基本稳定", "基本穩定")
        }
        return l("Over the last \(days) days your average \(name) was \(fmt(cur)) \(unit), compared with \(fmt(prev)) \(unit) in the \(days) days before (\(change >= 0 ? "+" : "")\(fmt(change, 1))%) — \(dir).",
                 "最近 \(days) 天你的平均\(name)为 \(fmt(cur)) \(unit)，之前 \(days) 天为 \(fmt(prev)) \(unit)（\(change >= 0 ? "+" : "")\(fmt(change, 1))%），属于\(dir)。",
                 "最近 \(days) 天你的平均\(name)為 \(fmt(cur)) \(unit)，之前 \(days) 天為 \(fmt(prev)) \(unit)（\(change >= 0 ? "+" : "")\(fmt(change, 1))%），屬於\(dir)。")
    }

    func balance(_ c: AssistantContext) -> String {
        guard let a = c.today, let b = a.balance, let r = a.recovery.score else { return notEnough }
        let head = l("Recovery \(r)/100, activity load \(a.activityLoad)/100.", "恢复 \(r)/100，活动负荷 \(a.activityLoad)/100。", "恢復 \(r)/100，活動負荷 \(a.activityLoad)/100。")
        let body: String
        switch b {
        case .roomToPush: body = l("You're well recovered with a light load so far — there's room for a quality session if you feel like it.",
                                   "你恢复良好且目前负荷较轻——如果状态不错，可以安排一次高质量训练。",
                                   "你恢復良好且目前負荷較輕——如果狀態不錯，可以安排一次高品質訓練。")
        case .balanced: body = l("Your activity and recovery are in balance.", "你的活动与恢复处于平衡状态。", "你的活動與恢復處於平衡狀態。")
        case .overreaching: body = l("Today's load is high relative to your recovery. Easy movement and rest will help you bounce back.",
                                     "相对于恢复状态，今天的负荷偏高。轻松活动和休息有助于恢复。",
                                     "相對於恢復狀態，今天的負荷偏高。輕鬆活動和休息有助於恢復。")
        case .restDay: body = l("Recovery is low and you've kept the load light — a sensible rest day.",
                                "恢复偏低且你保持了较轻的负荷——这是明智的休息日。",
                                "恢復偏低且你保持了較輕的負荷——這是明智的休息日。")
        }
        var out = head + "\n" + body
        if let acwr = a.readiness.acwr {
            out += "\n" + l("7-day vs 28-day load ratio: \(fmt(acwr, 2)).", "7 天与 28 天负荷比：\(fmt(acwr, 2))。", "7 天與 28 天負荷比：\(fmt(acwr, 2))。")
        }
        return out
    }

    func stress(_ c: AssistantContext) -> String {
        guard let a = c.today, let s = a.stress.result.score else { return notEnough }
        let peak = a.stress.hourly.max { $0.level < $1.level }
        var out = l("Estimated stress today: \(s)/100 (from heart rate at rest\(a.stress.hourly.isEmpty ? "" : " across \(a.stress.hourly.count) hours")).",
                    "今日压力估算：\(s)/100（基于静止时心率，共 \(a.stress.hourly.count) 小时）。",
                    "今日壓力估算：\(s)/100（基於靜止時心率，共 \(a.stress.hourly.count) 小時）。")
        if let peak, peak.level >= 60 {
            let h = c.calendar.component(.hour, from: peak.hourStart)
            out += "\n" + l("Highest around \(h):00. A few slow breaths or a short walk can help.",
                            "\(h) 点左右最高。几次缓慢深呼吸或短暂散步可能有帮助。",
                            "\(h) 點左右最高。幾次緩慢深呼吸或短暫散步可能有幫助。")
        }
        return out
    }

    func battery(_ c: AssistantContext) -> String {
        guard let a = c.today, let v = a.bodyBattery.result.score else { return notEnough }
        let m = a.bodyBattery.morningLevel ?? v
        return l("Body Battery is \(v)/100 now (started the day at \(m)).",
                 "身体电量目前为 \(v)/100（今早起始为 \(m)）。",
                 "身體電量目前為 \(v)/100（今早起始為 \(m)）。")
    }

    func readiness(_ c: AssistantContext) -> String {
        guard let a = c.today, let v = a.readiness.result.score, let lvl = a.readiness.level else { return notEnough }
        let advice: String
        switch lvl {
        case .prime: advice = l("You look ready for a harder session.", "你看起来适合进行较高强度的训练。", "你看起來適合進行較高強度的訓練。")
        case .moderate: advice = l("Moderate training fits today.", "今天适合中等强度训练。", "今天適合中等強度訓練。")
        case .easy: advice = l("Keep it easy today.", "今天以轻松活动为主。", "今天以輕鬆活動為主。")
        case .rest: advice = l("Prioritise rest and recovery today.", "今天请优先休息与恢复。", "今天請優先休息與恢復。")
        }
        return l("Training readiness: \(v)/100. ", "训练准备度：\(v)/100。", "訓練準備度：\(v)/100。") + advice
    }

    func activity(_ c: AssistantContext) -> String {
        guard let m = c.today?.metrics, m.steps != nil || m.activeEnergy != nil else { return notEnough }
        return l("Today: \(fmt(m.steps ?? 0)) steps, \(fmt(m.activeEnergy ?? 0)) kcal active energy, \(fmt(m.exerciseMinutes ?? 0)) exercise minutes.",
                 "今天：\(fmt(m.steps ?? 0)) 步，活动能量 \(fmt(m.activeEnergy ?? 0)) 千卡，锻炼 \(fmt(m.exerciseMinutes ?? 0)) 分钟。",
                 "今天：\(fmt(m.steps ?? 0)) 步，活動能量 \(fmt(m.activeEnergy ?? 0)) 大卡，運動 \(fmt(m.exerciseMinutes ?? 0)) 分鐘。")
    }

    func hydration(_ c: AssistantContext) -> String {
        let w = c.today?.metrics.waterML ?? 0
        return l("You've logged \(fmt(w)) ml of water today (goal \(fmt(c.waterGoalML)) ml).",
                 "今天你已记录饮水 \(fmt(w)) 毫升（目标 \(fmt(c.waterGoalML)) 毫升）。",
                 "今天你已記錄飲水 \(fmt(w)) 毫升（目標 \(fmt(c.waterGoalML)) 毫升）。")
    }
}

/// The *only* data that may leave the device when the user has opted into an external AI
/// provider: rounded, aggregate, de-identified numbers. No dates of birth, names, device IDs,
/// raw samples, locations or timestamps finer than a day.
public struct MinimizedHealthSummary: Codable, Hashable, Sendable {
    public var recovery: Int?
    public var sleepScore: Int?
    public var stress: Int?
    public var bodyBattery: Int?
    public var readiness: Int?
    public var sleepHours: Double?
    public var restingHR: Int?
    public var restingHRBaseline: Int?
    public var hrvMs: Int?
    public var hrvBaselineMs: Int?
    public var steps: Int?
    public var activeKcal: Int?
    public var trends: [String: String]

    public static func from(_ a: DailyAssessment?) -> MinimizedHealthSummary {
        func comp(_ key: String) -> ScoreComponent? { a?.recovery.components.first { $0.key == key } }
        return MinimizedHealthSummary(
            recovery: a?.recovery.score, sleepScore: a?.sleepScore.score, stress: a?.stress.result.score,
            bodyBattery: a?.bodyBattery.result.score, readiness: a?.readiness.result.score,
            sleepHours: a?.metrics.sleep.map { ($0.asleep / 360).rounded() / 10 },
            restingHR: a?.metrics.restingHeartRate.map { Int($0.rounded()) },
            restingHRBaseline: comp("restingHeartRate")?.baseline.map { Int($0.rounded()) },
            hrvMs: a?.metrics.hrv.map { Int($0.rounded()) },
            hrvBaselineMs: comp("hrv")?.baseline.map { Int($0.rounded()) },
            steps: a?.metrics.steps.map { Int(($0 / 100).rounded() * 100) },
            activeKcal: a?.metrics.activeEnergy.map { Int(($0 / 10).rounded() * 10) },
            trends: Dictionary(uniqueKeysWithValues: (a?.trends ?? []).map { ($0.metric, $0.direction.rawValue) })
        )
    }
}
