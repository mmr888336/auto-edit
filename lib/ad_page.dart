import 'package:flutter/material.dart';
import 'ads_service.dart';

/// شاشة الإعلان: تعرض إعلان Unity المكافأة، ولو اكتمل تدي المستخدم رصيده
class AdPage extends StatefulWidget {
  const AdPage({super.key});
  @override
  State<AdPage> createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> {
  bool loading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      loading = true;
      error = '';
    });
    final ok = await AdsService.showRewarded();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        loading = false;
        error = AdsService.lastError.isEmpty
            ? 'ما اكتمل الإعلان. شوفه للآخر عشان تاخد الرصيد.'
            : 'ما قدرنا نعرض الإعلان: ${AdsService.lastError}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعلان')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.ondemand_video, size: 80),
            const SizedBox(height: 24),
            if (loading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 16),
              const Text('جاري تحميل الإعلان...',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
            ] else ...[
              SelectableText(error,
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _run, child: const Text('حاول تاني')),
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('رجوع')),
            ],
          ],
        ),
      ),
    );
  }
}