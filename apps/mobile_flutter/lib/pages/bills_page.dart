import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'help_page.dart';
import 'loan_detail_page.dart';
import 'repay_page.dart';

class BillsPage extends StatefulWidget {
  const BillsPage({super.key});

  @override
  State<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends State<BillsPage> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/api/bills');
      if (!mounted) return;
      setState(() => _data = Map<String, dynamic>.from(data as Map));
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _data?['summary'] as Map?;
    final unpaid = (_data?['unpaid'] as List?) ?? [];
    final paid = (_data?['paid'] as List?) ?? [];
    final list = _tab == 0 ? unpaid : (_tab == 1 ? paid : [...unpaid, ...paid]);
    final overdue = (summary?['overdueCount'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: UColors.bg,
      body: RefreshIndicator(
        onRefresh: _load,
        color: UColors.gold,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(gradient: UColors.navyGradient),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                        child: Row(
                          children: [
                            const Text('我的账单', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                            const Spacer(),
                            IconButton(
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage())),
                              icon: const Icon(Icons.help_outline, size: 20, color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                      // 本期应还
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: UColors.navyDeep.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(overdue > 0 ? '逾期应还（元）' : '本期应还（元）', style: UText.sub.copyWith(fontSize: 13)),
                                const Spacer(),
                                if (overdue > 0) UTag(text: '$overdue 期逾期', color: UColors.danger, filled: true),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              money((summary?['nextPayableCents'] as num?) ?? 0),
                              style: UText.money.copyWith(fontSize: 38, color: overdue > 0 ? UColors.danger : UColors.text),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              summary?['nextDueDate'] == null
                                  ? '暂无待还账单，保持良好信用'
                                  : '还款日 ${dateShort(summary!['nextDueDate'] as String?)}',
                              style: UText.tiny,
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: UButton(
                                    text: unpaid.isEmpty ? '暂无待还' : '立即还款',
                                    small: false,
                                    onPressed: unpaid.isEmpty
                                        ? null
                                        : () async {
                                            final first = unpaid.first as Map;
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(builder: (_) => RepayPage(loanId: first['loanId'] as int, settle: false)),
                                            );
                                            _load();
                                          },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(color: UColors.bg, borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                children: [
                                  _kv('待还笔数', '${summary?['unpaidCount'] ?? 0}'),
                                  Container(width: 1, height: 22, color: UColors.line),
                                  _kv('累计欠款', money((summary?['totalUnpaidCents'] as num?) ?? 0)),
                                  Container(width: 1, height: 22, color: UColors.line),
                                  _kv('已还清', '${summary?['paidCount'] ?? 0} 期'),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        _seg(0, '待还款 ${unpaid.length}'),
                        _seg(1, '已还清 ${paid.length}'),
                        _seg(2, '全部'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_loading)
              const SliverToBoxAdapter(child: ULoading())
            else if (list.isEmpty)
              SliverToBoxAdapter(
                child: UEmpty(
                  text: _tab == 1 ? '暂无已还清账单' : '暂无账单',
                  sub: '借款成功后，还款计划会展示在这里',
                  icon: Icons.receipt_long_outlined,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                sliver: SliverList.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _billItem(Map<String, dynamic>.from(list[i] as Map)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _seg(int i, String text) {
    final active = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = i),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? UColors.navy : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            text,
            style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? Colors.white : UColors.textSub),
          ),
        ),
      ),
    );
  }

  Widget _billItem(Map<String, dynamic> item) {
    final overdue = item['status'] == 'overdue';
    final paid = item['status'] == 'paid';
    final days = (item['overdueDays'] as num?)?.toInt() ?? 0;
    return UCard(
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: item['loanId'] as int)),
      ).then((_) => _load()),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: (paid ? UColors.success : overdue ? UColors.danger : UColors.navy).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  paid ? Icons.check_rounded : overdue ? Icons.error_outline_rounded : Icons.schedule_rounded,
                  size: 19,
                  color: paid ? UColors.success : overdue ? UColors.danger : UColors.navy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('第 ${item['periodNo']}/${item['termMonths']} 期', style: UText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text('到期日 ${dateShort(item['dueDate'] as String?)}', style: UText.tiny),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(item['payableCents'] as num),
                    style: UText.h3.copyWith(fontSize: 17, color: overdue ? UColors.danger : UColors.text),
                  ),
                  const SizedBox(height: 3),
                  UTag(
                    text: paid ? '已还清' : overdue ? '逾期 $days 天' : '待还款',
                    color: paid ? UColors.success : overdue ? UColors.danger : UColors.warning,
                  ),
                ],
              ),
            ],
          ),
          if (!paid) ...[
            const Divider(height: 22),
            Row(
              children: [
                Text('本金 ${money(item['principalCents'] as num)}', style: UText.tiny),
                const SizedBox(width: 12),
                Text('利息 ${money(item['interestCents'] as num)}', style: UText.tiny),
                if ((item['penaltyCents'] as num? ?? 0) > 0) ...[
                  const SizedBox(width: 12),
                  Text('罚息 ${money(item['penaltyCents'] as num)}', style: UText.tiny.copyWith(color: UColors.danger)),
                ],
                const Spacer(),
                Text('去还款', style: UText.tiny.copyWith(color: UColors.navy, fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right, size: 14, color: UColors.navy),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Expanded(
      child: Column(
        children: [
          Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(k, style: UText.tiny.copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }
}
