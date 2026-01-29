class OBSConnection {
  final String id;
  String name;
  String host;
  int port;
  String? password;
  bool isDefault;
  DateTime? lastConnected;
  String iconName;

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
    };
  }

  String get address => '$host:$port';

  OBSConnection copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? password,
    bool? isDefault,
    DateTime? lastConnected,
    String? iconName,
  }) {
    return OBSConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      password: password ?? this.password,
      isDefault: isDefault ?? this.isDefault,
      lastConnected: lastConnected ?? this.lastConnected,
      iconName: iconName ?? this.iconName,
    );
  }

  @override
  String toString() => 'OBSConnection($name @ $address)';
}
