import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// Сервис адаптивного управления частотой экрана
/// При активности пользователя - максимальная частота
/// После 5 секунд бездействия - стандартная частота (60Hz)
class DisplayModeService {
  static DisplayModeService? _instance;
  static DisplayModeService get instance => _instance ??= DisplayModeService._();

  DisplayModeService._();

  Timer? _inactivityTimer;
  bool _isHighRefreshRate = false;
  DisplayMode? _highRefreshMode;
  DisplayMode? _standardMode;
  bool _initialized = false;

  static const _inactivityDuration = Duration(seconds: 5);

  /// Инициализация сервиса - определяет доступные режимы
  Future<void> init() async {
    if (_initialized) return;

    try {
      final modes = await FlutterDisplayMode.supported;
      if (modes.isEmpty) return;

      // Сортируем по частоте (от большей к меньшей)
      modes.sort((a, b) => b.refreshRate.compareTo(a.refreshRate));

      // Максимальная частота
      _highRefreshMode = modes.first;

      // Стандартная частота (около 60Hz или минимальная доступная)
      _standardMode = modes.firstWhere(
        (m) => m.refreshRate <= 60,
        orElse: () => modes.last,
      );

      debugPrint('DisplayMode: high=${_highRefreshMode?.refreshRate}Hz, '
          'standard=${_standardMode?.refreshRate}Hz');

      _initialized = true;

      // Начинаем со стандартной частоты
      await _setStandardRefreshRate();
    } catch (e) {
      debugPrint('DisplayMode init error: $e');
    }
  }

  /// Вызывать при любом пользовательском вводе
  void onUserActivity() {
    if (!_initialized) return;

    // Сбрасываем таймер
    _inactivityTimer?.cancel();

    // Включаем высокую частоту если ещё не включена
    if (!_isHighRefreshRate) {
      _setHighRefreshRate();
    }

    // Запускаем таймер бездействия
    _inactivityTimer = Timer(_inactivityDuration, () {
      _setStandardRefreshRate();
    });
  }

  Future<void> _setHighRefreshRate() async {
    if (_highRefreshMode == null || _isHighRefreshRate) return;

    try {
      await FlutterDisplayMode.setPreferredMode(_highRefreshMode!);
      _isHighRefreshRate = true;
      debugPrint('DisplayMode: switched to ${_highRefreshMode!.refreshRate}Hz');
    } catch (e) {
      debugPrint('DisplayMode high error: $e');
    }
  }

  Future<void> _setStandardRefreshRate() async {
    if (_standardMode == null || !_isHighRefreshRate) return;

    try {
      await FlutterDisplayMode.setPreferredMode(_standardMode!);
      _isHighRefreshRate = false;
      debugPrint('DisplayMode: switched to ${_standardMode!.refreshRate}Hz');
    } catch (e) {
      debugPrint('DisplayMode standard error: $e');
    }
  }

  void dispose() {
    _inactivityTimer?.cancel();
  }
}
