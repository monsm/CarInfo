// =============================================================================
// N43/N44/N45 语音播报系统 — 上车/下车/充电完成 TTS
// =============================================================================

import Foundation
import AVFoundation
import SwiftUI

class VoiceBroadcastManager: ObservableObject {
    static let shared = VoiceBroadcastManager()
    
    @Published var isSpeaking: Bool = false
    @Published var currentMessage: String = ""
    
    private let synthesizer = AVSpeechSynthesizer()
    private var enabled: Bool {
        UserDefaults.standard.bool(forKey: "carkeeper_voice_enabled")
    }
    
    private init() {}
    
    // N43 上车打卡语音播报
    func speakCheckIn(car: [String: Any]?) {
        guard enabled else { return }
        let plate = car?["plate"] as? String ?? "您的爱车"
        let msg = "欢迎使用\(plate)，祝您一路平安"
        speak(msg)
    }
    
    // N44 下车打卡语音播报
    func speakCheckOut(distanceKm: Double, energyKWh: Double, socEnd: Int) {
        guard enabled else { return }
        let msg = "行程结束，本次行驶\(String(format: "%.1f", distanceKm))公里，耗电\(String(format: "%.1f", energyKWh))千瓦时，当前电量\(socEnd) percent"
        speak(msg)
    }
    
    // N45 充电完成倒计时语音播报
    func speakChargeComplete(soc: Int, range: Int, minutesLeft: Int) {
        guard enabled else { return }
        if minutesLeft > 0 {
            let msg = "充电进行中，预计还需\(minutesLeft)分钟充满，当前电量\(soc) percent，续航约\(range)公里"
            speak(msg)
        } else {
            let msg = "充电已完成，当前电量\(soc) percent，续航约\(range)公里"
            speak(msg)
        }
    }
    
    // N45 充电进行中语音
    func speakChargingProgress(soc: Int, minutesLeft: Int) {
        guard enabled else { return }
        let msg = "正在充电，当前电量\(soc) percent，预计\(minutesLeft)分钟后充满"
        speak(msg)
    }
    
    private func speak(_ text: String) {
        guard !synthesizer.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        isSpeaking = true
        currentMessage = text
        synthesizer.speak(utterance)
        
        synthesizer.delegate = self
    }
}

extension VoiceBroadcastManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
            self.currentMessage = ""
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterate) {
        DispatchQueue.main.async { self.isSpeaking = true }
    }
}

// MARK: - Voice Broadcast Settings Card
struct VoiceBroadcastCard: View {
    @StateObject private var vm = VoiceBroadcastManager.shared
    @AppStorage("carkeeper_voice_enabled") private var enabled = false
    
    var body: some View {
        CardBox(title: "语音播报") {
            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("启用语音播报")
                            .font(.subheadline)
                        Text("上车/下车/充电时语音提示")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $enabled)
                        .labelsHidden()
                }
                
                if vm.isSpeaking {
                    HStack {
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.accent)
                            .pulseAnimation()
                        Text(vm.currentMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

extension View {
    func pulseAnimation() -> some View {
        self.animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: true)
    }
}
