import 'package:flutter_test/flutter_test.dart';
import 'package:obs_controller/models/connection.dart';

void main() {
  group('OBSConnection', () {
    test('создаётся с обязательными параметрами', () {
      final connection = OBSConnection(
        id: 'test-id',
        name: 'Test Server',
        host: '192.168.1.100',
      );

      expect(connection.id, 'test-id');
      expect(connection.name, 'Test Server');
      expect(connection.host, '192.168.1.100');
      expect(connection.port, 4455); // default port
      expect(connection.password, isNull);
      expect(connection.isDefault, false);
      expect(connection.lastConnected, isNull);
    });

    test('создаётся со всеми параметрами', () {
      final now = DateTime.now();
      final connection = OBSConnection(
        id: 'test-id',
        name: 'Test Server',
        host: '192.168.1.100',
        port: 4444,
        password: 'secret',
        isDefault: true,
        lastConnected: now,
      );

      expect(connection.port, 4444);
      expect(connection.password, 'secret');
      expect(connection.isDefault, true);
      expect(connection.lastConnected, now);
    });

    test('address возвращает корректный формат', () {
      final connection = OBSConnection(
        id: 'test-id',
        name: 'Test',
        host: '192.168.1.100',
        port: 4455,
      );

      expect(connection.address, '192.168.1.100:4455');
    });

    group('fromJson', () {
      test('парсит минимальный JSON', () {
        final json = {
          'id': 'json-id',
          'name': 'JSON Server',
          'host': '10.0.0.1',
        };

        final connection = OBSConnection.fromJson(json);

        expect(connection.id, 'json-id');
        expect(connection.name, 'JSON Server');
        expect(connection.host, '10.0.0.1');
        expect(connection.port, 4455);
      });

      test('парсит полный JSON', () {
        final json = {
          'id': 'json-id',
          'name': 'JSON Server',
          'host': '10.0.0.1',
          'port': 4444,
          'password': 'pass123',
          'isDefault': true,
          'lastConnected': '2026-01-21T12:00:00.000',
        };

        final connection = OBSConnection.fromJson(json);

        expect(connection.port, 4444);
        expect(connection.password, 'pass123');
        expect(connection.isDefault, true);
        expect(connection.lastConnected, isNotNull);
      });
    });

    group('toJson', () {
      test('сериализует в JSON', () {
        final connection = OBSConnection(
          id: 'test-id',
          name: 'Test',
          host: '192.168.1.1',
          port: 4455,
          password: 'secret',
          isDefault: true,
        );

        final json = connection.toJson();

        expect(json['id'], 'test-id');
        expect(json['name'], 'Test');
        expect(json['host'], '192.168.1.1');
        expect(json['port'], 4455);
        expect(json['password'], 'secret');
        expect(json['isDefault'], true);
      });

      test('fromJson и toJson обратимы', () {
        final original = OBSConnection(
          id: 'roundtrip-id',
          name: 'Roundtrip Test',
          host: '127.0.0.1',
          port: 4455,
          password: 'test',
          isDefault: false,
        );

        final json = original.toJson();
        final restored = OBSConnection.fromJson(json);

        expect(restored.id, original.id);
        expect(restored.name, original.name);
        expect(restored.host, original.host);
        expect(restored.port, original.port);
        expect(restored.password, original.password);
        expect(restored.isDefault, original.isDefault);
      });
    });

    group('copyWith', () {
      test('копирует с изменением одного поля', () {
        final original = OBSConnection(
          id: 'test-id',
          name: 'Original',
          host: '192.168.1.1',
        );

        final copy = original.copyWith(name: 'Modified');

        expect(copy.id, original.id);
        expect(copy.name, 'Modified');
        expect(copy.host, original.host);
      });

      test('копирует с изменением нескольких полей', () {
        final original = OBSConnection(
          id: 'test-id',
          name: 'Original',
          host: '192.168.1.1',
          port: 4455,
        );

        final copy = original.copyWith(
          host: '10.0.0.1',
          port: 4444,
          isDefault: true,
        );

        expect(copy.id, original.id);
        expect(copy.name, original.name);
        expect(copy.host, '10.0.0.1');
        expect(copy.port, 4444);
        expect(copy.isDefault, true);
      });
    });

    test('toString возвращает читаемый формат', () {
      final connection = OBSConnection(
        id: 'test-id',
        name: 'My OBS',
        host: '192.168.1.100',
        port: 4455,
      );

      expect(connection.toString(), 'OBSConnection(My OBS @ 192.168.1.100:4455)');
    });
  });
}
