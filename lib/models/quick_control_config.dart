import 'dart:convert';
import 'package:flutter/material.dart';

enum QuickButtonType {
  record,
  stream,
  scene,
  audioMute,
  sceneItem,
  separator,
  // НОВЫЕ ТИПЫ
  virtualCam,
  replayBuffer,
  screenshot,
  studioMode,
  hotkey,
}

class QuickButtonConfig {
  final String id;
  final QuickButtonType type;
  final String? targetName;
  final int? targetId;
  final String? sceneName;
  final String? groupName;

  // НОВЫЕ ПОЛЯ ДЛЯ КАСТОМИЗАЦИИ
  final String? customLabel;
  final String? customIcon;
  final String? customColor;

  final int order;

  QuickButtonConfig({
    required this.id,
    required this.type,
    this.targetName,
    this.targetId,
    this.sceneName,
    this.groupName,
    this.customLabel,
    this.customIcon,
    this.customColor,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.index,
        'targetName': targetName,
        'targetId': targetId,
        'sceneName': sceneName,
        'groupName': groupName,
        'customLabel': customLabel,
        'customIcon': customIcon,
        'customColor': customColor,
        'order': order,
      };

  factory QuickButtonConfig.fromJson(Map<String, dynamic> json) {
    return QuickButtonConfig(
      id: json['id'] as String,
      type: QuickButtonType.values[json['type'] as int],
      targetName: json['targetName'] as String?,
      targetId: json['targetId'] as int?,
      sceneName: json['sceneName'] as String?,
      groupName: json['groupName'] as String?,
      customLabel: json['customLabel'] as String?,
      customIcon: json['customIcon'] as String?,
      customColor: json['customColor'] as String?,
      order: json['order'] as int,
    );
  }

  QuickButtonConfig copyWith({
    String? id,
    QuickButtonType? type,
    String? targetName,
    int? targetId,
    String? sceneName,
    String? groupName,
    String? customLabel,
    String? customIcon,
    String? customColor,
    int? order,
  }) {
    return QuickButtonConfig(
      id: id ?? this.id,
      type: type ?? this.type,
      targetName: targetName ?? this.targetName,
      targetId: targetId ?? this.targetId,
      sceneName: sceneName ?? this.sceneName,
      groupName: groupName ?? this.groupName,
      customLabel: customLabel ?? this.customLabel,
      customIcon: customIcon ?? this.customIcon,
      customColor: customColor ?? this.customColor,
      order: order ?? this.order,
    );
  }

  String get displayName {
    if (customLabel != null && customLabel!.isNotEmpty) {
      return customLabel!;
    }

    switch (type) {
      case QuickButtonType.record:
        return 'Запись';
      case QuickButtonType.stream:
        return 'Стрим';
      case QuickButtonType.scene:
        return targetName ?? 'Сцена';
      case QuickButtonType.audioMute:
        return targetName ?? 'Аудио';
      case QuickButtonType.sceneItem:
        return targetName ?? 'Источник';
      case QuickButtonType.separator:
        return groupName ?? '─────';
      case QuickButtonType.virtualCam:
        return 'Виртуальная камера';
      case QuickButtonType.replayBuffer:
        return 'Replay Buffer';
      case QuickButtonType.screenshot:
        return 'Скриншот';
      case QuickButtonType.studioMode:
        return 'Studio Mode';
      case QuickButtonType.hotkey:
        return targetName ?? 'Hotkey';
    }
  }

  IconData get icon {
    if (customIcon != null) {
      return _parseIconData(customIcon!);
    }

    switch (type) {
      case QuickButtonType.record:
        return Icons.fiber_manual_record;
      case QuickButtonType.stream:
        return Icons.stream;
      case QuickButtonType.scene:
        return Icons.tv;
      case QuickButtonType.audioMute:
        return Icons.volume_up;
      case QuickButtonType.sceneItem:
        return Icons.layers;
      case QuickButtonType.separator:
        return Icons.horizontal_rule;
      case QuickButtonType.virtualCam:
        return Icons.videocam;
      case QuickButtonType.replayBuffer:
        return Icons.replay;
      case QuickButtonType.screenshot:
        return Icons.camera_alt;
      case QuickButtonType.studioMode:
        return Icons.edit;
      case QuickButtonType.hotkey:
        return Icons.keyboard;
    }
  }

  Color? get color {
    if (customColor != null) {
      return _parseColor(customColor!);
    }
    return null;
  }

  static IconData _parseIconData(String iconName) {
    final iconMap = {
      'videocam': Icons.videocam,
      'camera': Icons.camera_alt,
      'replay': Icons.replay,
      'edit': Icons.edit,
      'keyboard': Icons.keyboard,
      'tv': Icons.tv,
      'stream': Icons.stream,
      'record': Icons.fiber_manual_record,
      'volume': Icons.volume_up,
      'layers': Icons.layers,
      'play': Icons.play_arrow,
      'pause': Icons.pause,
      'stop': Icons.stop,
      'mic': Icons.mic,
      'mic_off': Icons.mic_off,
      'visibility': Icons.visibility,
      'visibility_off': Icons.visibility_off,
      'settings': Icons.settings,
      'star': Icons.star,
      'favorite': Icons.favorite,
      'check': Icons.check,
      'close': Icons.close,
      'add': Icons.add,
      'remove': Icons.remove,
      'radio_button_checked': Icons.radio_button_checked,
      'radio_button_unchecked': Icons.radio_button_unchecked,
      'light_mode': Icons.light_mode,
      'dark_mode': Icons.dark_mode,
      'photo_camera': Icons.photo_camera,
      'movie': Icons.movie,
    };

    return iconMap[iconName] ?? Icons.help_outline;
  }

  static Color _parseColor(String hexColor) {
    try {
      final hex = hexColor.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (e) {
      return Colors.blue;
    }
  }
}

class QuickControlProfile {
  final String id;
  final String name;
  final List<QuickButtonConfig> buttons;
  final int columns;
  final DateTime createdAt;
  final DateTime modifiedAt;

  QuickControlProfile({
    required this.id,
    required this.name,
    required this.buttons,
    this.columns = 3,
    DateTime? createdAt,
    DateTime? modifiedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        modifiedAt = modifiedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'buttons': buttons.map((b) => b.toJson()).toList(),
        'columns': columns,
        'createdAt': createdAt.toIso8601String(),
        'modifiedAt': modifiedAt.toIso8601String(),
      };

  factory QuickControlProfile.fromJson(Map<String, dynamic> json) {
    return QuickControlProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      buttons: (json['buttons'] as List)
          .map((b) => QuickButtonConfig.fromJson(b as Map<String, dynamic>))
          .toList(),
      columns: json['columns'] as int? ?? 3,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      modifiedAt: json['modifiedAt'] != null
          ? DateTime.parse(json['modifiedAt'] as String)
          : null,
    );
  }

  QuickControlProfile copyWith({
    String? id,
    String? name,
    List<QuickButtonConfig>? buttons,
    int? columns,
    DateTime? createdAt,
    DateTime? modifiedAt,
  }) {
    return QuickControlProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      buttons: buttons ?? this.buttons,
      columns: columns ?? this.columns,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? DateTime.now(),
    );
  }
}

class QuickControlConfig {
  final List<QuickButtonConfig> buttons;
  final int columns;

  QuickControlConfig({
    required this.buttons,
    this.columns = 3,
  });

  Map<String, dynamic> toJson() => {
        'buttons': buttons.map((b) => b.toJson()).toList(),
        'columns': columns,
      };

  factory QuickControlConfig.fromJson(Map<String, dynamic> json) {
    return QuickControlConfig(
      buttons: (json['buttons'] as List)
          .map((b) => QuickButtonConfig.fromJson(b as Map<String, dynamic>))
          .toList(),
      columns: json['columns'] as int? ?? 3,
    );
  }

  static QuickControlConfig empty() => QuickControlConfig(buttons: []);

  String toJsonString() => jsonEncode(toJson());

  static QuickControlConfig fromJsonString(String json) {
    return QuickControlConfig.fromJson(
        jsonDecode(json) as Map<String, dynamic>);
  }
}
