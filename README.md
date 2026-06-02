# BT Sentinel

Минимальный iPhone-прототип для мониторинга новых BLE-устройств рядом.

## Что делает

- Сканирует Bluetooth Low Energy advertising через CoreBluetooth.
- Подает короткий двухтональный сигнал при первом появлении неизвестного BLE-устройства.
- Показывает имя, RSSI, примерную дистанцию в метрах, ориентировочное направление, локальный CoreBluetooth UUID и краткие advertising-данные.
- Позволяет запомнить текущие устройства как известные.
- Автоматически запоминает неизвестное устройство, если оно висит в эфире дольше 10 секунд.
- Сохраняет базу известных устройств в UserDefaults.

## Ограничения iOS

- iPhone-приложение не видит "вообще все" Bluetooth-устройства. CoreBluetooth обнаруживает BLE-периферии, которые рекламируются в эфире.
- iOS не дает приложению MAC-адрес устройства; используется локальный `CBPeripheral.identifier`.
- Дистанция считается приблизительно по RSSI и зависит от стен, тела, антенн, мощности передатчика и помех.
- Направление не приходит из Bluetooth напрямую. Приложение использует компас iPhone и запоминает, в каком направлении сигнал устройства был сильнее. Для оценки направления медленно повернитесь с телефоном на 360 градусов.
- Фоновое сканирование ограничено системой. `bluetooth-central` включен, но надежнее держать приложение активным на экране.
- Симулятор не подходит для проверки реального Bluetooth-сканирования. Нужен физический iPhone.

Официальные ориентиры Apple:

- Core Bluetooth: https://developer.apple.com/documentation/corebluetooth/
- `scanForPeripherals`: https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/scanforperipherals(withservices:options:)
- Background Processing: https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html

## Запуск

1. Откройте `BluetoothSentinel.xcodeproj` в Xcode.
2. В target `BluetoothSentinel` выберите свою команду подписи.
3. Запустите на физическом iPhone.
4. Разрешите доступ к Bluetooth.
5. Нажмите `Запомнить текущие`, когда окружение считается нормальным.

После этого новое BLE-устройство в зоне обнаружения должно вызвать звуковой сигнал.
