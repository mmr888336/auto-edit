import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// إعدادات التطبيق محفوظة محليًا على الجوال.
class AppSettings {
  String provider;
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
  bool enhanceAudio;
  bool visualEffects;
  String visualStyle; // clean | cinematic | vivid
  bool punchZoom;
  bool flashTransitions;
  bool progressBar;
  bool upscale2k;
  double targetMb;
  String brollProvider;
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
    this.enhanceAudio = true,
    this.visualEffects = true,
    this.visualStyle = 'cinematic',
    this.punchZoom = true,
    this.flashTransitions = true,
    this.progressBar = true,
    this.upscale2k = true,
    this.targetMb = 12,
    this.brollProvider = 'pexels',
    this.pexelsKey = '',
    this.pixabayKey = '',
  });

  String get activeKey => provider == 'gemini' ? geminiKey : mistralKey;

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      provider: prefs.getString('provider') ?? 'gemini',
      geminiKey: prefs.getString('geminiKey') ?? '',
      geminiModel: prefs.getString('geminiModel') ?? 'gemini-2.5-flash',
      mistralKey: prefs.getString('mistralKey') ?? '',
      mistralModel: prefs.getString('mistralModel') ?? 'mistral-small-latest',
      noiseDb: prefs.getDouble('noiseDb') ?? -30,
      minSilence: prefs.getDouble('minSilence') ?? 0.5,
      captions: prefs.getBool('captions') ?? true,
      hook: prefs.getBool('hook') ?? true,
      broll: prefs.getBool('broll') ?? true,
      sfx: prefs.getBool('sfx') ?? true,
      enhanceAudio: prefs.getBool('enhanceAudio') ?? true,
      visualEffects: prefs.getBool('visualEffects') ?? true,
      visualStyle: prefs.getString('visualStyle') ?? 'cinematic',
      punchZoom: prefs.getBool('punchZoom') ?? true,
      flashTransitions: prefs.getBool('flashTransitions') ?? true,
      progressBar: prefs.getBool('progressBar') ?? true,
      upscale2k: prefs.getBool('upscale2k') ?? true,
      targetMb: prefs.getDouble('targetMb') ?? 12,
      brollProvider: prefs.getString('brollProvider') ?? 'pexels',
      pexelsKey: prefs.getString('pexelsKey') ?? '',
      pixabayKey: prefs.getString('pixabayKey') ?? '',
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('provider', provider);
    await prefs.setString('geminiKey', geminiKey.trim());
    await prefs.setString('geminiModel', geminiModel.trim());
    await prefs.setString('mistralKey', mistralKey.trim());
    await prefs.setString('mistralModel', mistralModel.trim());
    await prefs.setDouble('noiseDb', noiseDb);
    await prefs.setDouble('minSilence', minSilence);
    await prefs.setBool('captions', captions);
    await prefs.setBool('hook', hook);
    await prefs.setBool('broll', broll);
    await prefs.setBool('sfx', sfx);
    await prefs.setBool('enhanceAudio', enhanceAudio);
    await prefs.setBool('visualEffects', visualEffects);
    await prefs.setString('visualStyle', visualStyle);
    await prefs.setBool('punchZoom', punchZoom);
    await prefs.setBool('flashTransitions', flashTransitions);
    await prefs.setBool('progressBar', progressBar);
    await prefs.setBool('upscale2k', upscale2k);
    await prefs.setDouble('targetMb', targetMb);
    await prefs.setString('brollProvider', brollProvider);
    await prefs.setString('pexelsKey', pexelsKey.trim());
    await prefs.setString('pixabayKey', pixabayKey.trim());
  }
}

class AiService {
  static String _cut(String value) => value.length > 300 ? value.substring(0, 300) : value;

  static Future<String> generate(AppSettings settings, String prompt) async {
    if (settings.activeKey.trim().isEmpty) {
      throw Exception('ما في مفتاح API. ضعه في الإعدادات.');
    }
    if (settings.provider == 'gemini') {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/${settings.geminiModel}:generateContent'),
        headers: {'Content-Type': 'application/json', 'x-goog-api-key': settings.geminiKey.trim()},
        body: jsonEncode({'contents': [{'parts': [{'text': prompt}]}]}),
      );
      if (response.statusCode != 200) throw Exception('Gemini ${response.statusCode}: ${_cut(response.body)}');
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final candidates = json['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) throw Exception('Gemini لم يرجع نصًا.');
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) throw Exception('استجابة Gemini لا تحتوي على نص.');
      return parts.first['text'] as String;
    }

    final response = await http.post(
      Uri.parse('https://api.mistral.ai/v1/chat/completions'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${settings.mistralKey.trim()}'},
      body: jsonEncode({'model': settings.mistralModel, 'messages': [{'role': 'user', 'content': prompt}]}),
    );
    if (response.statusCode != 200) throw Exception('Mistral ${response.statusCode}: ${_cut(response.body)}');
    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) throw Exception('Mistral لم يرجع نصًا.');
    return choices.first['message']['content'] as String;
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings? settings;
  final geminiKey = TextEditingController();
  final geminiModel = TextEditingController();
  final mistralKey = TextEditingController();
  final mistralModel = TextEditingController();
  final pexelsKey = TextEditingController();
  final pixabayKey = TextEditingController();
  String testResult = '';
  bool testing = false;

  @override
  void initState() {
    super.initState();
    AppSettings.load().then((value) {
      if (!mounted) return;
      setState(() {
        settings = value;
        geminiKey.text = value.geminiKey;
        geminiModel.text = value.geminiModel;
        mistralKey.text = value.mistralKey;
        mistralModel.text = value.mistralModel;
        pexelsKey.text = value.pexelsKey;
        pixabayKey.text = value.pixabayKey;
      });
    });
  }

  @override
  void dispose() {
    geminiKey.dispose();
    geminiModel.dispose();
    mistralKey.dispose();
    mistralModel.dispose();
    pexelsKey.dispose();
    pixabayKey.dispose();
    super.dispose();
  }

  void _apply() {
    final current = settings!;
    current.geminiKey = geminiKey.text;
    current.geminiModel = geminiModel.text;
    current.mistralKey = mistralKey.text;
    current.mistralModel = mistralModel.text;
    current.pexelsKey = pexelsKey.text;
    current.pixabayKey = pixabayKey.text;
  }

  Future<void> _test() async {
    _apply();
    setState(() {
      testing = true;
      testResult = '';
    });
    try {
      final text = await AiService.generate(settings!, 'اكتب كلمة واحدة فقط: مرحبا');
      if (mounted) setState(() => testResult = 'شغال ✅ الرد: ${text.trim()}');
    } catch (e) {
      if (mounted) setState(() => testResult = 'فشل ❌ $e');
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  Widget _field(TextEditingController controller, String label, {bool secret = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: TextField(
        controller: controller,
        obscureText: secret,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = settings;
    if (current == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('الذكاء الاصطناعي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 6),
          const Text('الكابشن والعنوان واقتراحات B-roll وفحص الصور تستخدم Gemini دائمًا (لأنه يسمع الصوت ويرى الصور).', style: TextStyle(fontSize: 12, color: Colors.white70)),
          RadioListTile<String>(title: const Text('Gemini'), value: 'gemini', groupValue: current.provider, onChanged: (value) => setState(() => current.provider = value!)),
          RadioListTile<String>(title: const Text('Mistral'), value: 'mistral', groupValue: current.provider, onChanged: (value) => setState(() => current.provider = value!)),
          _field(geminiKey, 'مفتاح Gemini', secret: true),
          _field(geminiModel, 'اسم نموذج Gemini'),
          _field(mistralKey, 'مفتاح Mistral', secret: true),
          _field(mistralModel, 'اسم نموذج Mistral'),
          FilledButton.tonal(onPressed: testing ? null : _test, child: Text(testing ? 'جاري الاختبار...' : 'اختبر المفتاح')),
          if (testResult.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: SelectableText(testResult)),
          const Divider(height: 32),
          const Text('ميزات المونتاج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          SwitchListTile(title: const Text('تحسين الصوت'), subtitle: const Text('تقليل الضوضاء وموازنة مستوى الصوت وضغطه'), value: current.enhanceAudio, onChanged: (value) => setState(() => current.enhanceAudio = value)),
          SwitchListTile(title: const Text('تحسينات بصرية'), subtitle: const Text('ألوان وتأثيرات بصرية (قد تبطّئ التصدير)'), value: current.visualEffects, onChanged: (value) => setState(() => current.visualEffects = value)),
          if (current.visualEffects) ...[
            const Padding(padding: EdgeInsets.only(top: 6), child: Text('نمط الألوان')),
            RadioListTile<String>(title: const Text('نظيف (تباين وحدة خفيفة)'), value: 'clean', groupValue: current.visualStyle, onChanged: (value) => setState(() => current.visualStyle = value!)),
            RadioListTile<String>(title: const Text('سينمائي (ألوان دافئة وباردة + تظليل)'), value: 'cinematic', groupValue: current.visualStyle, onChanged: (value) => setState(() => current.visualStyle = value!)),
            RadioListTile<String>(title: const Text('حيوي (ألوان أقوى)'), value: 'vivid', groupValue: current.visualStyle, onChanged: (value) => setState(() => current.visualStyle = value!)),
            SwitchListTile(title: const Text('تقريب سريع عند القطع (Punch-in)'), subtitle: const Text('يكبّر اللقطة بالتناوب ليبدو القطع مقصودًا'), value: current.punchZoom, onChanged: (value) => setState(() => current.punchZoom = value)),
            SwitchListTile(title: const Text('وميض انتقالي عند B-roll'), value: current.flashTransitions, onChanged: (value) => setState(() => current.flashTransitions = value)),
            SwitchListTile(title: const Text('شريط تقدم أسفل الفيديو'), subtitle: const Text('يشجع المشاهد على إكمال الفيديو'), value: current.progressBar, onChanged: (value) => setState(() => current.progressBar = value)),
          ],
          SwitchListTile(title: const Text('إضافة كابشن'), subtitle: const Text('عطّله إذا كان الفيديو يحتوي على كابشن جاهز'), value: current.captions, onChanged: (value) => setState(() => current.captions = value)),
          SwitchListTile(title: const Text('عنوان جذاب في أول 3 ثوانٍ'), value: current.hook, onChanged: (value) => setState(() => current.hook = value)),
          SwitchListTile(title: const Text('B-roll (مقاطع توضيحية)'), subtitle: const Text('يحتاج مفتاح Pexels أو Pixabay واتصالًا بالإنترنت'), value: current.broll, onChanged: (value) => setState(() => current.broll = value)),
          SwitchListTile(title: const Text('مؤثرات صوتية انتقالية'), value: current.sfx, onChanged: (value) => setState(() => current.sfx = value)),
          const SizedBox(height: 8),
          const Text('مصدر مقاطع B-roll'),
          RadioListTile<String>(title: const Text('Pexels'), value: 'pexels', groupValue: current.brollProvider, onChanged: (value) => setState(() => current.brollProvider = value!)),
          RadioListTile<String>(title: const Text('Pixabay'), value: 'pixabay', groupValue: current.brollProvider, onChanged: (value) => setState(() => current.brollProvider = value!)),
          _field(pexelsKey, 'مفتاح Pexels', secret: true),
          _field(pixabayKey, 'مفتاح Pixabay', secret: true),
          const Divider(height: 32),
          const Text('التصدير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          SwitchListTile(title: const Text('دقة 2K'), subtitle: const Text('تستهلك وقتًا وذاكرة أكبر على الجوال'), value: current.upscale2k, onChanged: (value) => setState(() => current.upscale2k = value)),
          Text('الحجم المستهدف: ${current.targetMb.toStringAsFixed(0)} ميجا لكل 30 ثانية'),
          Slider(min: 6, max: 20, divisions: 14, value: current.targetMb, onChanged: (value) => setState(() => current.targetMb = value)),
          const Divider(height: 32),
          Text('حساسية السكتة: ${current.noiseDb.toStringAsFixed(0)} dB'),
          const Text('(القيمة الأقل تقص الأصوات الخافتة أكثر)', style: TextStyle(fontSize: 12, color: Colors.white70)),
          Slider(min: -50, max: -15, divisions: 35, value: current.noiseDb, onChanged: (value) => setState(() => current.noiseDb = value)),
          Text('أقل مدة سكتة تُقص: ${current.minSilence.toStringAsFixed(1)} ثانية'),
          Slider(min: 0.3, max: 1.5, divisions: 12, value: current.minSilence, onChanged: (value) => setState(() => current.minSilence = value)),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () async {
              _apply();
              await current.save();
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('حفظ الإعدادات'),
          ),
        ],
      ),
    );
  }
}
