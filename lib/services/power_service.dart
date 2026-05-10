import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'log_service.dart';
import 'storage_service.dart';

const _tag = 'Power';

/// Режим управления энергосбережением.
enum PowerMode {
  /// Автоматически: реагирует на системный режим энергосбережения и
  /// низкий заряд (≤20% без зарядки).
  auto,

  /// Всегда включено — режим экономии активен принудительно.
  always,

  /// Всегда выключено — обычный режим, без адаптации.
  never,
}

/// Управляет адаптацией приложения под состояние питания устройства.
/// Слушают другие компоненты через ChangeNotifier — при изменении
/// `isPowerSaving` пересчитывают свои параметры (refresh rate, частоту
/// поллинга и т. п.).
class PowerService extends ChangeNotifier {
  static PowerService? _instance;
  static PowerService get instance => _instance ??= PowerService._();
  PowerService._();

  final Battery _battery = Battery();

  StreamSubscription<BatteryState>? _stateSub;
  Timer? _refreshTimer;
  StorageService? _storage;
  bool _initialized = false;

  int _level = 100;
  BatteryState _state = BatteryState.unknown;
  bool _systemSaverEnabled = false;
  PowerMode _mode = PowerMode.auto;

  int get level => _level;
  BatteryState get state => _state;
  bool get systemSaverEnabled => _systemSaverEnabled;
  PowerMode get mode => _mode;

  bool get isCharging =>
      _state == BatteryState.charging || _state == BatteryState.full;

  /// Низкий заряд: ≤20% и не на зарядке.
  bool get isLowBattery => _level <= 20 && !isCharging;

  /// Активен ли режим экономии прямо сейчас.
  bool get isPowerSaving {
    switch (_mode) {
      case PowerMode.always:
        return true;
      case PowerMode.never:
        return false;
      case PowerMode.auto:
        return _systemSaverEnabled || isLowBattery;
    }
  }

  Future<void> init(StorageService storage) async {
    if (_initialized) return;
    _storage = storage;

    final modeStr = await storage.getSetting<String>('powerMode', 'auto');
    _mode = PowerMode.values.firstWhere(
      (m) => m.name == modeStr,
      orElse: () => PowerMode.auto,
    );

    await _refresh();

    // battery_plus выдаёт стрим только для состояния зарядки. Уровень и
    // флаг системного энергосбережения опрашиваем по таймеру.
    _stateSub = _battery.onBatteryStateChanged.listen((state) {
      _state = state;
      _refresh();
    });

    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refresh(),
    );

    _initialized = true;
    log.i(_tag,
        'Initialized: mode=$_mode, level=$_level%, saving=$isPowerSaving');
  }

  Future<void> setMode(PowerMode newMode) async {
    if (_mode == newMode) return;
    _mode = newMode;
    await _storage?.setSetting('powerMode', newMode.name);
    log.i(_tag, 'Mode changed: $newMode, saving=$isPowerSaving');
    notifyListeners();
  }

  /// Принудительный перезапрос текущего состояния (например, по фокусу).
  Future<void> refresh() => _refresh();

  Future<void> _refresh() async {
    final prevLevel = _level;
    final prevState = _state;
    final prevSaver = _systemSaverEnabled;
    final wasSaving = isPowerSaving;

    try {
      _level = await _battery.batteryLevel;
    } catch (e) {
      log.w(_tag, 'batteryLevel failed', e.toString());
    }
    try {
      _state = await _battery.batteryState;
    } catch (e) {
      log.w(_tag, 'batteryState failed', e.toString());
    }
    try {
      _systemSaverEnabled = await _battery.isInBatterySaveMode;
    } catch (e) {
      // На некоторых платформах метод может быть не поддержан — деградируем.
      _systemSaverEnabled = false;
    }

    if (wasSaving != isPowerSaving) {
      log.i(_tag,
          'Power saving switched: ${isPowerSaving ? "ON" : "OFF"} (level=$_level%, charging=$isCharging, sysSaver=$_systemSaverEnabled)');
    }

    // Уведомляем подписчиков только при реальном изменении наблюдаемого
    // состояния — иначе AnimatedBuilder/Consumer'ы пересобирают всё дерево
    // на каждый минутный пинг батареи, что вызывает заметные лаги UI.
    final changed = prevLevel != _level ||
        prevState != _state ||
        prevSaver != _systemSaverEnabled;
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }
}
