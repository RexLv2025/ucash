import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'repay_page.dart';

class LoanDetailPage extends StatefulWidget {
  final int loanId;
  const LoanDetailPage({super.key, required this.loanId});

  @override
  State<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends State<LoanDetailPage> {
  Map<String, dynamic>? _loan;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/api/loans/${widget.loanId}');
      if (!mounted) return;
      setState(() {
        _loan = Map<String, dynamic>.from(data as Map);
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
    final loan = _loan;
    final canRepay = loan != null && ['active', 'overdue'].contains(loan['status']);
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '借款详情'),
      body: _loading
          ? const ULoading()
          : loan == null
              ? const UEmpty(text: '借款记录不存在')
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Column(
                          children: [
                            UCard(
                              gradient: UColors.navyGradient,
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text('借款金额（元）', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                                      const Spacer(),
                                      UTag(
                                        text: statusText(loan['status'] as String),
                                        color: loan['status'] == 'overdue' ? UColors.danger : Colors.white,
                                        filled: true,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(money(loan['principalCents'] as num), style: const TextStyle(color: Colors.white, fontSize: 34, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 14),
                                  Row(
                                    children: [
                                      _kv('剩余本金', '${money(loan['remainingPrincipalCents'] as num)}'),
                                      _kv('已还本金', '${money(loan['paidPrincipalCents'] as num)}'),
                                      _kv('已还利息', '${money(loan['paidInterestCents'] as num)}'),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            UCard(
                              child: Column(
                                children: [
                                  _row('借款单号', loan['loanNo'] as String? ?? '--'),
                                  _row('借款期限', '${loan['termMonths']} 期'),
                                  _row('合同年利率', '${rate(loan['rateBp'] as num)}%'),
                                  _row('综合年化（IRR）', '${rate(loan['aprBp'] as num)}%'),
                                  _row('总利息', '${money(loan['totalInterestCents'] as num)} 元'),
                                  _row('总还款', '${money(loan['totalRepayCents'] as num)} 元'),
                                  _row('放款日期', dateShort(loan['disbursedAt'] as String?)),
                                  _row('首期还款日', dateShort(loan['firstDueDate'] as String?)),
                                  _row('合同编号', loan['contractNo'] as String? ?? '--'),
                                ],
                              ),
                            ),
                            const USectionTitle(title: '还款计划'),
                            UCard(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              child: Column(
                                children: (loan['schedules'] as List? ?? []).map((raw) {
                                  final s = raw as Map;
                                  final paid = s['status'] == 'paid';
                                  final overdue = s['status'] == 'overdue';
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 11),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 28,
                                              height: 28,
                                              decoration: BoxDecoration(
                                                color: (paid ? UColors.success : overdue ? UColors.danger : UColors.navy).withValues(alpha: 0.08),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '${s['periodNo']}',
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: paid ? UColors.success : overdue ? UColors.danger : UColors.navy),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(dateShort(s['dueDate'] as String?), style: UText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '本金 ${money(s['principalCents'] as num)} · 利息 ${money(s['interestCents'] as num)}${(s['penaltyCents'] as num? ?? 0) > 0 ? ' · 罚息 ${money(s['penaltyCents'] as num)}' : ''}',
                                                    style: UText.tiny.copyWith(fontSize: 10.5),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(money(s['totalCents'] as num), style: UText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 2),
                                                Text(paid ? '已还' : overdue ? '逾期' : '待还', style: UText.tiny.copyWith(fontSize: 10.5, color: paid ? UColors.success : overdue ? UColors.danger : UColors.textLight)),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (raw != (loan['schedules'] as List).last) const Divider(height: 1),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (canRepay)
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: UColors.navy.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -3))]),
                        child: SafeArea(
                          top: false,
                          child: UButton(
                            text: '去还款',
                            onPressed: () async {
                              await Navigator.push(context, MaterialPageRoute(builder: (_) => RepayPage(loanId: widget.loanId)));
                              _load();
                            },
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _kv(String k, String v) => Expanded(
        child: Column(
          children: [
            Text(v, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(k, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10.5)),
          ],
        ),
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Text(k, style: UText.sub.copyWith(fontSize: 13)),
            const Spacer(),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: UText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}
