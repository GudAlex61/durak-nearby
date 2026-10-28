# iOS 0.3.0

Код игры, бот, 24/36 карт, переводной режим и анимации общие для Android
и iOS. Нативный iOS-проект: `ios/Runner.xcworkspace`, bundle ID
`dev.duraknearby.durakBt`, минимум iOS 13. Bluetooth Usage Descriptions
заданы, бот не запрашивает доступ к Bluetooth.

## Проверка на Mac

Установите Flutter 3.35.7, Xcode и CocoaPods. Затем из корня проекта:

```sh
bash tool/ios_check.sh
```

Скрипт выполнит анализ и тесты, соберёт и установит приложение в iPhone
Simulator, запустит интеграционный сценарий и сделает скриншот. Затем проверит
сборку для реального arm64 iPhone без подписи. В `dist` будут ZIP с `.app`:
симуляторный и неподписанный для устройства. Скрипт ничего не публикует.

## Установка на настоящий iPhone

Откройте `ios/Runner.xcworkspace` в Xcode, выберите Runner → Signing &
Capabilities → Team (свой Apple ID), подключите iPhone и нажмите Run.
Для TestFlight используйте Apple Developer Program, собственный bundle ID и
`flutter build ipa --release`. Подписанный IPA появляется в `build/ios/ipa`.
Неподписанный `.app` нельзя установить как готовый IPA.

## Автоматически на GitHub

Содержимое проекта разместите в корне своего репозитория. Actions → Mobile
checks → Run workflow. macOS job вызывает тот же скрипт; сборки и скриншот
будут в артефакте DurakNearby-iOS. Workflow подготовлен, но из текущей среды
не запущен: здесь нет Mac и доступа к GitHub-репозиторию для этого проекта.

Проверки Flutter с TargetPlatform.iOS — проверки интерфейса, а не запуск
iOS Simulator. Они не заменяют Xcode-компиляцию и проверку Bluetooth на паре
физических телефонов.

Официальная инструкция: https://docs.flutter.dev/deployment/ios

## IPA для установки с Windows

Скрипт теперь также упаковывает iPhoneOS .app в `Payload/Runner.app` и создаёт
`dist/DurakNearby-ios-unsigned.ipa`. Валидатор отвергает simulator bundle и
проверяет метаданные и Mach-O. Это структурная проверка, не проверка запуска
или подписи. После macOS-сборки IPA подписывается локально через AltServer.
Пошаговая инструкция — `docs/IPHONE_INSTALL.md`. Здесь IPA ещё не собран:
доступ к macOS/GitHub runner не подключён.
