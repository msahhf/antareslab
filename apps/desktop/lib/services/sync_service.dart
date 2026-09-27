// SPDX-License-Identifier: Apache-2.0

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class SDSession {
  final String name;
  final int imageCount;
  final String date;
  final String status;

  SDSession({
    required this.name,
    this.imageCount = 0,
    this.date = '',
    this.status = 'Auto',
  });

  factory SDSession.fromJson(Map<String, dynamic> json) {
    return SDSession(
      name: json['name'] ?? 'Unknown',
      imageCount: json['count'] ?? 0,
      date: DateTime.now().toString().split('.')[0], // Placeholder
    );
  }
}

class SyncService {
  final String espHost;
  SyncService({required this.espHost});

  Future<List<SDSession>> getSessions() async {
    try {
      final response = await http.get(Uri.parse('http://$espHost/sync/list'))
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List sessionsJson = data['sessions'] ?? [];
        return sessionsJson.map((s) => SDSession.fromJson(s)).toList();
      }
    } catch (e) {
      print('Sync error: $e');
    }
    return [];
  }

  Future<void> downloadSession(SDSession session, Function(double) onProgress) async {
    final appDir = await getApplicationDocumentsDirectory();
    final savePath = p.join(appDir.path, 'AntaresStudio', '3D_Scans', session.name);
    
    await Directory(savePath).create(recursive: true);

    // In a real scenario, we'd list files in the session first.
    // Here we simulate downloading 80-90 images.
    for (int i = 0; i < 85; i++) {
      final fileName = 'img_$i.jpg';
      final fileUrl = 'http://$espHost/sync/download/${session.name}/$fileName';
      
      try {
        final response = await http.get(Uri.parse(fileUrl));
        if (response.statusCode == 200) {
          final file = File(p.join(savePath, fileName));
          await file.writeAsBytes(response.bodyBytes);
        }
      } catch (e) {
        print('Download error at $i: $e');
      }
      
      onProgress((i + 1) / 85);
    }
  }
}
