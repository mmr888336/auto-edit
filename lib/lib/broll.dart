import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'settings.dart';

/// يجيب مقطع B-roll صغير من Pexels أو Pixabay ويحفظه في outPath (أو null لو فشل)
class BrollFetcher {
  static int _area(dynamic f) =>
      ((f['width'] ?? 0) as num).toInt() * ((f['height'] ?? 0) as num).toInt();

  static Future<String?> fetch(AppSettings s, String query, bool portrait,
      String outPath, int pick) async {
    try {
      String? url;
      final q = Uri.encodeQueryComponent(query);

      if (s.brollProvider == 'pixabay') {
        if (s.pixabayKey.trim().isEmpty) return null;
        final r = await http
            .get(Uri.parse(
                'https://pixabay.com/api/videos/?key=${Uri.encodeQueryComponent(s.pixabayKey.trim())}&q=$q&per_page=5&safesearch=true'))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) return null;
        final hits = (jsonDecode(r.body)['hits'] as List);
        if (hits.isEmpty) return null;
        final v = hits[pick % hits.length]['videos'];
        for (final k in ['small', 'medium', 'tiny']) {
          final u = v[k]?['url'];
          if (u is String && u.isNotEmpty) {
            url = u;
            break;
          }
        }
      } else {
        if (s.pexelsKey.trim().isEmpty) return null;
        final r = await http.get(
          Uri.parse(
              'https://api.pexels.com/videos/search?query=$q&per_page=5&orientation=${portrait ? 'portrait' : 'landscape'}'),
          headers: {'Authorization': s.pexelsKey.trim()},
        ).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) return null;
        final vids = (jsonDecode(r.body)['videos'] as List);
        if (vids.isEmpty) return null;
        final v = vids[pick % vids.length];
        final files = (v['video_files'] as List)
            .where((f) => f['file_type'] == 'video/mp4' && f['link'] != null)
            .toList();
        if (files.isEmpty) return null;
        files.sort((a, b) => _area(a).compareTo(_area(b)));
        // أصغر ملف دقته معقولة (توفير للنت)
        dynamic chosen = files.last;
        for (final f in files) {
          final w = ((f['width'] ?? 0) as num).toInt();
          final h = ((f['height'] ?? 0) as num).toInt();
          if (math.min(w, h) >= 540) {
            chosen = f;
            break;
          }
        }
        url = chosen['link'] as String?;
      }

      if (url == null || url.isEmpty) return null;
      final d = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 90));
      if (d.statusCode != 200 || d.bodyBytes.length > 20 * 1024 * 1024) {
        return null;
      }
      await File(outPath).writeAsBytes(d.bodyBytes);
      return outPath;
    } catch (_) {
      return null;
    }
  }
}