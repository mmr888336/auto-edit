import 'dart:convert';
import 'settings.dart';

class Caption {
  final double start;
  final double end;
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
  final String title;
  final String description;
  final List<String> hashtags;
  final List<Caption> captions;
  final List<BrollIdea> broll;

  Analysis({
    required this.title,
    required this.description,
    required this.hashtags,
    required this.captions,
    required this.broll,
  });
}

class Analyzer {
  static Future<Analysis> run(AppSettings settings, String wavPath, double cutSec) async {
    final prompt = '''
    أنت مساعد مونتاج ذكي. قم بتحليل ملف صوتي لمدته $cutSec ثانية.
    قم بإرجاع النتيجة حصراً بصيغة JSON مطابقة تماماً للشكل التالي بدون أي إضافات نصية أخرى:
    {
      "title": "عنوان جذاب للفيديو",
      "description": "وصف جذاب للفيديو",
      "hashtags": ["tag1", "tag2"],
      "captions": [
        {"start": 0.0, "end": 3.0, "text": "النص الأول"}
      ],
      "broll": [
        {"start": 4.0, "end": 7.0, "query": "nature landscape"}
      ]
    }
    ''';

    try {
      final responseText = await AiService.generate(settings, prompt);
      final cleaned = responseText.replaceAll(RegExp(r'```json|```'), '').trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;

      final captions = (data['captions'] as List? ?? []).map((c) => Caption(
        (c['start'] as num).toDouble(),
        (c['end'] as num).toDouble(),
        c['text'] as String,
      )).toList();

      final broll = (data['broll'] as List? ?? []).map((b) => BrollIdea(
        (b['start'] as num).toDouble(),
        (b['end'] as num).toDouble(),
        b['query'] as String,
      )).toList();

      final hashtags = (data['hashtags'] as List? ?? []).map((h) => h.toString()).toList();

      return Analysis(
        title: data['title'] as String? ?? 'فيديو رائع من Wad Alreda Studio',
        description: data['description'] as String? ?? '',
        hashtags: hashtags.isEmpty ? ['Shorts', 'Reels', 'WadAlredaStudio'] : hashtags,
        captions: captions,
        broll: broll,
      );
    } catch (_) {
      return Analysis(
        title: 'فيديو احترافي',
        description: 'تم المونتاج تلقائياً بواسطة Wad Alreda Studio.',
        hashtags: ['WadAlredaStudio', 'Shorts'],
        captions: [
          Caption(0.0, cutSec > 3 ? 3.0 : cutSec, 'مرحباً بكم في هذا الفيديو')
        ],
        broll: [],
      );
    }
  }
}
