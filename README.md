# OBS Controller

![GitHub release](https://img.shields.io/github/v/release/SL1ZN1T3L/Epsiquad-OBS-Controller)
![GitHub all releases](https://img.shields.io/github/downloads/SL1ZN1T3L/Epsiquad-OBS-Controller/total)
![Flutter](https://img.shields.io/badge/Flutter-3.6+-02569B?logo=flutter)
![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)
![License](https://img.shields.io/github/license/SL1ZN1T3L/Epsiquad-OBS-Controller)

Приложение для удалённого управления OBS Studio через WebSocket на Android.

## Возможности

- 📺 **Переключение сцен** — сетка кнопок для быстрого переключения
- 🔴 **Управление стримом** — старт/стоп трансляции
- ⏺️ **Управление записью** — старт/стоп/пауза записи
- 🎮 **Quick Control** — настраиваемая панель быстрых действий
- 👁️ **Источники сцены** — показать/скрыть элементы
- 🔊 **Аудио** — mute/unmute аудио источников
- 📷 **Виртуальная камера** — включение/выключение
- 💾 **Бэкап настроек** — экспорт/импорт конфигурации
- 🔗 **Несколько подключений** — сохранение настроек разных OBS
- 📱 **Работа в фоне** — соединение не рвётся при сворачивании
- 🔄 **Автообновления** — проверка и установка новых версий

## Требования

- OBS Studio 28+ (WebSocket встроен)
- Для OBS < 28: плагин [obs-websocket](https://github.com/obsproject/obs-websocket)
- Android 5.0+

---

## 📦 Установка

### Для пользователей

1. **Скачайте APK** из [последнего релиза](https://github.com/SL1ZN1T3L/Epsiquad-OBS-Controller/releases/latest)
2. **Установите APK** на Android устройство
3. При необходимости разрешите установку из неизвестных источников

### Настройка OBS

#### OBS 28+

1. Откройте OBS
2. Меню **Инструменты** → **Настройки WebSocket сервера**
3. Включите **Enable WebSocket server**
4. Запомните порт (по умолчанию 4455)
5. Если нужна авторизация — установите пароль

#### OBS < 28

1. Скачайте [obs-websocket](https://github.com/obsproject/obs-websocket/releases)
2. Установите плагин
3. Перезапустите OBS
4. Настройте в **Инструменты** → **WebSocket Server Settings**

### Первое подключение

1. Запустите приложение
2. Нажмите на строку статуса вверху
3. Добавьте новое подключение:
   - Название (опционально)
   - IP адрес компьютера с OBS
   - Порт (4455 по умолчанию)
   - Пароль (если установлен в OBS)
4. Нажмите на подключение для соединения

#### Поиск IP адреса

**Windows:**
```cmd
ipconfig
# Ищите IPv4 Address в секции Ethernet или Wi-Fi
```

**macOS/Linux:**
```bash
ifconfig | grep "inet "
# или
ip addr show
```

### Troubleshooting

#### Не подключается

1. Убедитесь что OBS запущен
2. Проверьте что WebSocket сервер включён в OBS
3. Проверьте IP адрес и порт
4. Убедитесь что устройства в одной сети
5. Проверьте файрвол на компьютере

#### Соединение рвётся

- Приложение использует foreground service для работы в фоне
- Проверьте настройки батареи для приложения
- Отключите оптимизацию батареи для OBS Controller

#### Неправильный пароль

- Пароль чувствителен к регистру
- Проверьте пароль в настройках OBS WebSocket
- Попробуйте отключить авторизацию для теста

---

## 🛠️ Разработка

### Требования

- Flutter 3.6+
- Android SDK
- Git

### Установка Flutter

```bash
# Проверка установки
flutter doctor

# Если Flutter не установлен:
# https://docs.flutter.dev/get-started/install
```

### Клонирование репозитория

```bash
git clone https://github.com/SL1ZN1T3L/Epsiquad-OBS-Controller.git
cd Epsiquad-OBS-Controller
flutter pub get
```

### Сборка

#### Debug APK

```bash
flutter build apk --debug
```

#### Release APK

```bash
flutter build apk --release
# APK будет в: build/app/outputs/flutter-apk/app-release.apk
```

#### AAB (для Google Play)

```bash
flutter build appbundle --release
```

### Запуск в эмуляторе/устройстве

```bash
# Проверить подключенные устройства
flutter devices

# Запустить приложение
flutter run
```

### Структура проекта

```
lib/
├── main.dart                 # Точка входа
├── models/                   # Модели данных
│   ├── connection.dart       # Модель подключения
│   ├── obs_models.dart       # Модели OBS (сцены, источники)
│   └── quick_control_config.dart  # Конфигурация Quick Control
├── services/                 # Бизнес-логика
│   ├── obs_websocket_service.dart  # WebSocket API
│   ├── storage_service.dart        # Хранение настроек
│   ├── backup_service.dart         # Экспорт/импорт настроек
│   ├── update_service.dart         # Автообновления
│   └── foreground_service.dart     # Фоновый сервис
├── providers/                # State management
│   └── obs_provider.dart     # Состояние приложения (ChangeNotifier)
├── screens/                  # Экраны приложения
│   ├── home_screen.dart      # Главный экран
│   ├── connections_screen.dart     # Управление подключениями
│   ├── quick_control_screen.dart   # Quick Control панель
│   └── settings_screen.dart        # Настройки
└── widgets/                  # UI компоненты
    ├── scene_button.dart     # Кнопка сцены
    ├── control_panel.dart    # Панель управления
    ├── audio_source.dart     # Аудио источники
    └── scene_item.dart       # Источники сцены
```

### Архитектура

- **State Management**: Provider (ChangeNotifier pattern)
- **Network**: WebSocket (OBS WebSocket Protocol v5)
- **Storage**: SharedPreferences
- **Foreground Service**: flutter_foreground_task

---

## 📝 Лицензия

GPL-3.0 — см. [LICENSE](LICENSE)

## 👤 Автор

**Epsiquad** — концепция, дизайн, управление проектом

- GitHub: [@SL1ZN1T3L](https://github.com/SL1ZN1T3L)

## 👥 Участники

**Claude** — написание комитов

---

Вдохновлено [OBS Blade](https://github.com/Kounex/obs_blade)