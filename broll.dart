import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'settings.dart';

/// يجيب مقطع B-roll صغير من Pexels أو Pixabay ويحفظه في outPath (أو null لو فشل).
/// يتجاهل النتائج اللي وصفها فيه كلمات نسائية، ثم يفحصها Gemini بصرياً في المرحلة التالية.
class BrollFetcher {
  static const _blocked = [
    'woman', 'women', 'girl', 'girls', 'female', 'lady', 'ladies',
    'bikini', 'mother', 'bride', 'actress',
  ];

  static bool _bad(String text) {
    final l = text.toLowerCase();
    for (final w in _blocked) {
      if (RegExp('(^|[^a-z])$w([^a-z]|\$)').hasMatch(l)) return true;
    }
    return false;
  }

  static int _area(dynamic f) =>
      ((f['width'] ?? 0) as num).toInt() * ((f['height'] ?? 0) as num).toInt();

  /// animation=true: يطلب رسوم متحركة 2D من Pixabay (يحتاج مفتاح Pixabay)
  static Future<String?> fetch(AppSettings s, String query, bool portrait,
      String outPath, int pick,
      {bool animation = false}) async {
    try {
      String? url;
      final q = Uri.encodeQueryComponent(query);

      if (animation || s.brollProvider == 'pixabay') {
        final key = s.pixabayKey.trim();
        if (key.isEmpty) return null;
        final type = animation ? '&video_type=animation' : '';
        final r = await http
            .get(Uri.parse(
                'https://pixabay.com/api/videos/?key=${Uri.encodeQueryComponent(key)}&q=$q&per_page=20&safesearch=true$type'))
            .timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) return null;
        final hits = (jsonDecode(r.body)['hits'] as List)
            .where((h) => !_bad('${h['tags']} ${h['pageURL']}'))
            .toList();
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
        final key = s.pexelsKey.trim();
        if (key.isEmpty) return null;
        final r = await http.get(
          Uri.parse(
              'https://api.pexels.com/videos/search?query=$q&per_page=15&orientation=${portrait ? 'portrait' : 'landscape'}'),
          headers: {'Authorization': key},
        ).timeout(const Duration(seconds: 20));
        if (r.statusCode != 200) return null;
        final vids = (jsonDecode(r.body)['videos'] as List)
            .where((v) => !_bad('${v['url']}'))
            .toList();
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
