import SwiftData
import SwiftUI

// ============================================================================
// VoiceEntrySheet — 说一笔:语音 → 文字 → 结构化账单 → 一键落库
// 流程: 点麦克风说话 → 实时转写 → 停止后解析出金额/分类/类型 → 确认保存
// 保存口径与 AddExpenseSheet / AddIncomeSheet 1:1 对齐(cash 联动 + firstRecordDate 维护)
// ============================================================================

struct VoiceEntrySheet: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @StateObject private var recorder = VoiceRecorder()
    @Query private var expenses: [Expense]
    @Query private var assetsArr: [UserAssets]

    @State private var bill: AmountParser.Bill?
    @State private var savedToast: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    micSection
                    transcriptCard
                    statusFooter

                    if recorder.state == .done, let b = bill {
                        resultCard(b)
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
                bill = AmountParser.parse(recorder.transcript)
            case .idle:
                bill = nil
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
                    // 录音中: 音量驱动的呼吸光环
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
                .stroke(Color.hairlineSoft, lineWidth: 1)
        )
    }

    private var transcriptPlaceholder: String {
        switch recorder.state {
        case .idle:
            return "例: 星巴克花了三十五块五 / 工资一万二到账 / 地铁4元"
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

    @ViewBuilder
    private var statusFooter: some View {
        if recorder.state == .denied {
            VStack(spacing: 10) {
                Text("权限没开")
                    .font(.system(.headline, design: .rounded))
                Text("设置 → 隐私与安全性 → 麦克风 / 语音识别,\n把念念有账打开就能用了。")
                    .font(.system(.footnote, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.md)
        }
    }

    // ============================================================================
    // MARK: - 解析结果卡
    // ============================================================================

    private func resultCard(_ b: AmountParser.Bill) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            KickerLabel(text: "解析结果")

            if b.fuzzy && b.amount != nil {
                Label("金额听起来有点模糊,核对一下", systemImage: "exclamationmark.circle")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Color.incomeGold)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(b.amount.map(formatYuan) ?? "没听到金额")
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(b.isIncome ? Color.mossGreen : Color.flame)
                Spacer()
                Text(b.isIncome ? "收入" : "支出")
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background((b.isIncome ? Color.mossGreen : Color.flame).opacity(0.12))
                    .foregroundStyle(b.isIncome ? Color.mossGreen : Color.flame)
                    .clipShape(Capsule())
            }

            LabeledRow(label: "分类", value: b.category)
            LabeledRow(label: "备注", value: b.title)

            if b.amount != nil {
                HStack(spacing: Spacing.sm) {
                    VaultButton(title: "记支出", icon: "minus", style: .destructive) {
                        save(amount: b.amount!, asIncome: false)
                    }
                    VaultButton(title: "记收入", icon: "plus", style: .primary) {
                        save(amount: b.amount!, asIncome: true)
                    }
                }
                .padding(.top, 4)
            }

            GhostButton(title: "重新说一遍", icon: "arrow.counterclockwise") {
                bill = nil
                recorder.resetForNewRun()
            }
            .frame(maxWidth: .infinity)
        }
        .padding(Spacing.md)
        .background(Color.mist)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.hairlineSoft, lineWidth: 1)
        )
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// 结果卡的紧凑键值行
    private struct LabeledRow: View {
        let label: String
        let value: String
        var body: some View {
            HStack {
                Text(label)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Color.inkFaint)
                Spacer()
                Text(value)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Color.ink)
            }
        }
    }

    // ============================================================================
    // MARK: - 保存(与手动记账完全同口径)
    // ============================================================================

    private func save(amount amt: Double, asIncome incomeMode: Bool) {
        guard FinancialFormatting.validAmount(amt) else { return }
        let resultingCash = (assetsArr.first?.cash ?? 0) + (incomeMode ? amt : -amt)
        guard resultingCash.isFinite && abs(resultingCash) <= FinancialLimits.maximumAmount else { return }
        guard let b = bill else { return }

        let assets: UserAssets
        if let existing = assetsArr.first {
            assets = existing
        } else {
            assets = UserAssets(total: 0)
            modelContext.insert(assets)
        }

        if incomeMode {
            let src = b.title.trimmingCharacters(in: .whitespacesAndNewlines)
            // 与 AddIncomeSheet 同口径: isPassive 新建一律 false,被动收入由 PassiveSource 承载
            let income = Income(amount: amt, source: src.isEmpty ? "收入" : src,
                                isPassive: false, note: "", date: .now)
            modelContext.insert(income)
            assets.cash += amt
        } else {
            let expense = Expense(amount: amt, category: b.category, note: b.title, date: .now)
            modelContext.insert(expense)
            assets.cash -= amt
            assets.firstRecordDate = min(FreedomMath.earliestExpenseDate(expenses) ?? .now, .now)
        }
        assets.updatedAt = .now

        dismiss()
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