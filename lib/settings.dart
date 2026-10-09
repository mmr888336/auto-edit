import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات التطبيق (تتخزن في الجوال فقط)
class AppSettings {
  String provider; // gemini | mistral
  String geminiKey;
  String geminiModel;
  String mistralKey;
  String mistralModel;
  double noiseDb; // حساسية السكتة
  double minSilence; // أقل مدة سكتة تتقص (ثواني)

  AppSettings({
    this.provider = 'gemini',
    this.geminiKey = '',
    this.geminiModel = 'gemini-2.5-flash',
    this.mistralKey = '',
    this.mistralModel = 'mistral-small-latest',
    this.noiseDb = -30,
    this.minSilence = 0.5,
  });

  String get activeKey => provider == 'gemini' ? geminiKey : mistralKey;

  static Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      provider: p.getString('provider') ?? 'gemini',
      geminiKey: p.getString('geminiKey') ?? '',
      geminiModel: p.getString('geminiModel') ?? 'gemini-2.5-flash',
      mistralKey: p.getString('mistralKey') ?? '',
      mistralModel: p.getString('mistralModel') ?? 'mistral-small-latest',
      noiseDb: p.getDouble('noiseDb') ?? -30,
      minSilence: p.getDouble('minSilence') ?? 0.5,
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('provider', provider);
    await p.setString('geminiKey', geminiKey.trim());
    await p.setString('geminiModel', geminiModel.trim());
    await p.setString('mistralKey', mistralKey.trim());
    await p.setString('mistralModel', mistralModel.trim());
    await p.setDouble('noiseDb', noiseDb);
    await p.setDouble('minSilence', minSilence);
  }
}

/// طبقة موحدة للذكاء الاصطناعي: تبدّل بين Gemini وMistral من الإعدادات
class AiService {
  static String _cut(String s) => s.length > 300 ? s.substring(0, 300) : s;

  static Future<String> generate(AppSettings s, String prompt) async {
    if (s.activeKey.trim().isEmpty) {
      throw Exception('ما في مفتاح API. ضعه في الإعدادات.');
    }
    if (s.provider == 'gemini') {
      final r = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/${s.geminiModel}:generateContent'),
        headers: {
          'Content-Type': 'application/json',
          'x-goog-api-key': s.geminiKey.trim(),
        },
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ]
        }),
      );
      if (r.statusCode != 200) {
        throw Exception('Gemini ${r.statusCode}: ${_cut(r.body)}');
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j['candidates'][0]['content']['parts'][0]['text'] as String;
    } else {
      final r = await http.post(
        Uri.parse('https://api.mistral.ai/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${s.mistralKey.trim()}',
        },
        body: jsonEncode({
          'model': s.mistralModel,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      );
      if (r.statusCode != 200) {
        throw Exception('Mistral ${r.statusCode}: ${_cut(r.body)}');
      }
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j['choices'][0]['message']['content'] as String;
    }
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings? s;
  final gKey = TextEditingController();
  final gModel = TextEditingController();
  final mKey = TextEditingController();
  final mModel = TextEditingController();
  String testResult = '';
  bool testing = false;

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((v) {
      setState(() {
        s = v;
        gKey.text = v.geminiKey;
        gModel.text = v.geminiModel;
        mKey.text = v.mistralKey;
        mModel.text = v.mistralModel;
      });
    });
  }

  void _apply() {
    s!.geminiKey = gKey.text;
    s!.geminiModel = gModel.text;
    s!.mistralKey = mKey.text;
    s!.mistralModel = mModel.text;
  }

  Future<void> _test() async {
    _apply();
    setState(() {
      testing = true;
      testResult = '';
    });
    try {
      final t = await AiService.generate(s!, 'اكتب كلمة واحدة فقط: مرحبا');
      setState(() => testResult = 'شغال ✅  الرد: ${t.trim()}');
    } catch (e) {
      setState(() => testResult = 'فشل ❌ $e');
    } finally {
      setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (s == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('مزود الذكاء الاصطناعي',
              style: TextStyle(fontWeight: FontWeight.bold)),
          RadioListTile<String>(
            title: const Text('Gemini'),
            value: 'gemini',
            groupValue: s!.provider,
            onChanged: (v) => setState(() => s!.provider = v!),
          ),
          RadioListTile<String>(
            title: const Text('Mistral'),
            value: 'mistral',
            groupValue: s!.provider,
            onChanged: (v) => setState(() => s!.provider = v!),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: gKey,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'مفتاح Gemini', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: gModel,
            decoration: const InputDecoration(
                labelText: 'اسم نموذج Gemini', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: mKey,
            obscureText: true,
            decoration: const InputDecoration(
                labelText: 'مفتاح Mistral', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: mModel,
            decoration: const InputDecoration(
                labelText: 'اسم نموذج Mistral', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: testing ? null : _test,
            child: Text(testing ? 'جاري الاختبار...' : 'اختبر المفتاح'),
          ),
          if (testResult.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SelectableText(testResult),
            ),
          const Divider(height: 32),
          Text('حساسية السكتة: ${s!.noiseDb.toStringAsFixed(0)} dB'),
          const Text('(رقم أقل = يقص الأصوات الخافتة كمان، أعلى = يقص أقل)',
              style: TextStyle(fontSize: 12)),
          Slider(
            min: -50,
            max: -15,
            divisions: 35,
            value: s!.noiseDb,
            onChanged: (v) => setState(() => s!.noiseDb = v),
          ),
          Text('أقل مدة سكتة تتقص: ${s!.minSilence.toStringAsFixed(1)} ثانية'),
          Slider(
            min: 0.3,
            max: 1.5,
            divisions: 12,
            value: s!.minSilence,
            onChanged: (v) => setState(() => s!.minSilence = v),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              _apply();
              await s!.save();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}