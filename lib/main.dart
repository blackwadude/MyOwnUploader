import 'dart:io';

import 'package:flutter/material.dart';
import 'package:nativeupload/channel.dart'; // your existing channel

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Native Video Uploader',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.teal),
      home: const PickAndPreviewPage(),
    );
  }
}

class PickAndPreviewPage extends StatefulWidget {
  const PickAndPreviewPage({super.key});

  @override
  State<PickAndPreviewPage> createState() => _PickAndPreviewPageState();
}

class _PickAndPreviewPageState extends State<PickAndPreviewPage> {
  String? _thumbPath;

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _pick() async {
    final res = await VideoChannel.pickOrCapture();
    if (res == null) {
      return;
    }

    final video = res['path'];
    final thumb = res['thumbnail'];

    debugPrint('video: $video');
    debugPrint('thumb: $thumb');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Native Video Uploader')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ─── Pick Button ───────────────────────────────────────────
            ElevatedButton.icon(
              icon: const Icon(Icons.cloud_upload),
              label: const Text('Pick / Capture'),
              onPressed: _pick,
            ),
            const SizedBox(height: 30),

            // ─── Thumbnail (if any) ───────────────────────────────────
            if (_thumbPath != null)
              Column(
                children: [
                  Text(
                    'Thumbnail',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Image.file(File(_thumbPath!), height: 200),
                  const SizedBox(height: 30),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
