import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'palette.dart';

// ─── Data model for a single scene ──────────────────────────────────────────
class StoryScene {
  final int index;
  final String prompt;
  final String text;
  final Map<String, dynamic> criticReport;
  final DateTime generatedAt;

  const StoryScene({
    required this.index,
    required this.prompt,
    required this.text,
    required this.criticReport,
    required this.generatedAt,
  });

  double get tas =>
      (criticReport['metrics']?['trait_adherence_score'] as num?)?.toDouble() ??
      0.0;

  bool get approved => criticReport['approved'] == true;
}

// ─── Story Reader Page ───────────────────────────────────────────────────────
class StoryReaderPage extends StatefulWidget {
  final List<StoryScene> scenes;

  const StoryReaderPage({super.key, required this.scenes});

  @override
  State<StoryReaderPage> createState() => _StoryReaderPageState();
}

class _StoryReaderPageState extends State<StoryReaderPage> {
  final ScrollController _scroll = ScrollController();
  double _fontSize = 16.0;
  bool _showMeta = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _copyAll() {
    final full = widget.scenes
        .map((s) => '── Scene ${s.index} ──\n\n${s.text}')
        .join('\n\n\n');
    Clipboard.setData(ClipboardData(text: full));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Full story copied to clipboard',
          style: TextStyle(color: AppPalette.textPrimary, fontSize: 13),
        ),
        backgroundColor: AppPalette.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppPalette.border),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: Column(
        children: [
          _buildAppBar(context),
          _buildToolbar(),
          Expanded(
            child: widget.scenes.isEmpty
                ? _buildEmpty()
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.separated(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 48),
                      itemCount: widget.scenes.length,
                      separatorBuilder: (_, __) => _buildDivider(),
                      itemBuilder: (_, i) => _buildSceneBlock(widget.scenes[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── AppBar ──────────────────────────────────────────────────────────────
  Widget _buildAppBar(BuildContext context) {
    return Container(
      color: AppPalette.surface,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 14,
        bottom: 14,
        left: 16,
        right: 16,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppPalette.textSecondary,
              size: 18,
            ),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          const Icon(Icons.menu_book_rounded, color: AppPalette.red, size: 20),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Story Reader',
                style: TextStyle(
                  color: AppPalette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                '${widget.scenes.length} scene${widget.scenes.length == 1 ? '' : 's'}  ·  '
                '${widget.scenes.fold(0, (sum, s) => sum + s.text.split(' ').length)} words',
                style: const TextStyle(
                  color: AppPalette.textSecondary,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const Spacer(),
          _headerAction(Icons.copy_all_rounded, 'COPY ALL', _copyAll),
        ],
      ),
    );
  }

  Widget _headerAction(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.border, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: AppPalette.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.9,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Toolbar ─────────────────────────────────────────────────────────────
  Widget _buildToolbar() {
    return Container(
      color: AppPalette.surface,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // Font size controls
          const Text(
            'SIZE',
            style: TextStyle(
              color: AppPalette.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 10),
          _toolbarBtn(Icons.text_decrease_rounded, () {
            setState(() => _fontSize = (_fontSize - 1).clamp(12.0, 24.0));
          }),
          const SizedBox(width: 4),
          Text(
            _fontSize.toInt().toString(),
            style: const TextStyle(
              color: AppPalette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          _toolbarBtn(Icons.text_increase_rounded, () {
            setState(() => _fontSize = (_fontSize + 1).clamp(12.0, 24.0));
          }),
          const Spacer(),
          // Meta toggle
          GestureDetector(
            onTap: () => setState(() => _showMeta = !_showMeta),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _showMeta
                    ? AppPalette.red.withAlpha(30)
                    : AppPalette.card,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: _showMeta
                      ? AppPalette.red.withAlpha(100)
                      : AppPalette.border,
                ),
              ),
              child: Text(
                'META',
                style: TextStyle(
                  color: _showMeta ? AppPalette.red : AppPalette.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppPalette.border),
        ),
        child: Icon(icon, size: 14, color: AppPalette.textSecondary),
      ),
    );
  }

  // ─── Divider ─────────────────────────────────────────────────────────────
  Widget _buildDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: AppPalette.border, thickness: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppPalette.redDim,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const Expanded(
            child: Divider(color: AppPalette.border, thickness: 1),
          ),
        ],
      ),
    );
  }

  // ─── Scene Block ─────────────────────────────────────────────────────────
  Widget _buildSceneBlock(StoryScene scene) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scene header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppPalette.redDim.withAlpha(60),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppPalette.red.withAlpha(80)),
              ),
              child: Text(
                'SCENE ${scene.index}',
                style: const TextStyle(
                  color: AppPalette.red,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _timeAgo(scene.generatedAt),
                style: const TextStyle(
                  color: AppPalette.textMuted,
                  fontSize: 11,
                ),
              ),
            ),
            if (scene.approved)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 12,
                    color: AppPalette.successFg,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'TAS ${(scene.tas * 100).toInt()}%',
                    style: const TextStyle(
                      color: AppPalette.successFg,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Prompt tag
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppPalette.card,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppPalette.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.format_quote_rounded,
                size: 13,
                color: AppPalette.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  scene.prompt,
                  style: const TextStyle(
                    color: AppPalette.textSecondary,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Narrative text
        const SizedBox(height: 20),
        SelectableText(
          scene.text,
          style: TextStyle(
            color: AppPalette.textPrimary,
            fontSize: _fontSize,
            height: 1.9,
            letterSpacing: 0.2,
          ),
        ),

        // Meta panel
        if (_showMeta) ...[const SizedBox(height: 20), _buildMetaPanel(scene)],
      ],
    );
  }

  // ─── Meta Panel ──────────────────────────────────────────────────────────
  Widget _buildMetaPanel(StoryScene scene) {
    final metrics = scene.criticReport['metrics'] as Map? ?? {};
    final drifts =
        (metrics['state_drift_detected'] as List?)?.cast<String>() ?? [];
    final flags = metrics['temporal_continuity_flags'] ?? 0;
    final justification = scene.criticReport['justification'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CONSISTENCY REPORT',
            style: TextStyle(
              color: AppPalette.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _metricChip(
                'TAS',
                '${(scene.tas * 100).toInt()}%',
                AppPalette.successFg,
              ),
              const SizedBox(width: 10),
              _metricChip(
                'Continuity Flags',
                '$flags',
                flags == 0 ? AppPalette.successFg : AppPalette.red,
              ),
              const SizedBox(width: 10),
              _metricChip(
                'Approved',
                scene.approved ? 'YES' : 'NO',
                scene.approved ? AppPalette.successFg : AppPalette.red,
              ),
            ],
          ),
          if (drifts.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'STATE DRIFT DETECTED',
              style: TextStyle(
                color: AppPalette.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: drifts
                  .map(
                    (d) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppPalette.red.withAlpha(20),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppPalette.red.withAlpha(60)),
                      ),
                      child: Text(
                        d,
                        style: const TextStyle(
                          color: AppPalette.red,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (justification.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              justification,
              style: const TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 12,
                height: 1.6,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricChip(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppPalette.textMuted,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Empty state ─────────────────────────────────────────────────────────
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.menu_book_outlined, size: 48, color: AppPalette.textMuted),
          SizedBox(height: 16),
          Text(
            'No scenes generated yet.',
            style: TextStyle(color: AppPalette.textMuted, fontSize: 14),
          ),
          SizedBox(height: 6),
          Text(
            'Go back and generate some scenes first.',
            style: TextStyle(color: AppPalette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}
