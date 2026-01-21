import 'package:flutter_test/flutter_test.dart';
import 'package:obs_controller/models/quick_control_config.dart';

void main() {
  group('QuickButtonType', () {
    test('содержит все необходимые типы', () {
      expect(QuickButtonType.values, contains(QuickButtonType.record));
      expect(QuickButtonType.values, contains(QuickButtonType.stream));
      expect(QuickButtonType.values, contains(QuickButtonType.scene));
      expect(QuickButtonType.values, contains(QuickButtonType.audioMute));
      expect(QuickButtonType.values, contains(QuickButtonType.sceneItem));
      expect(QuickButtonType.values, contains(QuickButtonType.virtualCam));
      expect(QuickButtonType.values, contains(QuickButtonType.replayBuffer));
      expect(QuickButtonType.values, contains(QuickButtonType.screenshot));
      expect(QuickButtonType.values, contains(QuickButtonType.studioMode));
      expect(QuickButtonType.values, contains(QuickButtonType.hotkey));
    });
  });

  group('QuickButtonConfig', () {
    test('создаётся с обязательными параметрами', () {
      final config = QuickButtonConfig(
        id: 'btn-1',
        type: QuickButtonType.record,
        order: 0,
      );

      expect(config.id, 'btn-1');
      expect(config.type, QuickButtonType.record);
      expect(config.order, 0);
      expect(config.targetName, isNull);
      expect(config.customLabel, isNull);
    });

    test('создаётся с кастомизацией', () {
      final config = QuickButtonConfig(
        id: 'btn-2',
        type: QuickButtonType.scene,
        targetName: 'Game Scene',
        customLabel: 'Игра',
        customIcon: 'games',
        customColor: '#FF5722',
        order: 1,
      );

      expect(config.targetName, 'Game Scene');
      expect(config.customLabel, 'Игра');
      expect(config.customIcon, 'games');
      expect(config.customColor, '#FF5722');
    });

    group('toJson', () {
      test('сериализует базовую конфигурацию', () {
        final config = QuickButtonConfig(
          id: 'test-id',
          type: QuickButtonType.stream,
          order: 5,
        );

        final json = config.toJson();

        expect(json['id'], 'test-id');
        expect(json['type'], QuickButtonType.stream.index);
        expect(json['order'], 5);
      });

      test('сериализует полную конфигурацию', () {
        final config = QuickButtonConfig(
          id: 'full-id',
          type: QuickButtonType.audioMute,
          targetName: 'Mic/Aux',
          sceneName: 'Main',
          groupName: 'Audio',
          customLabel: 'Микрофон',
          customIcon: 'mic_off',
          customColor: '#E91E63',
          order: 2,
        );

        final json = config.toJson();

        expect(json['targetName'], 'Mic/Aux');
        expect(json['sceneName'], 'Main');
        expect(json['groupName'], 'Audio');
        expect(json['customLabel'], 'Микрофон');
        expect(json['customIcon'], 'mic_off');
        expect(json['customColor'], '#E91E63');
      });
    });

    group('fromJson', () {
      test('десериализует базовую конфигурацию', () {
        final json = {
          'id': 'json-id',
          'type': QuickButtonType.record.index,
          'order': 0,
        };

        final config = QuickButtonConfig.fromJson(json);

        expect(config.id, 'json-id');
        expect(config.type, QuickButtonType.record);
        expect(config.order, 0);
      });

      test('десериализует полную конфигурацию', () {
        final json = {
          'id': 'full-json',
          'type': QuickButtonType.sceneItem.index,
          'targetName': 'Webcam',
          'targetId': 42,
          'sceneName': 'Main',
          'groupName': 'Sources',
          'customLabel': 'Камера',
          'customIcon': 'videocam',
          'customColor': '#2196F3',
          'order': 3,
        };

        final config = QuickButtonConfig.fromJson(json);

        expect(config.type, QuickButtonType.sceneItem);
        expect(config.targetName, 'Webcam');
        expect(config.targetId, 42);
        expect(config.sceneName, 'Main');
        expect(config.groupName, 'Sources');
        expect(config.customLabel, 'Камера');
        expect(config.customIcon, 'videocam');
        expect(config.customColor, '#2196F3');
      });

      test('fromJson и toJson обратимы', () {
        final original = QuickButtonConfig(
          id: 'roundtrip',
          type: QuickButtonType.virtualCam,
          customLabel: 'Виртуальная камера',
          order: 10,
        );

        final json = original.toJson();
        final restored = QuickButtonConfig.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.type, original.type);
        expect(restored.customLabel, original.customLabel);
        expect(restored.order, original.order);
      });
    });

    group('copyWith', () {
      test('копирует с изменением одного поля', () {
        final original = QuickButtonConfig(
          id: 'original',
          type: QuickButtonType.screenshot,
          order: 0,
        );

        final copy = original.copyWith(order: 5);

        expect(copy.id, original.id);
        expect(copy.type, original.type);
        expect(copy.order, 5);
      });

      test('копирует с изменением нескольких полей', () {
        final original = QuickButtonConfig(
          id: 'original',
          type: QuickButtonType.scene,
          targetName: 'Scene 1',
          order: 0,
        );

        final copy = original.copyWith(
          targetName: 'Scene 2',
          customLabel: 'Новая сцена',
          customColor: '#4CAF50',
        );

        expect(copy.id, original.id);
        expect(copy.type, original.type);
        expect(copy.targetName, 'Scene 2');
        expect(copy.customLabel, 'Новая сцена');
        expect(copy.customColor, '#4CAF50');
      });
    });
  });
}
