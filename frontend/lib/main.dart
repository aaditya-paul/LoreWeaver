import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const LoreWeaverApp());
}

class LoreWeaverApp extends StatelessWidget {
  const LoreWeaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LoreWeaver API Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoreWeaverHomePage(),
    );
  }
}

class LoreWeaverHomePage extends StatefulWidget {
  const LoreWeaverHomePage({super.key});

  @override
  State<LoreWeaverHomePage> createState() => _LoreWeaverHomePageState();
}

class _LoreWeaverHomePageState extends State<LoreWeaverHomePage> {
  final TextEditingController _promptController = TextEditingController();
  String _responseText = "Generated scene will appear here.";
  bool _isLoading = false;

  Future<void> _generateScene() async {
    setState(() {
      _isLoading = true;
      _responseText = "Generating next scene (Local LLM -> Groq Critic)...";
    });

    try {
      final response = await http.post(
        Uri.parse('http://127.0.0.1:8000/generate_scene'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(<String, dynamic>{
          'user_prompt': _promptController.text,
          'active_characters': ['char_1'], // Mock data for now
          'location': 'Tavern',
          'seq_index': 1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _responseText = data['scene_text'] ?? "No text generated.";
        });
      } else {
        setState(() {
          _responseText =
              "Error (HTTP ${response.statusCode}): ${response.body}";
        });
      }
    } catch (e) {
      setState(() {
        _responseText = "Failed to connect to backend: $e";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LoreWeaver MVP Engine'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _promptController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Scene Prompt',
                hintText: 'e.g., The hero enters the dark tavern...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _generateScene,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('Generate Scene'),
            ),
            const SizedBox(height: 24),
            const Text(
              'Output:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_responseText),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
