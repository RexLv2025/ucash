import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'agreements_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController(text: '13800138000');
  final _code = TextEditingController();
  bool _agreed = false;
  bool _loading = false;
  bool _sending = false;
  int _countdown = 0;
  Timer? _timer;
  String? _devCode;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_countdown > 0 || _sending) return;
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text)) {
      showToast(context, '请输入正确的手机号', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      final data = await ApiClient.instance.post('/api/auth/sms-code', {'phone': _phone.text});
      setState(() {
        _devCode = data?['devCode'] as String?;
        _countdown = 60;
      });
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) return t.cancel();
        setState(() => _countdown--);
        if (_countdown <= 0) t.cancel();
      });
      showToast(context, '验证码已发送');
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _login() async {
    if (!_agreed) {
      showToast(context, '请先阅读并同意相关协议', error: true);
      return;
    }
    if (!RegExp(r'^1[3-9]\d{9}$').hasMatch(_phone.text)) {
      showToast(context, '请输入正确的手机号', error: true);
      return;
    }
    if (_code.text.length != 6) {
      showToast(context, '请输入 6 位验证码', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await session.login(_phone.text, _code.text);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.navy,
      resizeToAvoidBottomInset: true,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 品牌区
            Container(
              height: 300,
              width: double.infinity,
              decoration: const BoxDecoration(gradient: UColors.navyGradient),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 40, 28, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: UColors.goldGradient,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Center(
                          child: Text('U', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'UCash',
                        style: TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '额度灵活 · 随借随还 · 最快 1 分钟到账',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          _badge(Icons.verified_user_outlined, '持牌合规'),
                          const SizedBox(width: 10),
                          _badge(Icons.lock_outline, '信息加密'),
                          const SizedBox(width: 10),
                          _badge(Icons.bolt_outlined, '极速放款'),
                        ],
                      ),
                      const SizedBox(height: 36),
                    ],
                  ),
                ),
              ),
            ),
            // 表单卡片
            Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: UColors.navy.withValues(alpha: 0.1), blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('手机号登录', style: UText.h2),
                    const SizedBox(height: 4),
                    Text('未注册的手机号将自动创建账户', style: UText.tiny),
                    const SizedBox(height: 22),
                    UField(
                      label: '手机号',
                      hint: '请输入手机号',
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      maxLength: 11,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                    ),
                    const SizedBox(height: 16),
                    UField(
                      label: '验证码',
                      hint: '请输入 6 位验证码',
                      controller: _code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      formatters: [FilteringTextInputFormatter.digitsOnly],
                      suffix: TextButton(
                        onPressed: _countdown > 0 ? null : _sendCode,
                        child: Text(
                          _countdown > 0 ? '${_countdown}s 后重发' : '获取验证码',
                          style: TextStyle(color: _countdown > 0 ? UColors.textLight : UColors.navy, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_devCode != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          const Icon(Icons.info_outline, size: 14, color: UColors.goldDark),
                          const SizedBox(width: 6),
                          Text('演示环境验证码：$_devCode（或输入 123456）', style: UText.tiny.copyWith(color: UColors.goldDark)),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 22),
                    UButton(text: '登录 / 注册', onPressed: _login, loading: _loading),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _agreed,
                            onChanged: (v) => setState(() => _agreed = v ?? false),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            side: const BorderSide(color: UColors.line, width: 1.5),
                            activeColor: UColors.navy,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _agreed = !_agreed),
                            child: Text.rich(
                              TextSpan(
                                style: UText.tiny,
                                children: [
                                  const TextSpan(text: '我已阅读并同意 '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'privacy'))),
                                      child: Text('《隐私政策》', style: UText.tiny.copyWith(color: UColors.navy)),
                                    ),
                                  ),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'personalInfo'))),
                                      child: Text('《个人信息授权书》', style: UText.tiny.copyWith(color: UColors.navy)),
                                    ),
                                  ),
                                  const TextSpan(text: '，并授权查询相关信息用于风控评估。'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: Column(
                children: [
                  Text('理性借贷，量力而行 · 综合年化利率 9%-24%', style: UText.tiny.copyWith(color: Colors.white.withValues(alpha: 0.45))),
                  const SizedBox(height: 6),
                  Text('客服热线 400-000-8888（09:00-21:00）', style: UText.tiny.copyWith(color: Colors.white.withValues(alpha: 0.35))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: UColors.goldLight),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85))),
      ]),
    );
  }
}
