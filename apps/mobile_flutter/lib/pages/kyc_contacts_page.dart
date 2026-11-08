import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class KycContactsPage extends StatefulWidget {
  const KycContactsPage({super.key});

  @override
  State<KycContactsPage> createState() => _KycContactsPageState();
}

class _KycContactsPageState extends State<KycContactsPage> {
  final _n1 = TextEditingController();
  final _p1 = TextEditingController();
  final _n2 = TextEditingController();
  final _p2 = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _n1.dispose();
    _p1.dispose();
    _n2.dispose();
    _p2.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phoneRe = RegExp(r'^1[3-9]\d{9}$');
    if (_n1.text.trim().isEmpty || !phoneRe.hasMatch(_p1.text)) return showToast(context, '请填写完整的联系人一信息', error: true);
    if (_n2.text.trim().isEmpty || !phoneRe.hasMatch(_p2.text)) return showToast(context, '请填写完整的联系人二信息', error: true);
    if (_p1.text == _p2.text) return showToast(context, '两位联系人不能重复', error: true);
    setState(() => _submitting = true);
    try {
      await ApiClient.instance.post('/api/kyc/contacts', {
        'contact1Name': _n1.text.trim(),
        'contact1Phone': _p1.text,
        'contact2Name': _n2.text.trim(),
        'contact2Phone': _p2.text,
      });
      await session.refreshProfile(silent: true);
      if (!mounted) return;
      showToast(context, '联系人授权成功');
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
      appBar: UNavBar(title: '紧急联系人'),
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
                        const Text('联系人一', style: UText.h3),
                        const SizedBox(height: 14),
                        UField(label: '姓名', hint: '请输入真实姓名', controller: _n1, maxLength: 20),
                        const SizedBox(height: 14),
                        UField(
                          label: '手机号',
                          hint: '请输入手机号',
                          controller: _p1,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  UCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('联系人二', style: UText.h3),
                        const SizedBox(height: 14),
                        UField(label: '姓名', hint: '请输入真实姓名', controller: _n2, maxLength: 20),
                        const SizedBox(height: 14),
                        UField(
                          label: '手机号',
                          hint: '请输入手机号',
                          controller: _p2,
                          keyboardType: TextInputType.phone,
                          maxLength: 11,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 13, color: UColors.textLight),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '紧急联系人信息仅用于逾期后的联系与核实，不会用于营销。请确保已取得联系人同意。',
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
              child: UButton(text: '提交授权', onPressed: _submit, loading: _submitting),
            ),
          ),
        ],
      ),
    );
  }
}
