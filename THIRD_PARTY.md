# Зависимости

- Flutter SDK — BSD-3-Clause: https://github.com/flutter/flutter/blob/3.35.7/LICENSE
- bluetooth_low_energy 6.2.1 и его реализации для платформ — MIT:
  https://github.com/yanshouwang/bluetooth_low_energy
- Точный граф Dart-зависимостей зафиксирован в `pubspec.lock`.
  Лицензии транзитивных пакетов включаются Flutter в стандартный реестр лицензий.
- Графика карт создаётся виджетами и векторными путями мастей; сторонние изображения
  карточных колод не использованы.

- Исследован card_game (MIT), https://github.com/jlogical-apps/card_game ; код пакета в приложении не используется. Анимации написаны на стандартном Flutter AnimationController.
