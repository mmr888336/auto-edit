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
  double noiseDb;
  double minSilence;
  bool captions;
  bool hook;
  bool broll;
  bool sfx;
  bool upscale2k;
  double targetMb; // الحجم المستهدف لكل 30 ثانية
  String brollProvider; // pexels | pixabay
  String pexelsKey;
  String pixabayKey;

  AppSettings({
    this.provider = 'gemini',
    this.geminiKey = '',
    this.geminiModel = 'gemini-2.5-flash',
    this.mistralKey = '',
    this.mistralModel = 'mistral-small-latest',
    this.noiseDb = -30,
    this.minSilence = 0.5,
    this.captions = true,
    this.hook = true,
    this.broll = true,
    this.sfx = true,
    this.upscale2k = true,
    this.targetMb = 12,
    this.brollProvider = 'pexels',
    this.pexelsKey = '',
    this.pixabayKey = '',
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
      captions: p.getBool('captions') ?? true,
      hook: p.getBool('hook') ?? true,
      broll: p.getBool('broll') ?? true,
      sfx: p.getBool('sfx') ?? true,
      upscale2k: p.getBool('upscale2k') ?? true,
      targetMb: p.getDouble('targetMb') ?? 12,
      brollProvider: p.getString('brollProvider') ?? 'pexels',
      pexelsKey: p.getString('pexelsKey') ?? '',
      pixabayKey: p.getString('pixabayKey') ?? '',
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
    await p.setBool('captions', captions);
    await p.setBool('hook', hook);
    await p.setBool('broll', broll);
    await p.setBool('sfx', sfx);
    await p.setBool('upscale2k', upscale2k);
    await p.setDouble('targetMb', targetMb);
    await p.setString('brollProvider', brollProvider);
    await p.setString('pexelsKey', pexelsKey.trim());
    await p.setString('pixabayKey', pixabayKey.trim());
  }
}

/// طبقة موحدة للنصوص: تبدّل بين Gemini وMistral (تُستخدم لاختبار المفتاح)
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
  final pxKey = TextEditingController();
  final pbKey = TextEditingController();
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
        pxKey.text = v.pexelsKey;
        pbKey.text = v.pixabayKey;
      });
    });
  }

  void _apply() {
    s!.geminiKey = gKey.text;
    s!.geminiModel = gModel.text;
    s!.mistralKey = mKey.text;
    s!.mistralModel = mModel.text;
    s!.pexelsKey = pxKey.text;
    s!.pixabayKey = pbKey.text;
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

  Widget _field(TextEditingController c, String label, {bool secret = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        obscureText: secret,
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      ),
    );
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
          const Text('الذكاء الاصطناعي',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Text(
              'الكابشن والعنوان والـ B-roll يستخدموا Gemini دايماً (لأنه يسمع الصوت).',
              style: TextStyle(fontSize: 12)),
          RadioListTile<String>(
            title: const Text('Gemini'),
            value: 'gemini',
            groupValue: s!.provider,
            onChanged: (v) => setState(() => s!.provider = v!),
          ),
          RadioListTile<String>(
            title: const Text('Mistral (للاختبار فقط حالياً)'),
            value: 'mistral',
            groupValue: s!.provider,
            onChanged: (v) => setState(() => s!.provider = v!),
          ),
          _field(gKey, 'مفتاح Gemini', secret: true),
          _field(gModel, 'اسم نموذج Gemini'),
          _field(mKey, 'مفتاح Mistral', secret: true),
          _field(mModel, 'اسم نموذج Mistral'),
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
          const Text('ميزات المونتاج',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text('كابشن جديد'),
            subtitle: const Text('عطّله لو الفيديو فيه كابشن محروق أصلاً'),
            value: s!.captions,
            onChanged: (v) => setState(() => s!.captions = v),
          ),
          SwitchListTile(
            title: const Text('عنوان جذاب في أول 3 ثواني'),
            value: s!.hook,
            onChanged: (v) => setState(() => s!.hook = v),
          ),
          SwitchListTile(
            title: const Text('B-roll (مقاطع توضيحية)'),
            subtitle: const Text('يحتاج مفتاح Pexels أو Pixabay ونت'),
            value: s!.broll,
            onChanged: (v) => setState(() => s!.broll = v),
          ),
          SwitchListTile(
            title: const Text('مؤثرات صوتية'),
            value: s!.sfx,
            onChanged: (v) => setState(() => s!.sfx = v),
          ),
          const SizedBox(height: 8),
          const Text('مصدر الـ B-roll'),
          RadioListTile<String>(
            title: const Text('Pexels'),
            value: 'pexels',
            groupValue: s!.brollProvider,
            onChanged: (v) => setState(() => s!.brollProvider = v!),
          ),
          RadioListTile<String>(
            title: const Text('Pixabay'),
            value: 'pixabay',
            groupValue: s!.brollProvider,
            onChanged: (v) => setState(() => s!.brollProvider = v!),
          ),
          _field(pxKey, 'مفتاح Pexels', secret: true),
          _field(pbKey, 'مفتاح Pixabay', secret: true),
          const Divider(height: 32),
          const Text('التصدير',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          SwitchListTile(
            title: const Text('دقة 2K'),
            subtitle: const Text('بطيء على الجوالات الضعيفة'),
            value: s!.upscale2k,
            onChanged: (v) => setState(() => s!.upscale2k = v),
          ),
          Text(
              'الحجم المستهدف: ${s!.targetMb.toStringAsFixed(0)} ميجا لكل 30 ثانية'),
          Slider(
            min: 6,
            max: 20,
            divisions: 14,
            value: s!.targetMb,
            onChanged: (v) => setState(() => s!.targetMb = v),
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