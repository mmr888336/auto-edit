import 'dart:async';
import 'package:flutter/material.dart';

/// شاشة الإعلان (60 ثانية). حالياً مؤقتة، لاحقاً نربطها بإعلانات حقيقية (AdMob).
class AdPage extends StatefulWidget {
  const AdPage({super.key});
  @override
  State<AdPage> createState() => _AdPageState();
}

class _AdPageState extends State<AdPage> {
  static const int total = 60;
  int left = total;
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => left--);
      if (left <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = left <= 0;
    return PopScope(
      canPop: done,
      child: Scaffold(
        appBar: AppBar(title: const Text('إعلان'), automaticallyImplyLeading: false),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.ondemand_video, size: 80),
              const SizedBox(height: 16),
              const Text('مساحة الإعلان',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
              const SizedBox(height: 24),
              LinearProgressIndicator(value: (total - left) / total),
              const SizedBox(height: 12),
              Text(done ? 'خلص الإعلان ✅' : 'باقي $left ثانية',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: done ? () => Navigator.pop(context, true) : null,
                child: const Text('استلم 60 ثانية'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}