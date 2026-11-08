import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class KycRealnamePage extends StatefulWidget {
  const KycRealnamePage({super.key});

  @override
  State<KycRealnamePage> createState() => _KycRealnamePageState();
}

class _KycRealnamePageState extends State<KycRealnamePage> {
  final _name = TextEditingController();
  final _idCard = TextEditingController();
  final _city = TextEditingController(text: '深圳');
  final _company = TextEditingController();
  String _occupation = '企业职员';
  int _incomeCents = 1000000;
  bool _submitting = false;

  static const _occupations = ['企业职员', '个体经营', '公务员/事业单位', '自由职业', '其他'];
  static const _incomes = [
    [500000, '5 千以下'],
    [800000, '5 千 - 1 万'],
    [1500000, '1 万 - 2 万'],
    [3000000, '2 万以上'],
  ];

  @override
  void dispose() {
    _name.dispose();
    _idCard.dispose();
    _city.dispose();
    _company.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_name.text.trim().length < 2) return showToast(context, '请输入真实姓名', error: true);
    if (!RegExp(r'^\d{17}[\dXx]$').hasMatch(_idCard.text.trim())) return showToast(context, '请输入正确的 18 位身份证号', error: true);
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/api/kyc/realname', {
        'realName': _name.text.trim(),
        'idCard': _idCard.text.trim().toUpperCase(),
        'city': _city.text.trim(),
        'occupation': _occupation,
        'company': _company.text.trim(),
        'monthlyIncomeCents': _incomeCents,
      });
      await session.refreshProfile(silent: true);
      if (!mounted) return;
      showToast(context, '实名认证通过');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '实名认证'),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                children: [
                  UCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('请填写本人真实信息', style: UText.h3),
                        const SizedBox(height: 4),
                        Text('信息仅用于身份核验，全程加密存储', style: UText.tiny),
                        const SizedBox(height: 20),
                        UField(label: '真实姓名', hint: '与身份证一致', controller: _name, maxLength: 20),
                        const SizedBox(height: 16),
                        UField(
                          label: '身份证号',
                          hint: '18 位身份证号码',
                          controller: _idCard,
                          maxLength: 18,
                          keyboardType: TextInputType.text,
                          formatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9Xx]'))],
                        ),
                        const SizedBox(height: 16),
                        UField(label: '常住城市', hint: '如：深圳', controller: _city),
                        const SizedBox(height: 16),
                        UField(label: '工作单位（选填）', hint: '请输入单位名称', controller: _company),
                        const SizedBox(height: 18),
                        Text('职业类型', style: UText.sub.copyWith(fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _occupations.map((o) {
                            final active = _occupation == o;
                            return GestureDetector(
                              onTap: () => setState(() => _occupation = o),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active ? UColors.navy : UColors.bg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(o, style: TextStyle(fontSize: 12.5, color: active ? Colors.white : UColors.textSub)),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),
                        Text('月收入', style: UText.sub.copyWith(fontSize: 12)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _incomes.map((i) {
                            final active = _incomeCents == i[0];
                            return GestureDetector(
                              onTap: () => setState(() => _incomeCents = i[0] as int),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: active ? UColors.navy : UColors.bg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(i[1] as String, style: TextStyle(fontSize: 12.5, color: active ? Colors.white : UColors.textSub)),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_outline, size: 13, color: UColors.textLight),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '根据监管要求，本服务仅向 22-55 周岁、非在校学生的完全民事行为能力人提供。您的身份信息将用于实名核验与反欺诈，不会用于其他用途。',
                          style: UText.tiny.copyWith(height: 1.7),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: Colors.white,
            child: SafeArea(
              top: false,
              child: UButton(text: '提交认证', onPressed: _submit, loading: _submitting),
            ),
          ),
        ],
      ),
    );
  }
}
