import 'dart:async';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'obs_controller_channel',
      channelName: 'OBS Controller Service',
      channelDescription: 'Maintaining connection to OBS',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

Future<bool> startForegroundService() async {
  if (await FlutterForegroundTask.isRunningService) {
    return true;
  }
  final result = await FlutterForegroundTask.startService(
    notificationTitle: 'OBS Controller',
    notificationText: 'Connected to OBS',
    callback: startCallback,
  );
  return result is ServiceRequestSuccess;
}

Future<bool> stopForegroundService() async {
  final result = await FlutterForegroundTask.stopService();
  return result is ServiceRequestSuccess;
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(OBSTaskHandler());
}

class OBSTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {}

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationDismissed() {}
}

class ForegroundServiceManager {
  static final ForegroundServiceManager _instance =
      ForegroundServiceManager._();
  factory ForegroundServiceManager() => _instance;
  ForegroundServiceManager._();

  Future<void> init() async {
    FlutterForegroundTask.initCommunicationPort();
    initForegroundTask();
  }

  Future<bool> start() async {
    return await startForegroundService();
  }

  Future<bool> stop() async {
    return stopForegroundService();
  }

  void sendStatus(String status) {
    FlutterForegroundTask.updateService(
      notificationTitle: 'OBS Controller',
      notificationText: status,
    );
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;
}
