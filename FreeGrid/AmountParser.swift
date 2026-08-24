import Foundation

// ============================================================================
// AmountParser — 语音文本 → 结构化账单
// 从微信版 miniprogram/utils/parser.js 1:1 移植 (2026-08-24)
// 样板用例(全过):
//   "工资一万二"      → 12000 收入
//   "三万五千奖金"     → 35000 收入
//   "一百零五"        → 105
//   "在星巴克花了三十五块五喝咖啡" → 35.5 餐饮
//   "地铁4元"         → 4 交通
//   "8月23日花了20块"  → 20 (日期干扰被带单位优先规则排除)
// ============================================================================

enum AmountParser {

    struct Bill {
        var amount: Double?
        var category: String      // ExpenseCategory.canonical 之一
        var isIncome: Bool
        var isPassive: Bool       // Income.isPassive 口径: 利息/股息/分红
        var title: String
        var fuzzy: Bool           // "二十多""大概三百" 或没解析出金额
    }

    // MARK: - 中文数字 → Int

    private static let digits: [Character: Int] = [
        "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]
    private static let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000]

    /// 口语缩读: "一万二"→12000 / "三万五"→35000 / "一百零五"→105
    static func chineseToInt(_ text: String) -> Int? {
        var total = 0, section = 0, num = 0
        var lastWasTenThousand = false
        for ch in text {
            if let d = digits[ch] {
                num = d
            } else if let u = units[ch] {
                section += (num == 0 ? 1 : num) * u
                num = 0
            } else if ch == "万" {
                total = (total + section + num) * 10_000
                section = 0; num = 0
                lastWasTenThousand = true
            } else if ch == "亿" {
                total = (total + section + num) * 100_000_000
                section = 0; num = 0
                lastWasTenThousand = false
            } else {
                return nil   // 出现非数字字符即失败
            }
        }
        // 万之后的裸数字默认补"千" —— 微信版实战修过的坑,原样保留
        if lastWasTenThousand && num > 0 && section == 0 { num *= 1000 }
        return total + section + num
    }

    // MARK: - 金额提取

    /// 优先级: ①带"块/元/圆"的阿拉伯数字(避开日期干扰) → ②裸阿拉伯数字 → ③最长中文数字串
    static func extractAmount(_ text: String) -> Double? {
        // ① 带单位的阿拉伯数字优先
        if let s = firstCapture("(\\d+(?:\\.\\d{1,2})?)\\s*[块元圆]", text), let v = Double(s) {
            return v
        }
        // ② 裸阿拉伯数字兜底
        if let s = firstCapture("(\\d+(?:\\.\\d{1,2})?)", text), let v = Double(s) {
            return v
        }
        // ③ 中文数字串: 取能转成功且最长的串(避免"星期三"之类短串误判)
        guard let re = try? NSRegularExpression(pattern: "[零一二两三四五六七八九十百千万亿]+") else { return nil }
        let ns = text as NSString
        var best: (value: Int, len: Int)? = nil
        re.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.range.location != NSNotFound else { return }
            let seg = ns.substring(with: m.range)
            if let v = chineseToInt(seg), v > 0, best == nil || seg.count > best!.len {
                best = (v, seg.count)
            }
        }
        if let v = best?.value { return Double(v) }
        return nil
    }

    // MARK: - 模糊表达

    /// "二十多" "大概三百" "几十块" → 让 UI 提示用户核对金额
    static func isFuzzy(_ text: String) -> Bool {
        text.range(of: "多|大概|大约|左右|几十|几块", options: .regularExpression) != nil
    }

    // MARK: - 分类映射(FreeGrid canonical 9 类)

    private static let breakfastWords = ["早饭", "早点", "早餐", "豆浆", "油条", "包子"]
    private static let lunchWords     = ["午饭", "午餐"]
    private static let dinnerWords    = ["晚饭", "晚餐", "宵夜", "夜宵"]
    /// 通用吃喝词 → 按当前时段猜早/午/晚
    private static let mealWords = ["吃", "喝", "饭", "餐", "咖啡", "奶茶", "外卖", "面条",
                                    "米粉", "菜", "零食", "水果", "烧烤", "火锅", "酒",
                                    "星巴克", "瑞幸", "麦当劳", "肯德基", "海底捞"]
    private static let transportWords = ["打车", "滴滴", "地铁", "公交", "火车", "高铁", "机票",
                                         "飞机", "加油", "停车", "过路费", "单车", "出行"]
    private static let funWords       = ["电影", "游戏", "ktv", "旅游", "门票", "演出", "健身", "会员"]
    private static let medicalWords   = ["药", "医院", "挂号", "看病", "体检", "诊所"]
    private static let growthWords    = ["书", "课程", "培训", "学费", "网课", "考试"]
    private static let shoppingWords  = ["买", "淘宝", "京东", "拼多多", "超市", "衣服", "鞋",
                                         "包", "化妆品", "日用品"]

    private static let incomeWords   = ["工资", "薪水", "薪资", "奖金", "报销", "稿费",
                                        "分红", "收入", "到账", "进账"]
    private static let passiveWords  = ["利息", "股息", "分红", "房租"]

    private static func containsAny(_ words: [String], in text: String) -> Bool {
        words.contains { text.contains($0) }
    }

    /// 没指明哪顿的吃喝 → 按时段猜
    private static func guessMeal() -> String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11:  return "早餐"
        case 11..<15: return "午餐"
        default:      return "晚餐"
        }
    }

    static func detectCategory(_ text: String) -> String {
        let lower = text.lowercased()
        if containsAny(breakfastWords, in: text) { return "早餐" }
        if containsAny(lunchWords, in: text)     { return "午餐" }
        if containsAny(dinnerWords, in: text)    { return "晚餐" }
        if containsAny(mealWords, in: lower)     { return guessMeal() }
        if containsAny(transportWords, in: text) { return "交通" }
        if containsAny(funWords, in: lower)      { return "娱乐" }
        if containsAny(medicalWords, in: text)   { return "医疗" }
        if containsAny(growthWords, in: text)    { return "成长投资" }
        if containsAny(shoppingWords, in: text)  { return "购物" }
        return "其他"
    }

    static func detectIncome(_ text: String) -> (isIncome: Bool, isPassive: Bool) {
        let isPassive = containsAny(passiveWords, in: text)
        let isIncome = containsAny(incomeWords, in: text) || isPassive
        return (isIncome, isPassive)
    }

    // MARK: - 标题

    /// 去掉数字和动词,取前 6 个字当备注标题
    static func makeTitle(_ text: String, fallback: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "[零一二两三四五六七八九十百千万亿\\d.]+", with: "", options: .regularExpression)
        for w in ["在", "花了", "花费", "支付", "付了", "块钱", "元", "圆", "记一笔", "一下"] {
            t = t.replacingOccurrences(of: w, with: "")
        }
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = String(trimmed.prefix(6))
        return head.isEmpty ? fallback : head
    }

    // MARK: - 主入口

    static func parse(_ raw: String) -> Bill {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = extractAmount(text)
        let cat = detectCategory(text)
        let inc = detectIncome(text)
        let fallback = inc.isIncome ? "收入" : "\(cat)支出"
        return Bill(
            amount: amount,
            category: cat,
            isIncome: inc.isIncome,
            isPassive: inc.isPassive,
            title: makeTitle(text, fallback: fallback),
            fuzzy: isFuzzy(text) || amount == nil
        )
    }

    // MARK: - Regex helper

    private static func firstCapture(_ pattern: String, _ text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1,
              m.range(at: 1).location != NSNotFound else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
