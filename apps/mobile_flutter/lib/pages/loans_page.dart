import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'loan_detail_page.dart';

class LoansPage extends StatefulWidget {
  const LoansPage({super.key});

  @override
  State<LoansPage> createState() => _LoansPageState();
}

class _LoansPageState extends State<LoansPage> {
  int _tab = 0;
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  static const _keys = [null, 'active', 'settled', 'failed'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/api/loans', query: {if (_keys[_tab] != null) 'status': _keys[_tab]!});
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

  Color _statusColor(String s) {
    switch (s) {
      case 'active':
        return UColors.navy;
      case 'overdue':
        return UColors.danger;
      case 'settled':
        return UColors.success;
      case 'failed':
      case 'rejected':
        return UColors.textSub;
      default:
        return UColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '借款记录'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: List.generate(4, (i) {
                  final labels = ['全部', '还款中', '已结清', '未通过'];
                  final active = _tab == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _tab = i);
                        _load();
                      },
                      child: Container(
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: active ? UColors.navy : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                        child: Text(labels[i], style: TextStyle(fontSize: 12.5, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? Colors.white : UColors.textSub)),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const ULoading()
                : _list.isEmpty
                    ? const UEmpty(text: '暂无借款记录', sub: '额度激活后即可申请借款', icon: Icons.receipt_long_outlined)
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: UColors.gold,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final l = _list[i];
                            final status = l['status'] as String;
                            return UCard(
                              onTap: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: l['id'] as int)));
                                _load();
                              },
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Text('借款 ${money(l['principalCents'] as num)} 元', style: UText.h3.copyWith(fontSize: 15)),
                                      const SizedBox(width: 8),
                                      UTag(text: statusText(status), color: _statusColor(status)),
                                      const Spacer(),
                                      const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Text('${l['termMonths']} 期 · 年化 ${rate(l['aprBp'] as num)}%', style: UText.tiny),
                                      const Spacer(),
                                      Text(dateShort(l['createdAt'] as String?), style: UText.tiny),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Text('月供 ${money(l['monthlyPaymentCents'] as num)} 元', style: UText.tiny),
                                      const Spacer(),
                                      if ((l['remainingPrincipalCents'] as num? ?? 0) > 0)
                                        Text('剩余本金 ${money(l['remainingPrincipalCents'] as num)} 元', style: UText.tiny.copyWith(color: UColors.navy)),
                                    ],
                                  ),
                                  if (status == 'overdue') ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text('已逾期 ${l['overdueDays']} 天，请尽快处理', style: UText.tiny.copyWith(color: UColors.danger)),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
