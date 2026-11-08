import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class KycFacePage extends StatefulWidget {
  const KycFacePage({super.key});

  @override
  State<KycFacePage> createState() => _KycFacePageState();
}

class _KycFacePageState extends State<KycFacePage> {
  bool _scanning = false;
  int _progress = 0;
  Timer? _timer;
  bool _done = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _progress = 0;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (t) async {
      if (!mounted) return t.cancel();
      setState(() => _progress += 4);
      if (_progress >= 100) {
        t.cancel();
        try {
          await ApiClient.instance.post('/api/kyc/face', {'score': 95, 'liveness': true});
          await session.refreshProfile(silent: true);
          if (!mounted) return;
          setState(() {
            _scanning = false;
            _done = true;
          });
          showToast(context, '人脸识别通过');
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) Navigator.pop(context);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _scanning = false;
            _progress = 0;
          });
          showToast(context, e.toString(), error: true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.navy,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('人脸识别', style: TextStyle(color: Colors.white, fontSize: 17)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 18), onPressed: () => Navigator.pop(context)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(
              _scanning ? '请正对屏幕，保持面部在框内' : _done ? '识别成功' : '请将脸部置于取景框内',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              '活体检测用于确认本人操作，不会保存影像',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
            ),
            const Spacer(),
            // 取景框
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 240,
                  height: 240,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.04),
                    border: Border.all(color: UColors.gold.withValues(alpha: _scanning ? 0.9 : 0.4), width: 2),
                  ),
                ),
                Icon(Icons.face_retouching_natural, size: 96, color: Colors.white.withValues(alpha: 0.28)),
                if (_scanning)
                  SizedBox(
                    width: 236,
                    height: 236,
                    child: CircularProgressIndicator(
                      value: _progress / 100,
                      strokeWidth: 3,
                      valueColor: const AlwaysStoppedAnimation(UColors.gold),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                if (_done)
                  Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.35)),
                    child: const Icon(Icons.check_circle_rounded, size: 64, color: UColors.success),
                  ),
              ],
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _tip(Icons.light_mode_outlined, '光线充足'),
                      const SizedBox(width: 20),
                      _tip(Icons.visibility_outlined, '正视镜头'),
                      const SizedBox(width: 20),
                      _tip(Icons.masks_outlined, '无需遮挡'),
                    ],
                  ),
                  const SizedBox(height: 26),
                  UButton(
                    text: _scanning ? '识别中 ${_progress}%' : _done ? '识别成功' : '开始识别',
                    onPressed: _scanning || _done ? null : _start,
                    loading: _scanning,
                  ),
                  const SizedBox(height: 16),
                  Text('该功能由第三方活体检测服务提供（演示环境为模拟通道）', style: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 10.5), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tip(IconData icon, String text) => Column(
        children: [
          Icon(icon, size: 18, color: UColors.goldLight.withValues(alpha: 0.7)),
          const SizedBox(height: 5),
          Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11)),
        ],
      );
}
