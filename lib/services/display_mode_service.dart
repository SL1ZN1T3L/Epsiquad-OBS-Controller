import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'power_service.dart';

/// Сервис адаптивного управления частотой экрана.
/// При активности пользователя — максимальная частота, через 5с
/// бездействия — стандартная (60Hz).
/// При активном режиме энергосбережения high refresh rate не включается.
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

  Future<void> init() async {
    if (_initialized) return;

    try {
      final modes = await FlutterDisplayMode.supported;
      if (modes.isEmpty) return;

      modes.sort((a, b) => b.refreshRate.compareTo(a.refreshRate));

      _highRefreshMode = modes.first;
      _standardMode = modes.firstWhere(
        (m) => m.refreshRate <= 60,
        orElse: () => modes.last,
      );

      debugPrint('DisplayMode: high=${_highRefreshMode?.refreshRate}Hz, '
          'standard=${_standardMode?.refreshRate}Hz');

      _initialized = true;

      // При смене power-профиля — если включился saving и сейчас high,
      // принудительно опускаем до standard.
      PowerService.instance.addListener(_onPowerProfileChanged);

      await _setStandardRefreshRate();
    } catch (e) {
      debugPrint('DisplayMode init error: $e');
    }
  }

  void _onPowerProfileChanged() {
    if (!_initialized) return;
    if (PowerService.instance.isPowerSaving && _isHighRefreshRate) {
      _setStandardRefreshRate();
    }
  }

  void onUserActivity() {
    if (!_initialized) return;

    _inactivityTimer?.cancel();

    // В режиме энергосбережения high refresh rate не активируем вообще.
    if (PowerService.instance.isPowerSaving) {
      if (_isHighRefreshRate) {
        _setStandardRefreshRate();
      }
      return;
    }

    if (!_isHighRefreshRate) {
      _setHighRefreshRate();
    }

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
    PowerService.instance.removeListener(_onPowerProfileChanged);
  }
}
