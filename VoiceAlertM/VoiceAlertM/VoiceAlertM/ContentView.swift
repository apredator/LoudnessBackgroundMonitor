import SwiftUI
import Combine
import AudioToolbox
import AVFoundation

struct ContentView: View {
    @StateObject private var vm = MonitorViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("Порог срабатывания: \(Int(vm.threshold)) dB")
                .font(.headline)

            Slider(value: $vm.threshold, in: (-60 ... -10), step: 1) {
                Text("Threshold")
            }
            .padding()
//            .onChange(of: vm.threshold) { new in
//                vm.setThreshold(Float(new))
            .onChange(of: vm.threshold) { oldValue, newValue in
                vm.setThreshold(Float(newValue))
                    }

            Toggle("Включать вспышку при оповещении", isOn: $vm.torchEnabled)
                .padding(.horizontal)

            HStack(spacing: 20) {
                Button(action: vm.toggleRunning) {
                    Text(vm.isRunning ? "Остановить" : "Запустить")
                        .frame(minWidth: 120)
                }
                Button("Калибровать") {
                    vm.calibrate()
                }
            }

            Spacer()
            Text(vm.statusText)
                .foregroundColor(.gray)
                .font(.footnote)
                .padding()
        }
        .padding()
        .onAppear { vm.setup() }
    }
}

final class MonitorViewModel: ObservableObject {
    private let monitor = LoudnessBackgroundMonitor()
    @Published var threshold: Double = -30 { didSet { monitor.setThreshold(db: Float(threshold)) } }
    @Published var isRunning = false
    @Published var torchEnabled = false
    @Published var statusText = "Готов"
    
    func setup() {
        monitor.requestPermissions { [weak self] granted in
            DispatchQueue.main.async {
                if !granted {
                    self?.statusText = "Разрешения не даны (микрофон/уведомления)"
                } else {
                    self?.statusText = "Разрешения получены"
                }
            }
        }
        
        monitor.prepareSilentLoopIfNeeded()
        
        monitor.onDetectedInForeground = { [weak self] in
            DispatchQueue.main.async {
                self?.vibrateImmediate()
                if self?.torchEnabled == true { self?.flashOnce() }
                self?.statusText = "Срабатывание (foreground) — \(Date())"
            }
        }
        
        monitor.onDetectedInBackground = { [weak self] in
            DispatchQueue.main.async {
                if self?.torchEnabled == true { self?.flashOnce() }
                self?.statusText = "Срабатывание (background) — \(Date())"
            }
        }
    }
    
    func toggleRunning() {
        if isRunning {
            monitor.stop()
            isRunning = false
            statusText = "Остановлено"
        } else {
            do {
                try monitor.start(silentLoop: true)
                isRunning = true
                statusText = "Мониторинг запущен"
            } catch {
                statusText = "Ошибка старта: \(error.localizedDescription)"
            }
        }
    }
    
    func setThreshold(_ db: Float) { monitor.setThreshold(db: db) }
    
    func calibrate() {
        statusText = "Калибровка..."
        monitor.calibrate { [weak self] new in
            DispatchQueue.main.async {
                self?.threshold = Double(new)
                self?.statusText = "Калибровано: \(Int(new)) dB"
            }
        }
    }
    
    private func vibrateImmediate() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    
    private func flashOnce() {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }

        var locked = false
        do {
            try device.lockForConfiguration()
            locked = true

            try device.setTorchModeOn(level: 0.8)

            // Отключаем torch и снимаем блокировку спустя 0.25 сек
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                // выключаем вспышку (без try/catch — присваивание безопасно)
                device.torchMode = .off
                if locked {
                    device.unlockForConfiguration()
                    // при желании: locked = false
                }
            }
        } catch {
            // Если что-то пошло не так — попытаться безопасно вернуть устройство в исходное состояние
            if device.isTorchActive {
                device.torchMode = .off
            }
            if locked {
                device.unlockForConfiguration()
            }
            print("Torch error: \(error)")
        }
    }
}
