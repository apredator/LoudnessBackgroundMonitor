# VoiceAlert iOS

Минимальный SwiftUI-приложение для мониторинга уровня громкости (в фоне) с оповещением вибрацией и опциональной вспышкой.

Файлы:
- VoiceAlertApp.swift
- ContentView.swift
- LoudnessBackgroundMonitor.swift
- Info.plist (минимальные ключи; доработайте под ваш проект)
- silent_placeholder.txt (положите сюда короткий silent.mp3 в проекте)

Инструкция быстрой сборки
1) В Xcode создайте новый проект App -> SwiftUI, Language Swift, назовите проект "VoiceAlert" или оставьте как есть.
2) Скопируйте файлы из этого репозитория в ваш target.
3) Добавьте в проект короткий silent.mp3 (1-2 сек тишины) и убедитесь, что он включён в target.
4) В Info.plist должны быть указаны ключи NSMicrophoneUsageDescription, NSCameraUsageDescription и UIBackgroundModes (audio). В проекте уже есть минимальный Info.plist — проверьте и настройте его.
5) В Xcode -> Capabilities -> Background Modes включите "Audio, AirPlay, and Picture in Picture".
6) Запускать и тестировать нужно на реальном устройстве.

Примечания
- Приложение использует фоновый режим audio и silent loop, чтобы удерживать аудиосессию в фоне. Apple может потребовать объяснение использования микрофона/фонового аудио при публикации.
- Torch (вспышка) требует NSCameraUsageDescription и может быть ограничена в фоне на некоторых устройствах.
