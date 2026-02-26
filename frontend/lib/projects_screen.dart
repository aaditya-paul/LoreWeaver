import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'palette.dart';
import 'story_reader.dart';
import 'main.dart' show GeneratorScreen;

const _base = 'http://127.0.0.1:8000';

// ─── Data model ──────────────────────────────────────────────────────────────
class ProjectData {
  final String id;
  final String name;
  final String? description;
  final int sceneCount;
  final String createdAt;

  const ProjectData({
    required this.id,
    required this.name,
    this.description,
    required this.sceneCount,
    required this.createdAt,
  });

  factory ProjectData.fromJson(Map<String, dynamic> j) => ProjectData(
    id: j['id'],
    name: j['name'],
    description: j['description'],
    sceneCount: j['scene_count'] ?? 0,
    createdAt: j['created_at'] ?? '',
  );
}

// ─── Projects Screen ─────────────────────────────────────────────────────────
class ProjectsScreen extends StatefulWidget {
  final String token;
  final String email;
  const ProjectsScreen({super.key, required this.token, required this.email});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<ProjectData> _projects = [];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadProjects();
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${widget.token}',
  };

  Future<void> _loadProjects() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await http.get(
        Uri.parse('$_base/projects'),
        headers: _headers,
      );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        setState(
          () => _projects = list.map((e) => ProjectData.fromJson(e)).toList(),
        );
      } else {
        setState(() => _error = 'Failed to load projects.');
      }
    } catch (e) {
      setState(() => _error = 'Cannot reach backend.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createProject(String name, String? description) async {
    final res = await http.post(
      Uri.parse('$_base/projects'),
      headers: _headers,
      body: jsonEncode({'name': name, 'description': description}),
    );
    if (res.statusCode == 201) {
      _loadProjects();
    }
  }

  Future<void> _deleteProject(String id) async {
    await http.delete(Uri.parse('$_base/projects/$id'), headers: _headers);
    _loadProjects();
  }

  Future<List<StoryScene>> _fetchScenes(ProjectData project) async {
    final res = await http.get(
      Uri.parse('$_base/projects/${project.id}/scenes'),
      headers: _headers,
    );
    if (res.statusCode != 200) return [];
    final list = jsonDecode(res.body) as List;
    return list.map((s) {
      final criticReport = (s['critic_report'] as Map<String, dynamic>?) ?? {};
      return StoryScene(
        id: s['id'] ?? '',
        index: s['sequence_index'],
        prompt: s['prompt'],
        text: s['scene_text'],
        criticReport: criticReport,
        generatedAt: DateTime.tryParse(s['created_at'] ?? '') ?? DateTime.now(),
      );
    }).toList();
  }

  void _openGenerator(ProjectData project) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GeneratorScreen(project: project, token: widget.token),
      ),
    );
  }

  Future<void> _openReader(ProjectData project) async {
    final scenes = await _fetchScenes(project);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoryReaderPage(
          scenes: scenes,
          projectId: project.id,
          token: widget.token,
        ),
      ),
    );
  }

  void _showNewProjectDialog() {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'New Project',
          style: TextStyle(
            color: AppPalette.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _dialogLabel('PROJECT NAME'),
            const SizedBox(height: 6),
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: const TextStyle(
                color: AppPalette.textPrimary,
                fontSize: 14,
              ),
              cursorColor: AppPalette.red,
              decoration: _dialogInput('e.g. The Dark Chronicles'),
            ),
            const SizedBox(height: 14),
            _dialogLabel('DESCRIPTION (OPTIONAL)'),
            const SizedBox(height: 6),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              style: const TextStyle(
                color: AppPalette.textPrimary,
                fontSize: 14,
              ),
              cursorColor: AppPalette.red,
              decoration: _dialogInput(
                'Short description of your story world…',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'CANCEL',
              style: TextStyle(
                color: AppPalette.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              _createProject(
                name,
                descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'CREATE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppPalette.red),
                  )
                : _error.isNotEmpty
                ? _buildError()
                : _projects.isEmpty
                ? _buildEmpty()
                : _buildProjectList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      color: AppPalette.surface,
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
              color: AppPalette.redDim,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppPalette.red.withAlpha(120),
                width: 1,
              ),
            ),
            child: const Icon(
              Icons.auto_stories,
              color: AppPalette.red,
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
                  color: AppPalette.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              Text(
                widget.email,
                style: const TextStyle(
                  color: AppPalette.textSecondary,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const Spacer(),
          GestureDetector(
            onTap: _showNewProjectDialog,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppPalette.red,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.add_rounded, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'NEW',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
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

  Widget _buildProjectList() {
    return RefreshIndicator(
      color: AppPalette.red,
      backgroundColor: AppPalette.surface,
      onRefresh: _loadProjects,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        itemCount: _projects.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildProjectCard(_projects[i]),
      ),
    );
  }

  Widget _buildProjectCard(ProjectData p) {
    return GestureDetector(
      onTap: () => _openGenerator(p),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppPalette.redDim.withAlpha(60),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppPalette.red.withAlpha(60),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.book_outlined,
                color: AppPalette.red,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.name,
                    style: const TextStyle(
                      color: AppPalette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (p.description != null && p.description!.isNotEmpty)
                    Text(
                      p.description!,
                      style: const TextStyle(
                        color: AppPalette.textSecondary,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 5),
                  Text(
                    '${p.sceneCount} ${p.sceneCount == 1 ? 'scene' : 'scenes'}',
                    style: const TextStyle(
                      color: AppPalette.textMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // READ button — always visible
            _iconBtn(
              icon: Icons.menu_book_rounded,
              color: AppPalette.successFg,
              onTap: () => _openReader(p),
            ),
            const SizedBox(width: 8),
            // Delete
            _iconBtn(
              icon: Icons.delete_outline_rounded,
              color: AppPalette.textMuted,
              onTap: () => _confirmDelete(p),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppPalette.border),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }

  void _confirmDelete(ProjectData p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppPalette.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Delete Project?',
          style: TextStyle(
            color: AppPalette.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'This will permanently delete "${p.name}" and all its scenes.',
          style: const TextStyle(color: AppPalette.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 12),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteProject(p.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'DELETE',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_stories_outlined,
            size: 52,
            color: AppPalette.textMuted,
          ),
          const SizedBox(height: 16),
          const Text(
            'No projects yet',
            style: TextStyle(
              color: AppPalette.textSecondary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap NEW to create your first story project.',
            style: TextStyle(color: AppPalette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _showNewProjectDialog,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('CREATE PROJECT'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 40,
            color: AppPalette.red,
          ),
          const SizedBox(height: 12),
          Text(
            _error,
            style: const TextStyle(
              color: AppPalette.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadProjects,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('RETRY'),
          ),
        ],
      ),
    );
  }

  Widget _dialogLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: AppPalette.textSecondary,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );

  InputDecoration _dialogInput(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppPalette.textMuted, fontSize: 13),
    filled: true,
    fillColor: AppPalette.card,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppPalette.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppPalette.red, width: 1.5),
    ),
  );
}
