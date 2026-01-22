import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'screens/screens.dart';
import 'providers/obs_provider.dart';
import 'services/services.dart';
import 'widgets/shader_warmup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Включаем максимальную частоту обновления экрана (90Hz, 120Hz и т.д.)
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } catch (e) {
    debugPrint('Display mode error: $e');
  }

  final storage = await StorageService.init();

  // Загружаем настройку полноэкранного режима
  final fullscreenMode =
      await storage.getSetting<bool>('fullscreenMode', false);

  // Применяем режим системного UI
  if (fullscreenMode) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  } else {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
    );
  }

  // Устанавливаем цвет статус бара
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
    return MaterialApp(
      title: 'OBS Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
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
    );
  }
}
