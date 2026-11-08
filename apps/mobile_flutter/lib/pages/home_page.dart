import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'activate_page.dart';
import 'bills_page.dart';
import 'borrow_page.dart';
import 'coupons_page.dart';
import 'help_page.dart';
import 'invite_page.dart';
import 'loans_page.dart';
import 'messages_page.dart';
import 'repay_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _current;
  Map<String, dynamic>? _settings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    session.addListener(_onSession);
  }

  @override
  void dispose() {
    session.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/loans/summary/current').catchError((_) => null),
        ApiClient.instance.get('/api/settings').catchError((_) => null),
      ]);
      if (!mounted) return;
      setState(() {
        _current = results[0] == null ? null : Map<String, dynamic>.from(results[0] as Map);
        _settings = results[1] == null ? null : Map<String, dynamic>.from(results[1] as Map);
      });
      await session.refreshProfile(silent: true);
    } catch (_) {
      // 静默失败，保留缓存
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _borrow() {
    if (session.creditStatus != 'approved') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivatePage()));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const BorrowPage())).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final notice = _settings?['notice'] as String?;
    final banners = (_settings?['banners'] as List?) ?? [];
    final approved = session.creditStatus == 'approved';

    return Scaffold(
      backgroundColor: UColors.bg,
      body: RefreshIndicator(
        onRefresh: _load,
        color: UColors.gold,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ===== 顶部额度区 =====
              Container(
                decoration: const BoxDecoration(gradient: UColors.navyGradient),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                        child: Row(
                          children: [
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(gradient: UColors.goldGradient, borderRadius: BorderRadius.circular(9)),
                              child: const Center(child: Text('U', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))),
                            ),
                            const SizedBox(width: 8),
                            const Text('UCash', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                            const Spacer(),
                            ListenableBuilder(
                              listenable: session,
                              builder: (_, __) => GestureDetector(
                                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesPage())).then((_) => _load()),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.notifications_none_rounded, color: Colors.white, size: 22),
                                    ),
                                    if (session.unread > 0)
                                      Positioned(
                                        right: 6,
                                        top: 6,
                                        child: Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(color: UColors.danger, shape: BoxShape.circle),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage())),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.headset_mic_outlined, color: Colors.white, size: 21),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 额度卡
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
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
                                Text('可用额度（元）', style: UText.sub.copyWith(fontSize: 13)),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivatePage())).then((_) => _load()),
                                  child: Row(children: [
                                    Text(approved ? '额度详情' : '激活额度', style: UText.tiny.copyWith(color: UColors.goldDark, fontSize: 12)),
                                    const Icon(Icons.chevron_right, size: 14, color: UColors.goldDark),
                                  ]),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(money(session.availableCents), style: UText.money.copyWith(fontSize: 40)),
                                const SizedBox(width: 6),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Text(approved ? '' : '最高可借 5 万', style: UText.tiny),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(color: UColors.bg, borderRadius: BorderRadius.circular(12)),
                              child: Row(
                                children: [
                                  _kv('总额度', '${money(session.totalLimitCents)}', first: true),
                                  _divider(),
                                  _kv('已用额度', money(session.usedLimitCents)),
                                  _divider(),
                                  _kv('年化利率', session.rateBp == null ? '--' : '${rate(session.rateBp!)}%'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            UButton(
                              text: approved ? '立即借款' : '激活我的额度',
                              onPressed: _borrow,
                            ),
                            const SizedBox(height: 10),
                            Center(
                              child: Text(
                                '综合年化利率（IRR）9%–24%，具体以审批结果为准',
                                style: UText.tiny.copyWith(fontSize: 10.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 26),
                    ],
                  ),
                ),
              ),
              // ===== 主体 =====
              Transform.translate(
                offset: const Offset(0, -14),
                child: Column(
                  children: [
                    // 四宫格
                    UCard(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Row(
                        children: [
                          _entry(Icons.trending_up_rounded, '提额任务', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivatePage())).then((_) => _load())),
                          _entry(Icons.confirmation_num_outlined, '优惠券', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CouponsPage()))),
                          _entry(Icons.card_giftcard_rounded, '邀请有礼', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvitePage()))),
                          _entry(Icons.menu_book_outlined, '借款攻略', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage()))),
                        ],
                      ),
                    ),
                    // 进行中借款
                    if (_current != null) ...[
                      const SizedBox(height: 12),
                      UCard(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillsPage())).then((_) => _load()),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('进行中的借款', style: UText.h3),
                                const SizedBox(width: 8),
                                UTag(
                                  text: _current!['status'] == 'overdue' ? '已逾期 ${_current!['overdueDays']} 天' : '第 ${_current!['nextPeriod']}/${_current!['termMonths']} 期',
                                  color: _current!['status'] == 'overdue' ? UColors.danger : UColors.navy,
                                ),
                                const Spacer(),
                                const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('本期应还（元）', style: UText.tiny),
                                    const SizedBox(height: 4),
                                    Text(money(_current!['nextAmountCents'] as num), style: UText.h2),
                                  ],
                                ),
                                const Spacer(),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('还款日 ${dateShort(_current!['nextDueDate'] as String?)}', style: UText.tiny),
                                    const SizedBox(height: 4),
                                    Text('剩余本金 ${money(_current!['principalCents'] as num)}', style: UText.tiny),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            UButton(
                              text: '立即还款',
                              small: true,
                              onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => RepayPage(loanId: _current!['loanId'] as int, settle: false)),
                              ).then((_) => _load()),
                            ),
                          ],
                        ),
                      ),
                    ],
                    // 邀请 banner
                    if (banners.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GestureDetector(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvitePage())),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFF1C3F78), Color(0xFF0F2B5B)]),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (banners[0] as Map)['title'] as String? ?? '邀请好友',
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        (banners[0] as Map)['subtitle'] as String? ?? '',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(gradient: UColors.goldGradient, borderRadius: BorderRadius.circular(20)),
                                  child: const Text('去邀请', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                    // 借款记录
                    const SizedBox(height: 12),
                    UCard(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          _rowItem(Icons.history_rounded, '借款记录', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoansPage()))),
                          const Divider(indent: 52),
                          _rowItem(Icons.shield_outlined, '安全与合规', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage()))),
                        ],
                      ),
                    ),
                    // 公告
                    if (notice != null && notice.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.campaign_outlined, size: 14, color: UColors.textLight),
                            const SizedBox(width: 6),
                            Expanded(child: Text(notice, style: UText.tiny.copyWith(height: 1.6))),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool first = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(v, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: UColors.text)),
          const SizedBox(height: 3),
          Text(k, style: UText.tiny.copyWith(fontSize: 10.5)),
        ],
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 24, color: UColors.line);

  Widget _entry(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, size: 21, color: UColors.goldDark),
            ),
            const SizedBox(height: 8),
            Text(label, style: UText.sub.copyWith(fontSize: 12, color: UColors.text)),
          ],
        ),
      ),
    );
  }

  Widget _rowItem(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 19, color: UColors.navy.withValues(alpha: 0.7)),
            const SizedBox(width: 12),
            Text(label, style: UText.body.copyWith(fontSize: 14)),
            const Spacer(),
            const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
          ],
        ),
      ),
    );
  }
}
