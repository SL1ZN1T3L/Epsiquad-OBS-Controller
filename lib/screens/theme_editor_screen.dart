import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show themeNotifier;

const _prefsKey = 'custom_theme';

class AppTheme {
  final String name;
  final Color seedColor;
  final Brightness brightness;

  AppTheme({
    required this.name,
    required this.seedColor,
    this.brightness = Brightness.dark,
  });

  ThemeData toThemeData() {
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
      ),
      useMaterial3: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'color': seedColor.toARGB32(),
        'brightness': brightness.index,
      };

  factory AppTheme.fromJson(Map<String, dynamic> json) {
    return AppTheme(
      name: json['name'] as String,
      seedColor: Color(json['color'] as int),
      brightness: Brightness.values[json['brightness'] as int? ?? 1],
    );
  }

  static AppTheme get defaultTheme => AppTheme(
        name: 'По умолчанию',
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      );

  static final List<AppTheme> presets = [
    AppTheme(name: 'Синий', seedColor: Colors.blue),
    AppTheme(name: 'Фиолетовый', seedColor: Colors.deepPurple),
    AppTheme(name: 'Зелёный', seedColor: Colors.green),
    AppTheme(name: 'Красный', seedColor: Colors.red),
    AppTheme(name: 'Оранжевый', seedColor: Colors.orange),
    AppTheme(name: 'Бирюзовый', seedColor: Colors.teal),
    AppTheme(name: 'Розовый', seedColor: Colors.pink),
    AppTheme(name: 'Индиго', seedColor: Colors.indigo),
    AppTheme(name: 'Янтарный', seedColor: Colors.amber),
    AppTheme(name: 'Циан', seedColor: Colors.cyan),
  ];

  static Future<AppTheme?> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json == null) return null;
    try {
      return AppTheme.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AppTheme theme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(theme.toJson()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}

// ==================== UI ====================

class ThemeEditorScreen extends StatefulWidget {
  final void Function(ThemeData theme)? onThemeChanged;

  const ThemeEditorScreen({super.key, this.onThemeChanged});

  @override
  State<ThemeEditorScreen> createState() => _ThemeEditorScreenState();
}

class _ThemeEditorScreenState extends State<ThemeEditorScreen> {
  Color _selectedColor = Colors.blue;
  String _themeName = 'Моя тема';
  Brightness _brightness = Brightness.dark;
  final _nameController = TextEditingController(text: 'Моя тема');

  // Кастомные сохранённые темы
  List<AppTheme> _savedThemes = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentTheme();
    _loadSavedThemes();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentTheme() async {
    final saved = await AppTheme.loadSaved();
    if (saved != null && mounted) {
      setState(() {
        _selectedColor = saved.seedColor;
        _themeName = saved.name;
        _brightness = saved.brightness;
        _nameController.text = saved.name;
      });
    }
  }

  Future<void> _loadSavedThemes() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('saved_themes');
    if (json != null) {
      try {
        final list = jsonDecode(json) as List;
        setState(() {
          _savedThemes = list
              .map((e) => AppTheme.fromJson(e as Map<String, dynamic>))
              .toList();
        });
      } catch (_) {}
    }
  }

  Future<void> _saveSavedThemes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'saved_themes', jsonEncode(_savedThemes.map((t) => t.toJson()).toList()));
  }

  void _applyTheme(AppTheme theme) {
    setState(() {
      _selectedColor = theme.seedColor;
      _brightness = theme.brightness;
      _themeName = theme.name;
      _nameController.text = theme.name;
    });
    AppTheme.save(theme);
    themeNotifier.value = theme.toThemeData();
    widget.onThemeChanged?.call(theme.toThemeData());
  }

  void _applyCurrentColor() {
    final theme = AppTheme(
      name: _themeName,
      seedColor: _selectedColor,
      brightness: _brightness,
    );
    _applyTheme(theme);
  }

  Future<void> _resetToDefault() async {
    await AppTheme.clear();
    final defaultTheme = AppTheme.defaultTheme;
    setState(() {
      _selectedColor = defaultTheme.seedColor;
      _brightness = defaultTheme.brightness;
      _themeName = defaultTheme.name;
      _nameController.text = defaultTheme.name;
    });
    themeNotifier.value = defaultTheme.toThemeData();
    widget.onThemeChanged?.call(defaultTheme.toThemeData());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Тема сброшена'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewTheme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: _selectedColor,
        brightness: _brightness,
      ),
      useMaterial3: true,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Оформление'),
        actions: [
          TextButton(
            onPressed: _resetToDefault,
            child: const Text('Сбросить'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Превью
          Card(
            color: previewTheme.colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Предпросмотр',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PreviewChip('Primary', previewTheme.colorScheme.primary),
                      _PreviewChip(
                          'Secondary', previewTheme.colorScheme.secondary),
                      _PreviewChip(
                          'Tertiary', previewTheme.colorScheme.tertiary),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _PreviewChip('Error', previewTheme.colorScheme.error),
                      _PreviewChip(
                          'Surface', previewTheme.colorScheme.surfaceContainerHighest),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Пресеты
          const Text('Пресеты',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AppTheme.presets.map((preset) {
              final isSelected = preset.seedColor.toARGB32() == _selectedColor.toARGB32();
              return GestureDetector(
                onTap: () => _applyTheme(preset),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: preset.seedColor,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: preset.seedColor.withValues(alpha: 0.5),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 24),

          // Custom цвет
          const Text('Свой цвет',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Hue слайдер
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Оттенок', style: TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 8),
                  _HueSlider(
                    hue: HSVColor.fromColor(_selectedColor).hue,
                    onChanged: (hue) {
                      setState(() {
                        _selectedColor =
                            HSVColor.fromAHSV(1.0, hue, 0.8, 0.9).toColor();
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _applyCurrentColor,
                    child: const Text('Применить'),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Режим
          Card(
            child: SwitchListTile(
              title: const Text('Светлая тема'),
              subtitle: const Text('Переключение между тёмной и светлой'),
              value: _brightness == Brightness.light,
              onChanged: (value) {
                setState(() {
                  _brightness = value ? Brightness.light : Brightness.dark;
                });
                _applyCurrentColor();
              },
            ),
          ),

          // Сохранённые темы
          if (_savedThemes.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text('Сохранённые',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            ...(_savedThemes.asMap().entries.map((entry) {
              final theme = entry.value;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.seedColor,
                    radius: 16,
                  ),
                  title: Text(theme.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check, size: 20),
                        onPressed: () => _applyTheme(theme),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                        onPressed: () {
                          setState(() => _savedThemes.removeAt(entry.key));
                          _saveSavedThemes();
                        },
                      ),
                    ],
                  ),
                ),
              );
            })),
          ],

          const SizedBox(height: 16),

          // Сохранить текущую
          OutlinedButton.icon(
            onPressed: () {
              final theme = AppTheme(
                name: _themeName,
                seedColor: _selectedColor,
                brightness: _brightness,
              );
              setState(() => _savedThemes.add(theme));
              _saveSavedThemes();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Тема сохранена'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Сохранить тему'),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _PreviewChip extends StatelessWidget {
  final String label;
  final Color color;

  const _PreviewChip(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }
}

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueSlider({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 16,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
        trackShape: _HueTrackShape(),
      ),
      child: Slider(
        value: hue,
        min: 0,
        max: 360,
        onChanged: onChanged,
      ),
    );
  }
}

class _HueTrackShape extends SliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 16;
    final trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(
        offset.dx + 12, trackTop, parentBox.size.width - 24, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

    final colors = List.generate(
      7,
      (i) => HSVColor.fromAHSV(1.0, i * 60.0, 0.8, 0.9).toColor(),
    );

    final gradient = LinearGradient(colors: colors);
    final paint = Paint()..shader = gradient.createShader(rect);

    context.canvas.drawRRect(rrect, paint);
  }
}
