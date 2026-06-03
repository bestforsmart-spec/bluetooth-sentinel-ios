# BT Sentinel Mac

macOS-версия BT Sentinel 1.0 beta для MacBook.

## Что работает

- BLE-сканирование через CoreBluetooth.
- Тихий старт 60 секунд без сигналов.
- Безымянные устройства называются `Новый 1`, `Новый 2`, `Новый 3`.
- Короткий сигнал при новом устройстве после тихого старта.
- Другой сигнал при устойчивом сближении.
- 8-секундная стабилизация RSSI и 12-секундное окно сближения.
- Компактная таблица устройств и детальная панель.

## Сборка

```bash
cd macos
chmod +x scripts/build_app.sh
./scripts/build_app.sh
```

Готовое приложение:

```text
packages/BT Sentinel Mac.app
```

Архив для передачи:

```text
packages/BT-Sentinel-Mac-1.0-beta.zip
```

## Запуск

1. Откройте `BT Sentinel Mac.app`.
2. Разрешите доступ к Bluetooth, если macOS спросит.
3. Дождитесь тихого старта.

Если macOS блокирует приложение после скачивания из GitHub, откройте его через правый клик -> `Open`. Второй вариант:

```bash
xattr -dr com.apple.quarantine "BT Sentinel Mac.app"
open "BT Sentinel Mac.app"
```

## Важно

Приложение слушает только BLE advertising-пакеты, доступные CoreBluetooth. Оно не сканирует Wi-Fi, SDR-диапазоны, Bluetooth Classic и скрытые устройства, которые не передают BLE advertising.
