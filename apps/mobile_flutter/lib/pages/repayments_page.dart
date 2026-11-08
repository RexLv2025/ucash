import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class RepaymentsPage extends StatefulWidget {
  const RepaymentsPage({super.key});

  @override
  State<RepaymentsPage> createState() => _RepaymentsPageState();
}

class _RepaymentsPageState extends State<RepaymentsPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/api/repayments');
      if (!mounted) return;
      setState(() {
        _list = ((data['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '还款记录'),
      body: _loading
          ? const ULoading()
          : _list.isEmpty
              ? const UEmpty(text: '暂无还款记录', sub: '成功还款后可在此查看凭证', icon: Icons.payments_outlined)
              : RefreshIndicator(
                  onRefresh: _load,
                  color: UColors.gold,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final r = _list[i];
                      final settle = r['type'] == 'settle';
                      return UCard(
                        onTap: () => showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            title: const Text('还款凭证', style: UText.h3),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _kv('还款单号', r['repaymentNo'] as String? ?? '--'),
                                _kv('借款单号', r['loanNo'] as String? ?? '--'),
                                _kv('还款类型', settle ? '提前结清' : '按期还款'),
                                _kv('还款金额', '${money(r['amountCents'] as num)} 元'),
                                _kv('其中本金', '${money(r['principalCents'] as num)} 元'),
                                _kv('其中利息', '${money(r['interestCents'] as num)} 元'),
                                if ((r['penaltyCents'] as num? ?? 0) > 0) _kv('其中罚息', '${money(r['penaltyCents'] as num)} 元'),
                                _kv('还款时间', dateTimeShort(r['paidAt'] as String?)),
                                _kv('还款状态', '成功'),
                              ],
                            ),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭', style: TextStyle(color: UColors.navy)))],
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(color: UColors.success.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(11)),
                              child: const Icon(Icons.check_rounded, size: 19, color: UColors.success),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(settle ? '提前结清' : '按期还款', style: UText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
                                  const SizedBox(height: 3),
                                  Text('${dateTimeShort(r['paidAt'] as String?)} · ${r['loanNo']}', style: UText.tiny.copyWith(fontSize: 10.5)),
                                ],
                              ),
                            ),
                            Text('-${money(r['amountCents'] as num)}', style: UText.h3.copyWith(fontSize: 16)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Text(k, style: UText.sub.copyWith(fontSize: 12.5)),
            const Spacer(),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: UText.body.copyWith(fontSize: 12.5, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}
