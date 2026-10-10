import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'settings.dart';

class Caption {
  final double start;
  double end;
  final String text;
  Caption(this.start, this.end, this.text);
}

class BrollIdea {
  final double start;
  final double end;
  final String query;
  BrollIdea(this.start, this.end, this.query);
}

class Analysis {
  final List<Caption> captions;
  final String title;
  final String description;
  final List<String> hashtags;
  final List<BrollIdea> broll;
  Analysis(this.captions, this.title, this.description, this.hashtags, this.broll);
}

/// Gemini يسمع الصوت فعلاً ويرجع: كابشن بالتوقيت + عنوان + وصف + هاشتاقات + أفكار B-roll
class Analyzer {
  static double _num(dynamic v) =>
      v is num ? v.toDouble() : (double.tryParse('$v') ?? 0.0);

  static Uri _url(AppSettings s) => Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/${s.geminiModel}:generateContent');

  static Map<String, String> _headers(AppSettings s) => {
        'Content-Type': 'application/json',
        'x-goog-api-key': s.geminiKey.trim(),
      };

  static String _cut(String s) => s.length > 300 ? s.substring(0, 300) : s;

  static Future<Analysis> run(
      AppSettings s, String wavPath, double durationSec) async {
    if (s.geminiKey.trim().isEmpty) {
      throw Exception('التحليل الصوتي يحتاج مفتاح Gemini في الإعدادات.');
    }
    final bytes = await File(wavPath).readAsBytes();
    final prompt = '''
أنت محرر فيديوهات قصيرة (ريلز / تيك توك). استمع للصوت المرفق (غالباً كلام عربي بلهجة سودانية أو عامية). مدة الصوت ${durationSec.toStringAsFixed(1)} ثانية.
أرجع JSON فقط، بدون أي شرح وبدون علامات markdown، بهذا الشكل بالضبط:
{"segments":[{"start":0.0,"end":1.6,"text":"..."}],"title":"...","description":"...","hashtags":["..."],"broll":[{"start":5.0,"end":7.5,"query":"..."}]}
القواعد:
- segments: قسّم الكلام لمقاطع قصيرة (من 2 إلى 5 كلمات). وقت البداية والنهاية بالثواني العشرية (مثل 12.4) وليس بصيغة دقائق:ثواني. اكتب الكلام بنفس لهجة المتحدث كما نطقه بدون تحويله للفصحى وبدون علامات ترقيم. لا تكتب شيئاً في فترات الصمت أو الموسيقى.
- title: عنوان جذاب يشد الانتباه في أول 3 ثواني، من 3 إلى 7 كلمات، بنفس لغة الفيديو.
- description: وصف قصير للنشر (سطرين على الأكثر).
- hashtags: من 5 إلى 8 هاشتاقات بدون علامة #.
- broll: من 2 إلى 4 لحظات يناسبها مقطع توضيحي (B-roll) بعد الثانية 4، كل واحدة بين 2 و3 ثواني. اجعل المقطع مرتبطاً بمعنى الكلام في تلك اللحظة تحديداً (فكرة مختلفة لكل لحظة). query كلمات بحث إنجليزية بسيطة (من 1 إلى 3 كلمات). مهم جداً: اختر مشاهد وأشياء وأماكن وطبيعة ومفاهيم (مثل money, city night, laptop, sunrise, shopping, phone, ocean, graph) ولا تذكر أشخاصاً ولا نساء ولا وجوهاً في الكلمات. لو ما في لحظات مناسبة اترك المصفوفة فاضية.
''';

    final r = await http
        .post(
          _url(s),
          headers: _headers(s),
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'inline_data': {
                      'mime_type': 'audio/wav',
                      'data': base64Encode(bytes),
                    }
                  },
                  {'text': prompt},
                ]
              }
            ],
            'generationConfig': {
              'responseMimeType': 'application/json',
              'temperature': 0.3,
            },
          }),
        )
        .timeout(const Duration(seconds: 180));

    if (r.statusCode != 200) {
      throw Exception('Gemini ${r.statusCode}: ${_cut(r.body)}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final text = j['candidates'][0]['content']['parts'][0]['text'] as String;
    final a = text.indexOf('{');
    final b = text.lastIndexOf('}');
    if (a < 0 || b <= a) throw Exception('رد غير مفهوم من الذكاء الاصطناعي');
    final m = jsonDecode(text.substring(a, b + 1)) as Map<String, dynamic>;

    final caps = <Caption>[];
    for (final e in (m['segments'] as List? ?? [])) {
      final st = _num(e['start']);
      var en = _num(e['end']);
      final t = '${e['text'] ?? ''}'.trim();
      if (t.isEmpty || st < 0 || st >= durationSec) continue;
      if (en > durationSec) en = durationSec;
      if (en - st < 0.2) continue;
      caps.add(Caption(st, en, t));
    }
    caps.sort((x, y) => x.start.compareTo(y.start));
    for (var i = 0; i < caps.length - 1; i++) {
      if (caps[i].end > caps[i + 1].start) caps[i].end = caps[i + 1].start;
    }
    caps.removeWhere((c) => c.end - c.start < 0.15);

    final broll = <BrollIdea>[];
    for (final e in (m['broll'] as List? ?? [])) {
      final q = '${e['query'] ?? ''}'.trim();
      if (q.isEmpty) continue;
      broll.add(BrollIdea(_num(e['start']), _num(e['end']), q));
    }

    final tags = (m['hashtags'] as List? ?? [])
        .map((e) => '$e'.replaceAll('#', '').trim())
        .where((e) => e.isNotEmpty)
        .toList();

    return Analysis(
      caps,
      '${m['title'] ?? ''}'.trim(),
      '${m['description'] ?? ''}'.trim(),
      tags,
      broll,
    );
  }

  /// فحص بصري: هل في الصورة امرأة أو فتاة؟ (يرمي خطأ لو ما قدر يفحص)
  static Future<bool> containsWoman(AppSettings s, String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final r = await http
        .post(
          _url(s),
          headers: _headers(s),
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'inline_data': {
                      'mime_type': 'image/jpeg',
                      'data': base64Encode(bytes),
                    }
                  },
                  {
                    'text':
                        'Does this image show a woman, a girl, or any female person (face or body)? Answer with exactly one word: YES or NO.'
                  },
                ]
              }
            ],
            'generationConfig': {'temperature': 0.0},
          }),
        )
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200) {
      throw Exception('Gemini ${r.statusCode}: ${_cut(r.body)}');
    }
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final text = (j['candidates'][0]['content']['parts'][0]['text'] as String)
        .toUpperCase();
    return text.contains('YES');
  }
}
