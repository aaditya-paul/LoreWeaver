import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'palette.dart';
import 'story_reader.dart';
import 'auth_screen.dart';
import 'projects_screen.dart';

typedef _Palette = AppPalette;
const _baseUrl = 'http://127.0.0.1:8000';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const LoreWeaverApp());
}

class LoreWeaverApp extends StatelessWidget {
  const LoreWeaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoreWeaver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _Palette.bg,
        colorScheme: const ColorScheme.dark(
          primary: _Palette.red,
          surface: _Palette.surface,
          onSurface: _Palette.textPrimary,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _Palette.card,
          labelStyle: const TextStyle(
            color: _Palette.textSecondary,
            fontSize: 13,
          ),
          hintStyle: const TextStyle(color: _Palette.textMuted, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 16,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _Palette.border, width: 1.2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _Palette.red, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _Palette.red),
          ),
        ),
        dividerColor: _Palette.border,
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(_Palette.borderHover),
          trackColor: WidgetStateProperty.all(_Palette.surface),
          radius: const Radius.circular(4),
        ),
      ),
      home: const AuthScreen(),
    );
  }
}

// ─── Generator Screen (scoped to a project) ───────────────────────────────
class GeneratorScreen extends StatefulWidget {
  final ProjectData project;
  final String token;
  const GeneratorScreen({
    super.key,
    required this.project,
    required this.token,
  });

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _locationController = TextEditingController(
    text: 'Unspecified',
  );
  final TextEditingController _charactersController = TextEditingController();
  final ScrollController _outputScroll = ScrollController();

  // In-session scenes (since last page open) — used for scene count badge only
  final List<StoryScene> _scenes = [];
  bool _readerLoading = false;

  String _responseText = '';
  bool _isLoading = false;
  _GenerationStatus _status = _GenerationStatus.idle;
  String _statusLabel = '';

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _promptController.dispose();
    _locationController.dispose();
    _charactersController.dispose();
    _outputScroll.dispose();
    super.dispose();
  }

  /// Fetch all scenes for the current project from the backend and open reader.
  Future<void> _openReader() async {
    if (_readerLoading) return;
    setState(() => _readerLoading = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/projects/${widget.project.id}/scenes'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      );
      if (!mounted) return;
      final List<StoryScene> scenes;
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        scenes = list.map((s) {
          final criticReport =
              (s['critic_report'] as Map<String, dynamic>?) ?? {};
          return StoryScene(
            index: s['sequence_index'],
            prompt: s['prompt'],
            text: s['scene_text'],
            criticReport: criticReport,
            generatedAt:
                DateTime.tryParse(s['created_at'] ?? '') ?? DateTime.now(),
          );
        }).toList();
      } else {
        scenes = [];
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => StoryReaderPage(scenes: scenes)),
      );
    } catch (_) {
      // silently fall through — reader will open with empty scenes
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StoryReaderPage(scenes: [])),
        );
      }
    } finally {
      if (mounted) setState(() => _readerLoading = false);
    }
  }

  Future<void> _generateScene() async {
    if (_promptController.text.trim().isEmpty) return;

    setState(() {
      _isLoading = true;
      _status = _GenerationStatus.planning;
      _statusLabel = 'Planning scene with Groq…';
      _responseText = '';
    });

    await Future.delayed(const Duration(milliseconds: 300));

    setState(() {
      _status = _GenerationStatus.executing;
      _statusLabel = 'Executing via Local LLM…';
    });

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/generate_scene'),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: jsonEncode({
          'project_id': widget.project.id,
          'user_prompt': _promptController.text,
          'location': _locationController.text.trim().isEmpty
              ? 'Unspecified'
              : _locationController.text.trim(),
          'characters_freetext': _charactersController.text.trim(),
          'active_characters': [],
        }),
      );

      setState(() {
        _status = _GenerationStatus.critiquing;
        _statusLabel = 'Running consistency critique…';
      });

      await Future.delayed(const Duration(milliseconds: 400));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sceneText = data['scene_text'] as String? ?? 'No text generated.';
        final criticReport =
            (data['critic_report'] as Map<String, dynamic>?) ?? {};
        final seqIndex = data['sequence_index'] as int? ?? _scenes.length + 1;
        // Persist location for next scene
        final usedLocation =
            data['location'] as String? ?? _locationController.text.trim();
        setState(() {
          _responseText = sceneText;
          _status = _GenerationStatus.success;
          _statusLabel = 'Scene approved — consistency checks passed.';
          if (usedLocation.isNotEmpty && usedLocation != 'Unspecified') {
            _locationController.text = usedLocation;
          }
          _scenes.add(
            StoryScene(
              index: seqIndex,
              prompt: _promptController.text,
              text: sceneText,
              criticReport: criticReport,
              generatedAt: DateTime.now(),
            ),
          );
        });
      } else {
        setState(() {
          _responseText = 'HTTP ${response.statusCode}\n\n${response.body}';
          _status = _GenerationStatus.error;
          _statusLabel = 'Backend returned an error.';
        });
      }
    } catch (e) {
      setState(() {
        _responseText = e.toString();
        _status = _GenerationStatus.error;
        _statusLabel = 'Could not reach backend.';
      });
    } finally {
      setState(() => _isLoading = false);
      if (_outputScroll.hasClients) {
        _outputScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    }
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildAppBar(),
          _buildPipelineBar(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  _buildPromptCard(),
                  const SizedBox(height: 14),
                  _buildGenerateButton(),
                  const SizedBox(height: 20),
                  _buildStatusRow(),
                  const SizedBox(height: 12),
                  Expanded(child: _buildOutputPanel()),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return Container(
      color: _Palette.surface,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        bottom: 14,
        left: 20,
        right: 20,
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _Palette.redDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _Palette.red.withAlpha(120), width: 1),
            ),
            child: const Icon(
              Icons.auto_stories,
              color: _Palette.red,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LoreWeaver',
                style: TextStyle(
                  color: _Palette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                'Narrative Engine v0.1',
                style: TextStyle(
                  color: _Palette.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Scene counter chip — always visible
          _pill('LOCAL LLM', _Palette.successFg, _Palette.success),
          const SizedBox(width: 8),
          _pill('GROQ', _Palette.red, _Palette.redDim),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _readerLoading ? null : _openReader,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _Palette.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _Palette.border),
              ),
              child: _readerLoading
                  ? const SizedBox(
                      width: 40,
                      height: 14,
                      child: Center(
                        child: SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: _Palette.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : Row(
                      children: [
                        const Icon(
                          Icons.menu_book_rounded,
                          size: 14,
                          color: _Palette.red,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'READ  ALL',
                          style: const TextStyle(
                            color: _Palette.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg.withAlpha(60),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withAlpha(80), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  // ─── Pipeline Bar ─────────────────────────────────────────────────────────
  static const _phaseLabels = ['PLAN', 'EXECUTE', 'CRITIQUE', 'DONE'];
  static const _phaseStatuses = [
    _GenerationStatus.planning,
    _GenerationStatus.executing,
    _GenerationStatus.critiquing,
    _GenerationStatus.success,
  ];

  Widget _buildPipelineBar() {
    return Container(
      color: _Palette.surface,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        children: [
          for (int i = 0; i < _phaseLabels.length; i++) ...[
            _phaseChip(_phaseLabels[i], _phaseStatuses[i]),
            if (i < _phaseLabels.length - 1)
              Expanded(
                child: Container(
                  height: 1,
                  color: _isPhaseActive(_phaseStatuses[i])
                      ? _Palette.red.withAlpha(120)
                      : _Palette.border,
                ),
              ),
          ],
        ],
      ),
    );
  }

  bool _isPhaseActive(_GenerationStatus phase) {
    final order = [
      _GenerationStatus.planning,
      _GenerationStatus.executing,
      _GenerationStatus.critiquing,
      _GenerationStatus.success,
    ];
    final current = order.indexOf(_status);
    final target = order.indexOf(phase);
    return current >= target && _status != _GenerationStatus.idle;
  }

  Widget _phaseChip(String label, _GenerationStatus phase) {
    final active = _isPhaseActive(phase);
    final isCurrent = _status == phase;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCurrent && _isLoading)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Opacity(
              opacity: _pulseAnim.value,
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: _Palette.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          )
        else
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: active ? _Palette.red : _Palette.border,
              shape: BoxShape.circle,
            ),
          ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: active ? _Palette.red : _Palette.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  // ─── Prompt Card ──────────────────────────────────────────────────────────
  Widget _buildPromptCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Location + Characters row ─────────────────────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('LOCATION'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _locationController,
                    style: const TextStyle(
                      color: _Palette.textPrimary,
                      fontSize: 13,
                    ),
                    cursorColor: _Palette.red,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Dark Dungeon',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('CHARACTERS'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _charactersController,
                    style: const TextStyle(
                      color: _Palette.textPrimary,
                      fontSize: 13,
                    ),
                    cursorColor: _Palette.red,
                    decoration: const InputDecoration(
                      hintText: 'e.g. Aria (brave warrior), Mace (old wizard)',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Scene Prompt ──────────────────────────────────────────────────
        _sectionLabel('SCENE PROMPT'),
        const SizedBox(height: 8),
        TextField(
          controller: _promptController,
          maxLines: 4,
          style: const TextStyle(
            color: _Palette.textPrimary,
            fontSize: 14.5,
            height: 1.6,
          ),
          cursorColor: _Palette.red,
          decoration: const InputDecoration(
            hintText:
                'Describe the next scene — e.g., The hero enters the dark tavern…',
            labelText: 'Narrative directive',
          ),
        ),
      ],
    );
  }

  // ─── Generate Button ──────────────────────────────────────────────────────
  Widget _buildGenerateButton() {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _generateScene,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isLoading ? _Palette.border : _Palette.red,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _Palette.border,
          elevation: _isLoading ? 0 : 4,
          shadowColor: _Palette.redGlow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: _isLoading ? _Palette.borderHover : _Palette.red,
              width: 1,
            ),
          ),
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _Palette.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _statusLabel.isNotEmpty ? _statusLabel : 'Processing…',
                    style: const TextStyle(
                      color: _Palette.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bolt_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'GENERATE SCENE',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ─── Status Row ───────────────────────────────────────────────────────────
  Widget _buildStatusRow() {
    if (_status == _GenerationStatus.idle) {
      return Row(
        children: [
          _sectionLabel('OUTPUT'),
          const Spacer(),
          Text(
            'Scene ${_scenes.length}',
            style: const TextStyle(
              color: _Palette.textMuted,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );
    }

    Color statusColor;
    IconData statusIcon;
    switch (_status) {
      case _GenerationStatus.error:
        statusColor = _Palette.red;
        statusIcon = Icons.error_outline_rounded;
        break;
      case _GenerationStatus.success:
        statusColor = _Palette.successFg;
        statusIcon = Icons.check_circle_outline_rounded;
        break;
      default:
        statusColor = _Palette.textSecondary;
        statusIcon = Icons.hourglass_top_rounded;
    }

    return Row(
      children: [
        _sectionLabel('OUTPUT'),
        const SizedBox(width: 12),
        Icon(statusIcon, size: 13, color: statusColor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _statusLabel,
            style: TextStyle(
              color: statusColor,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          'Scene ${_scenes.length}',
          style: const TextStyle(
            color: _Palette.textMuted,
            fontSize: 11,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  // ─── Output Panel ─────────────────────────────────────────────────────────
  Widget _buildOutputPanel() {
    final hasContent = _responseText.isNotEmpty;
    final isError = _status == _GenerationStatus.error;

    return Container(
      decoration: BoxDecoration(
        color: _Palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? _Palette.red.withAlpha(80) : _Palette.border,
          width: 1.2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Panel header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _Palette.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasContent
                        ? (isError ? _Palette.red : _Palette.successFg)
                        : _Palette.border,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  hasContent ? 'narrative_output.txt' : 'awaiting generation…',
                  style: const TextStyle(
                    color: _Palette.textSecondary,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    letterSpacing: 0.4,
                  ),
                ),
                const Spacer(),
                if (hasContent && !isError)
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _responseText));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Copied to clipboard',
                            style: TextStyle(
                              color: _Palette.textPrimary,
                              fontSize: 13,
                            ),
                          ),
                          backgroundColor: _Palette.surface,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: _Palette.border),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    child: const Row(
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: _Palette.textSecondary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'COPY',
                          style: TextStyle(
                            color: _Palette.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: hasContent
                ? Scrollbar(
                    controller: _outputScroll,
                    child: SingleChildScrollView(
                      controller: _outputScroll,
                      padding: const EdgeInsets.all(18),
                      child: SelectableText(
                        _responseText,
                        style: TextStyle(
                          color: isError ? _Palette.red : _Palette.textPrimary,
                          fontSize: 14.5,
                          height: 1.85,
                          letterSpacing: 0.15,
                          fontFamily: isError ? 'monospace' : null,
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_stories_outlined,
                          size: 36,
                          color: _Palette.textMuted,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Your generated scene will appear here.',
                          style: TextStyle(
                            color: _Palette.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── Footer ───────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      color: _Palette.surface,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 10,
        top: 10,
        left: 20,
        right: 20,
      ),
      child: Row(
        children: [
          const Text(
            'Local LLM  ·  Groq  ·  Gemini',
            style: TextStyle(
              color: _Palette.textMuted,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          Text(
            'aaditya-paul / LoreWeaver',
            style: TextStyle(
              color: _Palette.textMuted,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: _Palette.textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

// ─── Enums ───────────────────────────────────────────────────────────────────
enum _GenerationStatus { idle, planning, executing, critiquing, success, error }
