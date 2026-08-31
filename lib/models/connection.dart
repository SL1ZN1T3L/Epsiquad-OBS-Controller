/// Сентинел для copyWith: отличает «параметр не передан» от «передан null».
/// Нужен, чтобы можно было очистить пароль через copyWith(password: null).
const Object _unset = Object();

class OBSConnection {
  final String id;
  final String name;
  final String host;
  final int port;
  final String? password;
  final bool isDefault;
  final DateTime? lastConnected;
  final String iconName;
  final bool useTls;

  static const defaultIcon = 'computer';

  OBSConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 4455,
    this.password,
    this.isDefault = false,
    this.lastConnected,
    this.iconName = defaultIcon,
    this.useTls = false,
  });

  factory OBSConnection.fromJson(Map<String, dynamic> json) {
    return OBSConnection(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 4455,
      password: json['password'] as String?,
      isDefault: json['isDefault'] as bool? ?? false,
      lastConnected: json['lastConnected'] != null
          ? DateTime.parse(json['lastConnected'] as String)
          : null,
      iconName: json['iconName'] as String? ?? defaultIcon,
      useTls: json['useTls'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'password': password,
      'isDefault': isDefault,
      'lastConnected': lastConnected?.toIso8601String(),
      'iconName': iconName,
      'useTls': useTls,
    };
  }

  String get address => '$host:$port';

  OBSConnection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    Object? password = _unset,
    bool? isDefault,
    Object? lastConnected = _unset,
    String? iconName,
    bool? useTls,
  }) {
    return OBSConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      password:
          identical(password, _unset) ? this.password : password as String?,
      isDefault: isDefault ?? this.isDefault,
      lastConnected: identical(lastConnected, _unset)
          ? this.lastConnected
          : lastConnected as DateTime?,
      iconName: iconName ?? this.iconName,
      useTls: useTls ?? this.useTls,
    );
  }

  @override
  String toString() => 'OBSConnection($name @ $address)';
}
