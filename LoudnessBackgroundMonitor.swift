import Foundation
import AVFoundation
import UserNotifications
import AudioToolbox
import Accelerate
import UIKit

final class LoudnessBackgroundMonitor {
    private let engine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()
    private var smoothingFactor: Float = 0.85
    private var smoothedDb: Float = -160
    private(set) var thresholdDb: Float = -30
    private var lastTriggerTime: Date = .distantPast
    private let triggerCooldown: TimeInterval = 1.0

    private var silentPlayer: AVAudioPlayer?

    var onDetectedInForeground: (() -> Void)?
    var onDetectedInBackground: (() -> Void)?

    func requestPermissions(completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var micGranted = false
        var notifGranted = false

        group.enter()
        session.requestRecordPermission { granted in
            micGranted = granted
            group.leave()
        }

        group.enter()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            notifGranted = granted
            group.leave()
        }

        group.notify(queue: .main) {
            completion(micGranted && notifGranted)
        }
    }

    func prepareSilentLoopIfNeeded(fileName: String = "silent", fileExt: String = "mp3") {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExt) else { return }
        do {
            silentPlayer = try AVAudioPlayer(contentsOf: url)
            silentPlayer?.numberOfLoops = -1
            silentPlayer?.volume = 0.0
            silentPlayer?.prepareToPlay()
        } catch {
            print("Silent player init error: \(error)")
        }
    }

    func start(silentLoop: Bool = true) throws {
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.mixWithOthers, .defaultToSpeaker])
        try session.setActive(true, options: [])

        if silentLoop {
            silentPlayer?.play()
        }

        let input = engine.inputNode
        let bus = 0
        let format = input.inputFormat(forBus: bus)

        input.removeTap(onBus: bus)
        input.installTap(onBus: bus, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameLength = Int(buffer.frameLength)

            // вычисление RMS (vDSP)
            var rms: Float = 0
            vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameLength))
            let minRms: Float = 1e-8
            let safeRms = max(rms, minRms)
            let db = 20.0 * log10f(safeRms)

            self.smoothedDb = self.smoothingFactor * self.smoothedDb + (1 - self.smoothingFactor) * db

            if self.smoothedDb > self.thresholdDb {
                let now = Date()
                if now.timeIntervalSince(self.lastTriggerTime) > self.triggerCooldown {
                    self.lastTriggerTime = now
                    DispatchQueue.main.async {
                        self.handleDetection()
                    }
                }
            }
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        silentPlayer?.stop()
        try? session.setActive(false)
    }

    private func handleDetection() {
        if UIApplication.shared.applicationState == .active {
            onDetectedInForeground?()
        } else {
            scheduleLocalNotification()
            onDetectedInBackground?()
        }
    }

    private func scheduleLocalNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Громкий звук"
        content.body = "Обнаружен высокий уровень громкости"
        content.sound = UNNotificationSound.default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    func setThreshold(db: Float) {
        thresholdDb = db
    }

    func calibrate(duration: TimeInterval = 2.0, offsetDb: Float = 6.0, completion: @escaping (Float) -> Void) {
        var samples: [Float] = []
        let start = Date()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] t in
            guard let s = self else { t.invalidate(); return }
            samples.append(s.smoothedDb)
            if Date().timeIntervalSince(start) >= duration {
                t.invalidate()
                let mean = samples.reduce(0, +) / Float(max(samples.count, 1))
                let newThreshold = mean + offsetDb
                self?.thresholdDb = newThreshold
                completion(newThreshold)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
