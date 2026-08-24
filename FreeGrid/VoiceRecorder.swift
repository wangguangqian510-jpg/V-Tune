import AVFoundation
import Combine
import Speech

// ============================================================================
// VoiceRecorder — SFSpeechRecognizer zh-CN 实时语音转文字
// 点击开始 / 点击结束 (微信版验证过的交互模式,按住说话的时序坑不重踩)
// 设备端识别优先 (iOS 17.6+ 支持离线,免费无限次);不支持时回落苹果服务器。
// ============================================================================

@MainActor
final class VoiceRecorder: ObservableObject {

    enum State: Equatable {
        case idle
        case recording
        case done
        case denied          // 麦克风或语音识别权限被拒
        case failed(String)  // 带人话原因的失败
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var transcript = ""

    /// 录音中脉冲动画驱动 (0..1)
    @Published private(set) var audioLevel: Double = 0

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private var recognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    }()

    // MARK: - 公共入口: 点一下开始,再点一下结束

    func toggle() {
        switch state {
        case .recording:
            stop()
        case .idle, .done, .failed:
            start()
        case .denied:
            break // UI 层引导去设置,这里不重复请求
        }
    }

    func resetForNewRun() {
        teardownAudio()
        transcript = ""
        audioLevel = 0
        state = .idle
    }

    // MARK: - 开始录音 + 识别

    private func start() {
        Task { [weak self] in
            guard let self else { return }

            // ① 权限双请求(麦克风 + 语音识别)
            let micOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
            }
            let speechOK = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    c.resume(returning: status == .authorized)
                }
            }
            guard micOK, speechOK else {
                self.state = .denied
                return
            }

            // ② 识别器可用性
            guard let recognizer = self.recognizer, recognizer.isAvailable else {
                self.state = .failed("识别服务暂不可用,稍后再试")
                return
            }

            // ③ 音频会话(测量模式,避免系统 AGC 干扰识别)
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setCategory(.playAndRecord, mode: .measurement, options: .duckOthers)
                try session.setActive(true, options: .notifyOthersOnDeactivation)
            } catch {
                self.state = .failed("麦克风初始化失败")
                return
            }

            // ④ 清场后起引擎
            self.teardownAudio()
            self.transcript = ""
            self.audioLevel = 0

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            if recognizer.supportsOnDeviceRecognition {
                req.requiresOnDeviceRecognition = true   // 离线免费无限制
            }
            self.request = req

            let input = self.engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                self.state = .failed("录音格式异常")
                return
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                req.append(buffer)
                Task { @MainActor [weak self] in
                    self?.sampleLevel(buffer)
                }
            }
            self.engine.prepare()
            do {
                try self.engine.start()
            } catch {
                self.state = .failed("录音启动失败")
                return
            }
            self.state = .recording

            // ⑤ 识别任务: partial 结果实时刷 transcript
            self.task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let result {
                        let text = result.bestTranscription.formattedString
                        if !text.isEmpty { self.transcript = text }
                    }
                    if error != nil || result?.isFinal == true {
                        if self.state == .recording {
                            let ok = !self.transcript.isEmpty
                            self.finishRecording(success: ok,
                                                 reason: ok ? nil : "识别中断,再试一次")
                        }
                    }
                }
            }
        }
    }

    // MARK: - 手动停止(点击结束)

    func stop() {
        request?.endAudio()
        finishRecording(success: !transcript.isEmpty,
                        reason: transcript.isEmpty ? "没听清,再试一次" : nil)
    }

    private func finishRecording(success: Bool, reason: String?) {
        teardownAudio()
        if success {
            state = .done
        } else {
            state = .failed(reason ?? "没听清,再试一次")
        }
    }

    // MARK: - 音量采样(按钮脉冲动画用)

    private func sampleLevel(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += channel[i] * channel[i] }
        let rms = sqrt(sum / Float(n))
        let db = 20 * log10(max(rms, 1e-6))          // -60..0
        audioLevel = Double(min(max((db + 60) / 60, 0), 1))   // 归一 0..1
    }

    // MARK: - 清理

    private func teardownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        task?.cancel(); task = nil
        request = nil
    }
}