# BT Sentinel Android

Android-версия BT Sentinel 1.0 beta для наблюдения за BLE-устройствами рядом.

## Что работает

- BLE-сканирование через `BluetoothLeScanner`.
- Тихий старт 60 секунд без сигналов.
- Безымянные устройства называются `Новый 1`, `Новый 2`, `Новый 3`.
- Новое устройство после тихого старта даёт короткий сигнал и вибро.
- Устойчивое сближение даёт другой короткий сигнал и вибро.
- RSSI стабилизируется через 8-секундное окно, trimmed median и deadband 3 dBm.
- UI обновляется раз в секунду.
- Новые устройства автоматически становятся известными через 5 минут стабильного наблюдения.
- Светлая/тёмная тема и переключатель звука.

## Установка APK

1. Передайте файл `BT-Sentinel-Android-1.0-beta-debug.apk` на Android-телефон.
2. Откройте файл на телефоне.
3. Разрешите установку из неизвестных источников для приложения, через которое открываете APK.
4. После запуска разрешите Bluetooth scan.

## Сборка из исходников

```bash
cd android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
export ANDROID_SDK_ROOT=/opt/homebrew/share/android-commandlinetools
gradle :app:assembleDebug
```

APK будет здесь:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

## Важно

Android-версия, как и iOS-версия, анализирует только доступные BLE advertising-пакеты. RSSI не является точной дистанцией: тело, рельеф, металл, влажность и мощность передатчика могут менять сигнал.
