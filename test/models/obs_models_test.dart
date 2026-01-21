import 'package:flutter_test/flutter_test.dart';
import 'package:obs_controller/models/obs_models.dart';

void main() {
  group('OBSScene', () {
    test('создаётся с обязательными параметрами', () {
      final scene = OBSScene(name: 'Scene 1', index: 0);

      expect(scene.name, 'Scene 1');
      expect(scene.index, 0);
      expect(scene.isCurrentProgram, false);
      expect(scene.isCurrentPreview, false);
    });

    test('fromJson парсит корректно', () {
      final json = {'sceneName': 'Main Scene', 'sceneIndex': 1};

      final scene = OBSScene.fromJson(json);

      expect(scene.name, 'Main Scene');
      expect(scene.index, 1);
    });

    test('fromJson определяет текущую program сцену', () {
      final json = {'sceneName': 'Live', 'sceneIndex': 0};

      final scene = OBSScene.fromJson(json, currentProgram: 'Live');

      expect(scene.isCurrentProgram, true);
      expect(scene.isCurrentPreview, false);
    });

    test('fromJson определяет текущую preview сцену', () {
      final json = {'sceneName': 'Preview Scene', 'sceneIndex': 1};

      final scene = OBSScene.fromJson(json, currentPreview: 'Preview Scene');

      expect(scene.isCurrentProgram, false);
      expect(scene.isCurrentPreview, true);
    });

    test('copyWith создаёт копию с изменениями', () {
      final original = OBSScene(name: 'Scene', index: 0);
      final copy = original.copyWith(isCurrentProgram: true);

      expect(copy.name, original.name);
      expect(copy.isCurrentProgram, true);
    });
  });

  group('OBSSceneItem', () {
    test('создаётся с обязательными параметрами', () {
      final item = OBSSceneItem(
        sceneItemId: 1,
        sourceName: 'Webcam',
        sourceType: 'dshow_input',
        isVisible: true,
      );

      expect(item.sceneItemId, 1);
      expect(item.sourceName, 'Webcam');
      expect(item.sourceType, 'dshow_input');
      expect(item.isVisible, true);
      expect(item.isLocked, false);
      expect(item.index, 0);
    });

    test('fromJson парсит корректно', () {
      final json = {
        'sceneItemId': 42,
        'sourceName': 'Game Capture',
        'sourceType': 'game_capture',
        'sceneItemEnabled': true,
        'sceneItemLocked': true,
        'sceneItemIndex': 3,
      };

      final item = OBSSceneItem.fromJson(json);

      expect(item.sceneItemId, 42);
      expect(item.sourceName, 'Game Capture');
      expect(item.sourceType, 'game_capture');
      expect(item.isVisible, true);
      expect(item.isLocked, true);
      expect(item.index, 3);
    });

    test('fromJson обрабатывает отсутствующие поля', () {
      final json = {
        'sceneItemId': 1,
        'sourceName': 'Source',
      };

      final item = OBSSceneItem.fromJson(json);

      expect(item.sourceType, 'unknown');
      expect(item.isVisible, true);
      expect(item.isLocked, false);
      expect(item.index, 0);
    });

    test('copyWith создаёт копию с изменениями', () {
      final original = OBSSceneItem(
        sceneItemId: 1,
        sourceName: 'Source',
        sourceType: 'type',
        isVisible: true,
      );

      final copy = original.copyWith(isVisible: false, isLocked: true);

      expect(copy.sceneItemId, original.sceneItemId);
      expect(copy.isVisible, false);
      expect(copy.isLocked, true);
    });
  });

  group('OBSAudioSource', () {
    test('создаётся с обязательными параметрами', () {
      final audio = OBSAudioSource(name: 'Mic', kind: 'wasapi_input_capture');

      expect(audio.name, 'Mic');
      expect(audio.kind, 'wasapi_input_capture');
      expect(audio.volume, 1.0);
      expect(audio.isMuted, false);
    });

    test('fromJson парсит корректно', () {
      final json = {
        'inputName': 'Desktop Audio',
        'inputKind': 'wasapi_output_capture',
        'inputVolumeMul': 0.75,
        'inputMuted': true,
      };

      final audio = OBSAudioSource.fromJson(json);

      expect(audio.name, 'Desktop Audio');
      expect(audio.kind, 'wasapi_output_capture');
      expect(audio.volume, 0.75);
      expect(audio.isMuted, true);
    });

    test('fromJson обрабатывает отсутствующие поля', () {
      final json = {'inputName': 'Source'};

      final audio = OBSAudioSource.fromJson(json);

      expect(audio.kind, 'unknown');
      expect(audio.volume, 1.0);
      expect(audio.isMuted, false);
    });

    test('copyWith создаёт копию с изменениями', () {
      final original = OBSAudioSource(name: 'Mic', kind: 'input');
      final copy = original.copyWith(volume: 0.5, isMuted: true);

      expect(copy.name, original.name);
      expect(copy.volume, 0.5);
      expect(copy.isMuted, true);
    });
  });

  group('OBSOutputStatus', () {
    test('создаётся с дефолтными значениями', () {
      final status = OBSOutputStatus();

      expect(status.isActive, false);
      expect(status.isPaused, false);
      expect(status.duration, isNull);
    });

    test('durationString форматируется корректно', () {
      final status = OBSOutputStatus(
        isActive: true,
        duration: const Duration(hours: 1, minutes: 30, seconds: 45),
      );

      expect(status.durationString, '01:30:45');
    });

    test('durationString возвращает 00:00:00 при null', () {
      final status = OBSOutputStatus();

      expect(status.durationString, '00:00:00');
    });
  });
}
