import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../providers/obs_provider.dart';

class ConnectionsScreen extends StatefulWidget {
  const ConnectionsScreen({super.key});

  @override
  State<ConnectionsScreen> createState() => _ConnectionsScreenState();
}

class _ConnectionsScreenState extends State<ConnectionsScreen> {
  bool _autoConnect = true;

  @override
  void initState() {
    super.initState();
    _loadAutoConnect();
  }

  Future<void> _loadAutoConnect() async {
    final provider = context.read<OBSProvider>();
    final value = await provider.getAutoConnect();
    if (mounted) {
      setState(() => _autoConnect = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подключения'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () => _scanQRCode(context),
            tooltip: 'Сканировать QR',
          ),
        ],
      ),
      body: Consumer<OBSProvider>(
        builder: (context, provider, _) {
          final connections = provider.connections;

          if (connections.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_off, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Нет сохранённых подключений',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _addConnection(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить подключение'),
                  ),
                  const SizedBox(height: 32),
                  // Переключатель автоподключения
                  _buildAutoConnectSwitch(provider),
                ],
              ),
            );
          }

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: connections.length,
                  itemBuilder: (context, index) {
                    final connection = connections[index];
                    final isCurrentConnection =
                        provider.currentConnection?.id == connection.id;
                    final isConnected =
                        isCurrentConnection && provider.isConnected;

                    return Card(
                      color: isConnected ? Colors.green.shade900 : null,
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isConnected
                              ? Colors.green
                              : connection.isDefault
                                  ? Theme.of(context).primaryColor
                                  : Colors.grey,
                          child: Icon(
                            isConnected ? Icons.check : Icons.computer,
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          connection.name,
                          style: TextStyle(
                            fontWeight: connection.isDefault
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(connection.address),
                            if (connection.lastConnected != null)
                              Text(
                                'Последнее: ${_formatDate(connection.lastConnected!)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (connection.isDefault)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Chip(
                                  label: Text('По умолч.'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            PopupMenuButton<String>(
                              onSelected: (value) => _handleMenuAction(
                                context,
                                value,
                                connection,
                              ),
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.edit),
                                    title: Text('Редактировать'),
                                    dense: true,
                                  ),
                                ),
                                if (!connection.isDefault)
                                  const PopupMenuItem(
                                    value: 'default',
                                    child: ListTile(
                                      leading: Icon(Icons.star),
                                      title: Text('По умолчанию'),
                                      dense: true,
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading:
                                        Icon(Icons.delete, color: Colors.red),
                                    title: Text('Удалить'),
                                    dense: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        onTap: () async {
                          if (isConnected) {
                            await provider.disconnect();
                          } else {
                            await provider.connect(connection);
                            if (context.mounted && provider.isConnected) {
                              Navigator.of(context).pop();
                            }
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
              // Переключатель автоподключения внизу списка
              _buildAutoConnectSwitch(provider),
              const SizedBox(height: 8),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addConnection(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildAutoConnectSwitch(OBSProvider provider) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: SwitchListTile(
        title: const Text('Автоподключение'),
        subtitle: const Text('Подключаться при запуске приложения'),
        secondary: const Icon(Icons.power_settings_new),
        value: _autoConnect,
        onChanged: (value) async {
          setState(() => _autoConnect = value);
          await provider.setAutoConnect(value);
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Только что';
    if (diff.inHours < 1) return '${diff.inMinutes} мин назад';
    if (diff.inDays < 1) return '${diff.inHours} ч назад';
    if (diff.inDays < 7) return '${diff.inDays} дн назад';

    return '${date.day}.${date.month}.${date.year}';
  }

  void _handleMenuAction(
    BuildContext context,
    String action,
    OBSConnection connection,
  ) async {
    final provider = context.read<OBSProvider>();

    switch (action) {
      case 'edit':
        _editConnection(context, connection);
        break;
      case 'default':
        await provider.setDefaultConnection(connection.id);
        break;
      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Удалить подключение?'),
            content:
                Text('Вы уверены, что хотите удалить "${connection.name}"?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child:
                    const Text('Удалить', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (confirmed == true) {
          await provider.deleteConnection(connection.id);
        }
        break;
    }
  }

  void _addConnection(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const ConnectionDialog(connection: null),
    );
  }

  void _editConnection(BuildContext context, OBSConnection connection) {
    showDialog(
      context: context,
      builder: (context) => ConnectionDialog(connection: connection),
    );
  }

  void _scanQRCode(BuildContext context) async {
    final result = await Navigator.of(context).push<OBSConnection>(
      MaterialPageRoute(
        builder: (_) => const QRScannerScreen(),
      ),
    );

    if (result != null && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => ConnectionDialog(connection: result),
      );
    }
  }
}

class ConnectionDialog extends StatefulWidget {
  final OBSConnection? connection;

  const ConnectionDialog({super.key, this.connection});

  @override
  State<ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<ConnectionDialog> {
  late TextEditingController _nameController;
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _passwordController;
  bool _isDefault = false;
  bool _showPassword = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.connection?.name ?? '',
    );
    _hostController = TextEditingController(
      text: widget.connection?.host ?? '',
    );
    _portController = TextEditingController(
      text: (widget.connection?.port ?? 4455).toString(),
    );
    _passwordController = TextEditingController(
      text: widget.connection?.password ?? '',
    );
    _isDefault = widget.connection?.isDefault ?? false;

    debugPrint(
        'ConnectionDialog init: host=${widget.connection?.host}, password=${widget.connection?.password}');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.connection?.id != null &&
        widget.connection!.id.isNotEmpty &&
        widget.connection?.lastConnected != null;

    return AlertDialog(
      title: Text(isEditing ? 'Редактировать' : 'Новое подключение'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Название',
                hintText: 'Мой OBS',
                prefixIcon: Icon(Icons.label),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: 'Хост / IP',
                hintText: '192.168.1.100',
                prefixIcon: Icon(Icons.computer),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Порт',
                hintText: '4455',
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Пароль (опционально)',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _showPassword = !_showPassword);
                  },
                ),
              ),
              obscureText: !_showPassword,
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('По умолчанию'),
              subtitle: const Text('Автоподключение при запуске'),
              value: _isDefault,
              onChanged: (value) {
                setState(() => _isDefault = value);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final host = _hostController.text.trim();
    final port = int.tryParse(_portController.text.trim()) ?? 4455;
    final password =
        _passwordController.text.isEmpty ? null : _passwordController.text;

    if (host.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите хост или IP адрес')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final provider = context.read<OBSProvider>();

    // Определяем, это редактирование существующего или новое
    final existingId = widget.connection?.id;
    final isExisting = existingId != null &&
        existingId.isNotEmpty &&
        (provider.connections).any((c) => c.id == existingId);

    final connection = OBSConnection(
      id: isExisting ? existingId : const Uuid().v4(),
      name: name.isEmpty ? host : name,
      host: host,
      port: port,
      password: password,
      isDefault: _isDefault,
      lastConnected: widget.connection?.lastConnected,
    );

    debugPrint('Saving connection: ${connection.toJson()}');

    try {
      if (isExisting) {
        await provider.updateConnection(connection);
      } else {
        await provider.addConnection(connection);
      }
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('Error saving connection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  String? _lastScanned;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Сканировать QR код'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller?.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller?.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // Подсказка внизу
          Positioned(
            bottom: 50,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Наведите камеру на QR код в настройках OBS WebSocket\n(Инструменты → Настройки WebSocket сервера → Показать QR)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final value = barcode.rawValue!;

    // Избегаем повторной обработки того же кода
    if (value == _lastScanned) return;
    _lastScanned = value;

    _isProcessing = true;
    debugPrint('QR Code detected: $value');

    try {
      final connection = _parseQRCode(value);
      if (connection != null) {
        // Возвращаем результат на предыдущий экран
        Navigator.of(context).pop(connection);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось распознать QR код OBS')),
        );
        _isProcessing = false;
        _lastScanned = null;
      }
    } catch (e) {
      debugPrint('Error parsing QR: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
      _isProcessing = false;
      _lastScanned = null;
    }
  }

  OBSConnection? _parseQRCode(String value) {
    String host;
    int port = 4455;
    String? password;

    // Формат OBS WebSocket 5.x: obsws://host:port/password
    // Старый формат: obswebsocket|host:port|password
    if (value.startsWith('obsws://')) {
      // Убираем схему
      final withoutScheme = value.substring(8); // убираем "obsws://"

      // Разбираем host:port/password
      final slashIndex = withoutScheme.indexOf('/');
      String hostPort;

      if (slashIndex != -1) {
        hostPort = withoutScheme.substring(0, slashIndex);
        password = withoutScheme.substring(slashIndex + 1);
        // Убираем возможный trailing slash или query string из пароля
        if (password.contains('?')) {
          password = password.split('?').first;
        }
        if (password.isEmpty) {
          password = null;
        }
      } else {
        hostPort = withoutScheme;
      }

      // Разбираем host:port
      final colonIndex = hostPort.lastIndexOf(':');
      if (colonIndex != -1) {
        host = hostPort.substring(0, colonIndex);
        port = int.tryParse(hostPort.substring(colonIndex + 1)) ?? 4455;
      } else {
        host = hostPort;
      }
    } else if (value.startsWith('obswebsocket|')) {
      // Старый формат: obswebsocket|host:port|password
      final parts = value.split('|');
      if (parts.length >= 2) {
        final hostPort = parts[1];
        final colonIndex = hostPort.lastIndexOf(':');
        if (colonIndex != -1) {
          host = hostPort.substring(0, colonIndex);
          port = int.tryParse(hostPort.substring(colonIndex + 1)) ?? 4455;
        } else {
          host = hostPort;
        }
        if (parts.length >= 3 && parts[2].isNotEmpty) {
          password = parts[2];
        }
      } else {
        return null;
      }
    } else if (value.contains(':')) {
      // Простой формат host:port
      final parts = value.split(':');
      host = parts[0];
      port = int.tryParse(parts[1].split('/').first.split('?').first) ?? 4455;
    } else {
      // Только хост
      host = value;
    }

    if (host.isEmpty) {
      return null;
    }

    debugPrint(
        'QR parsed: $host:$port, password: ${password != null ? "SET" : "null"}');

    return OBSConnection(
      id: '', // будет сгенерирован при сохранении
      name: 'OBS ($host)',
      host: host,
      port: port,
      password: password,
    );
  }
}
