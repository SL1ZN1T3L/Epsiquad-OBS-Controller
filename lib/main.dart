import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/screens.dart';
import 'providers/obs_provider.dart';
import 'services/services.dart';
import 'widgets/shader_warmup.dart';

final themeNotifier = ValueNotifier<ThemeData>(
  ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.blue,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  ),
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Загружаем настройку логирования ДО первого вызова log
  final prefs = await SharedPreferences.getInstance();
  log.enabled = prefs.getBool('loggingEnabled') ?? true;

  log.i('App', 'Starting OBS Controller...');

  await DisplayModeService.instance.init();

  final storage = await StorageService.init();
  log.i('App', 'Storage initialized');

  final savedTheme = await AppTheme.loadSaved();
  if (savedTheme != null) {
    themeNotifier.value = savedTheme.toThemeData();
  }

  await StatsHistoryService.instance.load();

  final fullscreenMode =
      await storage.getSetting<bool>('fullscreenMode', false);

  if (fullscreenMode) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
    ),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => OBSProvider(storage),
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => DisplayModeService.instance.onUserActivity(),
      onPointerMove: (_) => DisplayModeService.instance.onUserActivity(),
      child: ValueListenableBuilder<ThemeData>(
        valueListenable: themeNotifier,
        builder: (context, theme, _) => MaterialApp(
          title: 'OBS Controller',
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: const ShaderWarmup(
            child: HomeScreen(),
          ),
          builder: (context, child) {
            if (kDebugMode) {
              return Banner(
                message: 'BETA',
                location: BannerLocation.topEnd,
                color: Colors.deepOrange,
                child: child ?? const SizedBox.shrink(),
              );
            }
            return child ?? const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
