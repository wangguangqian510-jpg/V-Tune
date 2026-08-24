import SwiftData
import SwiftUI

// ============================================================================
// VoiceEntrySheet — 说一笔:语音 → 文字 → 结构化账单(支持一句话多笔) → 一键落库
// 流程: 点麦克风说话 → 实时转写 → 停止后按标点/连接词拆段解析 → 逐笔核对 → 全部记下
// 保存口径与 AddExpenseSheet / AddIncomeSheet 1:1 对齐(cash 联动 + firstRecordDate 维护)
// ============================================================================

struct VoiceEntrySheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceRecorder()
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]

    @State private var bills: [AmountParser.Bill] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    micSection
                    transcriptCard

                    if recorder.state == .done, !bills.isEmpty {
                        resultSection
                    }
                }
                .padding(.horizontal, Spacing.md)
                .padding(.top, Spacing.lg)
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .background(Color.paper)
            .navigationTitle("说一笔")
            .inlineNavTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .foregroundStyle(Color.inkMuted)
                }
            }
        }
        .onChange(of: recorder.state) { _, s in
            switch s {
            case .done:
                bills = AmountParser.parseMultiple(recorder.transcript)
            case .idle:
                bills = []
            default:
                break
            }
        }
        .onDisappear { recorder.resetForNewRun() }
    }

    // ============================================================================
    // MARK: - 麦克风区
    // ============================================================================

    private var isRecording: Bool { recorder.state == .recording }

    private var micSection: some View {
        VStack(spacing: 14) {
            Button {
                recorder.toggle()
            } label: {
                ZStack {
                    if isRecording {
                        Circle()
                            .stroke(Color.flame.opacity(0.35), lineWidth: 2)
                            .frame(width: 128 + recorder.audioLevel * 26,
                                   height: 128 + recorder.audioLevel * 26)
                    }
                    Circle()
                        .fill(isRecording ? AnyShapeStyle(Color.flame) : AnyShapeStyle(Color.mist))
                        .frame(width: 108, height: 108)
                        .shadow(color: isRecording ? Color.flame.opacity(0.3) : .black.opacity(0.06),
                                radius: isRecording ? 14 : 5, y: 2)
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(isRecording ? Color.white : Color.ink)
                }
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: recorder.audioLevel)
            .animation(.easeInOut(duration: 0.18), value: isRecording)

            Text(isRecording ? "在听…说完点一下停止" : "点一下开始说话")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.inkFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // ============================================================================
    // MARK: - 转写卡
    // ============================================================================

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            KickerLabel(text: "你说的话")
            Text(transcriptPlaceholder)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(recorder.transcript.isEmpty ? Color.inkFaint : Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(Spacing.md)
        .background(Color.mist)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.hairlineSoft, lineWidth: 1)
        )
    }

    private var transcriptPlaceholder: String {
        switch recorder.state {
        case .idle:
            return "例: 星巴克花了三十五块五 / 发工资了一万二 / 多笔可连说: 午饭20，打车8块，再买杯咖啡15"
        case .recording:
            return recorder.transcript.isEmpty ? "听着呢…" : recorder.transcript
        case .done:
            return recorder.transcript
        case .denied:
            return "需要麦克风和语音识别权限才能用"
        case .failed(let msg):
            return msg
        }
    }

    // ============================================================================
    // MARK: - 解析结果区(多笔列表)
    // ============================================================================

    @ViewBuilder
    private var resultSection: some View {
        let hasFuzzy = bills.contains { $0.fuzzy }
        let totalValid = bills.filter { $0.amount != nil }.count

        VStack(spacing: 14) {
            HStack {
                KickerLabel(text: bills.count > 1 ? "解析出 \(bills.count) 笔" : "解析结果")
                Spacer()
                if bills.count > 1 {
                    Text("点 × 可去掉不要的")
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.inkGhost)
                }
            }

            if hasFuzzy && totalValid > 0 {
                Label("有金额听起来模糊,核对一下", systemImage: "exclamationmark.circle")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.incomeGold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            ForEach(Array(bills.enumerated()), id: \.element.id) { index, b in
                billRow(b, index: index)
            }

            if totalValid > 0 {
                VaultButton(title: bills.count > 1 ? "全部记下 · \(bills.count) 笔" : "记下这一笔",
                            icon: "checkmark.circle",
                            style: .primary) {
                    saveAll()
                }
                .padding(.top, 4)
            } else {
                Text("没听到金额,再试一次吧")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
            }

            GhostButton(title: "重新说一遍", icon: "arrow.counterclockwise") {
                bills = []
                recorder.resetForNewRun()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.md)
        .background(Color.mist)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.hairlineSoft, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// 单笔行卡
    private func billRow(_ b: AmountParser.Bill, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: b.isIncome ? "dollarsign.circle" : categoryIcon(b.category))
                .font(.system(size: 17))
                .foregroundStyle(b.isIncome ? Color.mossGreen : categoryTint(b.category))
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(b.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .lineLimit(1)
                Text("\(b.isIncome ? "收入" : "支出") · \(b.category)" + (b.fuzzy ? " · 金额模糊" : ""))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer(minLength: 8)
            Text(b.amount.map { ((b.isIncome ? "+" : "−") + formatYuan($0)) } ?? "—")
                .font(.system(.subheadline, design: .rounded, weight: .bold).monospacedDigit())
                .foregroundStyle(b.isIncome ? Color.mossGreen : Color.flame)
            Button {
                bills.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.inkGhost)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    private func categoryTint(_ c: String) -> Color {
        switch c {
        case "餐饮": return Color(red: 0.090, green: 0.698, blue: 0.416)
        case "交通": return Color(red: 0.184, green: 0.620, blue: 0.561)
        case "购物": return Color(red: 0.910, green: 0.635, blue: 0.239)
        case "娱乐": return Color(red: 0.478, green: 0.435, blue: 0.941)
        case "居住": return Color(red: 0.310, green: 0.557, blue: 0.969)
        case "医疗": return Color.flame
        default: return Color(red: 0.541, green: 0.592, blue: 0.549)
        }
    }

    private func categoryIcon(_ c: String) -> String {
        switch c {
        case "餐饮": return "fork.knife"
        case "交通": return "bus"
        case "购物": return "cart"
        case "娱乐": return "gamecontroller"
        case "居住": return "house"
        case "医疗": return "cross.case.fill"
        default: return "ellipsis.circle"
        }
    }

    // ============================================================================
    // MARK: - 批量保存(与手动记账完全同口径)
    // ============================================================================

    private func saveAll() {
        let valid = bills.filter {
            guard let a = $0.amount else { return false }
            return FinancialFormatting.validAmount(a)
        }
        guard !valid.isEmpty else { return }

        let assets = ensureAssets()

        for b in valid {
            let amt = b.amount!
            if b.isIncome {
                let src = b.title.trimmingCharacters(in: .whitespacesAndNewlines)
                // 与 AddIncomeSheet 同口径: isPassive 新建一律 false
                let income = Income(amount: amt, source: src.isEmpty ? "收入" : src,
                                    isPassive: false, note: "", date: .now)
                modelContext.insert(income)
                assets.cash += amt
            } else {
                let expense = Expense(amount: amt, category: b.category, note: b.title, date: .now)
                modelContext.insert(expense)
                assets.cash -= amt
            }
        }
        // 有支出时维护追踪基线(与 AddExpenseSheet 同口径)
        if valid.contains(where: { !$0.isIncome }) {
            assets.firstRecordDate = min(FreedomMath.earliestExpenseDate(expenses) ?? .now, .now)
        }
        assets.updatedAt = .now

        dismiss()
    }

    private func ensureAssets() -> UserAssets {
        if let existing = assetsArr.first { return existing }
        let a = UserAssets(total: 0)
        modelContext.insert(a)
        return a
    }

    /// 格式化金额: 与 AddExpenseSheet 相同的千分位实现
    private func formatYuan(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        let s = f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
        return "¥\(s)"
    }
}