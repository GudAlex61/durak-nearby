# iOS 0.3.1

Готов нативный iPhone IPA: `DurakNearby-ios-unsigned.ipa`, версия 0.3.1,
сборка 5, ARM64, минимум iOS 13. Собран Xcode 26.6 / iPhoneOS SDK 26.5
на macOS; готовое приложение — 16.1 МБ до упаковки.

Bundle ID: `dev.duraknearby.durakBt`. Правила, бот, 24/36 карт, переводной
режим, перетаскивание, кнопка «Взять» и анимации общие с Android.

## Готовая сборка

https://github.com/GudAlex61/durak-nearby/actions/runs/40641671235

Анализ без замечаний; 67 тестов прошли; iPhone ARM64 Release собран;
структура Payload, Info.plist, платформа iphoneos и Mach-O проверены.
IPA не подписан. Установка с Windows через локальную подпись AltStore:
`docs/IPHONE_INSTALL.md`. Установка на физический iPhone и радиообмен BLE
между телефонами в этой работе пока не проверены.

Сценарий запуска игры с ботом и выхода в меню пройден на iPhone Simulator:
https://github.com/GudAlex61/durak-nearby/actions/runs/40648425021

## Пересборка

В Actions доступны независимые проверки симулятора и сборка iPhone IPA.
Для локального запуска на Mac установите Flutter 3.35.7, Xcode и CocoaPods:

```sh
flutter pub get
flutter analyze
flutter test --reporter expanded
flutter build ios --release --no-codesign
```

Для запуска через Xcode откройте `ios/Runner.xcworkspace`, выберите свою
Team в Signing & Capabilities и подключённый iPhone. Для TestFlight нужны
Apple Developer Program и подписанная сборка.

Проверки с TargetPlatform.iOS не равны запуску симулятора. Реальные результаты
и границы проверки записаны в `docs/TEST_REPORT.md`.
