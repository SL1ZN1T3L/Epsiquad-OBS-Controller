import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

enum ChatPlatform { twitch, youtube }

class StreamChatScreen extends StatefulWidget {
  const StreamChatScreen({super.key});

  @override
  State<StreamChatScreen> createState() => _StreamChatScreenState();
}

class _StreamChatScreenState extends State<StreamChatScreen> {
  ChatPlatform _platform = ChatPlatform.twitch;
  String _username = '';
  String _videoId = '';
  bool _isLoading = false;
  bool _chatActive = false;
  WebViewController? _webController;

  final _usernameController = TextEditingController();
  final _videoIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _videoIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _platform = ChatPlatform
          .values[prefs.getInt('chatPlatform') ?? 0];
      _username = prefs.getString('chatUsername') ?? '';
      _videoId = prefs.getString('chatVideoId') ?? '';
      _usernameController.text = _username;
      _videoIdController.text = _videoId;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('chatPlatform', _platform.index);
    await prefs.setString('chatUsername', _username);
    await prefs.setString('chatVideoId', _videoId);
  }

  void _openChat() {
    String? url;

    if (_platform == ChatPlatform.twitch) {
      if (_username.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Введите имя канала Twitch'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      url = 'https://www.twitch.tv/popout/$_username/chat?popout=&darkpopout';
    } else {
      if (_videoId.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Введите ID видео YouTube'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      url =
          'https://www.youtube.com/live_chat?v=$_videoId&embed_domain=obscontroller&dark_theme=1';
    }

    _saveSettings();

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..loadRequest(Uri.parse(url));

    setState(() {
      _webController = controller;
      _chatActive = true;
      _isLoading = true;
    });

    controller.setNavigationDelegate(
      NavigationDelegate(
        onPageFinished: (_) {
          if (mounted) setState(() => _isLoading = false);
          // Инжектим CSS для тёмной темы и очистки UI
          controller.runJavaScript('''
            document.body.style.backgroundColor = '#0e0e10';
            // Убираем лишние элементы Twitch
            const style = document.createElement('style');
            style.textContent = `
              .consent-banner, .twilight-minimal-root > div:first-child,
              .stream-chat-header, [data-a-target="right-column-chat-input-message-queue"] {
                display: none !important;
              }
              body { background: #0e0e10 !important; }
            `;
            document.head.appendChild(style);
          ''');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат стрима'),
        actions: [
          if (_chatActive)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _webController?.reload(),
            ),
          if (_chatActive)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _chatActive = false),
            ),
        ],
      ),
      body: _chatActive ? _buildChat() : _buildSetup(),
    );
  }

  Widget _buildSetup() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Выбор платформы
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Платформа',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SegmentedButton<ChatPlatform>(
                    segments: const [
                      ButtonSegment(
                        value: ChatPlatform.twitch,
                        label: Text('Twitch'),
                        icon: Icon(Icons.live_tv),
                      ),
                      ButtonSegment(
                        value: ChatPlatform.youtube,
                        label: Text('YouTube'),
                        icon: Icon(Icons.play_circle),
                      ),
                    ],
                    selected: {_platform},
                    onSelectionChanged: (set) {
                      setState(() => _platform = set.first);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Настройки
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_platform == ChatPlatform.twitch) ...[
                    const Text('Канал Twitch',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        hintText: 'epsiquad',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (v) => _username = v.trim(),
                    ),
                  ] else ...[
                    const Text('ID видео YouTube',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _videoIdController,
                      decoration: InputDecoration(
                        hintText: 'dQw4w9WgXcQ',
                        prefixIcon: const Icon(Icons.link),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        helperText: 'ID из URL: youtube.com/watch?v=...',
                      ),
                      onChanged: (v) => _videoId = v.trim(),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _openChat,
            icon: const Icon(Icons.chat),
            label: const Text('Открыть чат'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChat() {
    return Stack(
      children: [
        if (_webController != null)
          WebViewWidget(controller: _webController!),
        if (_isLoading)
          const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
