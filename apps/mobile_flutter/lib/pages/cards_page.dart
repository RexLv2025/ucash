import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class CardsPage extends StatefulWidget {
  const CardsPage({super.key});

  @override
  State<CardsPage> createState() => _CardsPageState();
}

class _CardsPageState extends State<CardsPage> {
  List<Map<String, dynamic>> _cards = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/api/cards');
      if (!mounted) return;
      setState(() => _cards = ((data['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final name = TextEditingController();
    final cardNo = TextEditingController();
    final phone = TextEditingController();
    String bank = '招商银行';
    const banks = ['招商银行', '工商银行', '建设银行', '农业银行', '中国银行', '交通银行', '浦发银行', '平安银行'];

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('添加银行卡', style: UText.h3),
                    const Spacer(),
                    IconButton(onPressed: () => Navigator.pop(ctx, false), icon: const Icon(Icons.close, size: 20)),
                  ]),
                  const SizedBox(height: 6),
                  UField(label: '持卡人姓名', hint: '需与实名信息一致', controller: name),
                  const SizedBox(height: 14),
                  UField(
                    label: '银行卡号',
                    hint: '请输入 16-19 位卡号',
                    controller: cardNo,
                    keyboardType: TextInputType.number,
                    maxLength: 19,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 14),
                  UField(
                    label: '预留手机号',
                    hint: '银行预留手机号',
                    controller: phone,
                    keyboardType: TextInputType.phone,
                    maxLength: 11,
                    formatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  Text('开户银行', style: UText.sub.copyWith(fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: banks.map((b) {
                      final active = bank == b;
                      return GestureDetector(
                        onTap: () => setSheet(() => bank = b),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(color: active ? UColors.navy : UColors.bg, borderRadius: BorderRadius.circular(10)),
                          child: Text(b, style: TextStyle(fontSize: 12, color: active ? Colors.white : UColors.textSub)),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  UButton(
                    text: '确认添加',
                    onPressed: () async {
                      if (name.text.trim().length < 2 || cardNo.text.length < 16 || phone.text.length != 11) {
                        showToast(ctx, '请完整填写信息', error: true);
                        return;
                      }
                      try {
                        await ApiClient.instance.post('/api/cards', {
                          'bankName': bank,
                          'cardNo': cardNo.text,
                          'holderName': name.text.trim(),
                          'phone': phone.text,
                          'isDefault': false,
                        });
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } catch (e) {
                        if (ctx.mounted) showToast(ctx, e.toString(), error: true);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text('仅支持绑定持卡人本人的储蓄卡，信用卡不可用于收款', style: UText.tiny, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    name.dispose();
    cardNo.dispose();
    phone.dispose();
    if (ok == true) _load();
  }

  Future<void> _setDefault(int id) async {
    try {
      await ApiClient.instance.post('/api/cards/$id/default');
      _load();
      if (mounted) showToast(context, '已设为默认卡');
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _remove(int id) async {
    final ok = await showConfirm(context, title: '解绑银行卡', content: '解绑后该卡将无法用于借款与还款，确认解绑？');
    if (!ok) return;
    try {
      await ApiClient.instance.delete('/api/cards/$id');
      _load();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '银行卡管理', trailing: TextButton(onPressed: _add, child: const Text('添加', style: TextStyle(color: UColors.navy, fontSize: 14)))),
      body: _loading
          ? const ULoading()
          : _cards.isEmpty
              ? UEmpty(text: '暂无银行卡', sub: '绑定本人储蓄卡后即可借款', icon: Icons.credit_card_off_outlined, action: UButton(text: '添加银行卡', width: 160, small: true, onPressed: _add))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: _cards.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final c = _cards[i];
                    final isDefault = c['isDefault'] == true;
                    final invalid = c['status'] != 'active';
                    return Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isDefault ? [const Color(0xFF1C3F78), const Color(0xFF0F2B5B)] : [Colors.white, Colors.white],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(color: UColors.navy.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.account_balance_rounded, size: 20, color: isDefault ? UColors.goldLight : UColors.navy),
                              const SizedBox(width: 8),
                              Text(c['bankName'] as String? ?? '--', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: isDefault ? Colors.white : UColors.text)),
                              const SizedBox(width: 8),
                              if (isDefault)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(4)),
                                  child: const Text('默认', style: TextStyle(fontSize: 9.5, color: UColors.goldLight)),
                                ),
                              const Spacer(),
                              if (invalid) UTag(text: '异常', color: UColors.danger),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Text(
                            c['cardNoMask'] as String? ?? '',
                            style: TextStyle(fontSize: 19, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: isDefault ? Colors.white : UColors.text),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Text('储蓄卡', style: TextStyle(fontSize: 11, color: isDefault ? Colors.white.withValues(alpha: 0.5) : UColors.textLight)),
                              const Spacer(),
                              if (!isDefault) ...[
                                GestureDetector(onTap: () => _setDefault(c['id'] as int), child: Text('设为默认', style: UText.tiny.copyWith(color: UColors.navy))),
                                const SizedBox(width: 14),
                              ],
                              GestureDetector(onTap: () => _remove(c['id'] as int), child: Text('解绑', style: UText.tiny.copyWith(color: UColors.danger))),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
