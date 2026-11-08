import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'activate_page.dart';
import 'agreements_page.dart';
import 'cards_page.dart';
import 'coupons_page.dart';
import 'help_page.dart';
import 'invite_page.dart';
import 'loan_detail_page.dart';
import 'loans_page.dart';
import 'messages_page.dart';
import 'repayments_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  Future<void> _refresh() async {
    await session.refreshProfile();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final verified = session.me?['profile']?['verified'] as Map?;
        final allVerified = verified?['contacts'] == true;
        return Scaffold(
          backgroundColor: UColors.bg,
          body: RefreshIndicator(
            onRefresh: _refresh,
            color: UColors.gold,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  Container(
                    decoration: const BoxDecoration(gradient: UColors.navyGradient),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
                            child: Row(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    gradient: UColors.goldGradient,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 2),
                                  ),
                                  child: Center(
                                    child: Text(
                                      (session.name.isNotEmpty ? session.name.substring(0, 1) : 'U'),
                                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(session.name.isEmpty ? '未实名用户' : session.name, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w600)),
                                          const SizedBox(width: 8),
                                          if (allVerified)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(4)),
                                              child: const Text('已认证', style: TextStyle(color: UColors.goldLight, fontSize: 9.5)),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(session.phone, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13)),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
                                  icon: const Icon(Icons.settings_outlined, size: 21, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          // 额度卡
                          GestureDetector(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivatePage())).then((_) => _refresh()),
                            child: Container(
                              margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.07),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                children: [
                                  _limitCol('总额度', money(session.totalLimitCents)),
                                  _line(),
                                  _limitCol('已用额度', money(session.usedLimitCents)),
                                  _line(),
                                  _limitCol('可用额度', money(session.availableCents), highlight: true),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 26),
                        ],
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -14),
                    child: Column(
                      children: [
                        if (!allVerified)
                          UCard(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ActivatePage())).then((_) => _refresh()),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                                  child: const Icon(Icons.workspace_premium_outlined, size: 19, color: UColors.goldDark),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('完成认证，额度最高 5 万', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                      SizedBox(height: 2),
                                      Text('实名 + 人脸 + 联系人，最快 1 分钟', style: TextStyle(fontSize: 11, color: UColors.textSub)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
                              ],
                            ),
                          ),
                        if (!allVerified) const SizedBox(height: 12),
                        UCard(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _item(Icons.receipt_long_outlined, '借款记录', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoansPage()))),
                              _item(Icons.payments_outlined, '还款记录', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RepaymentsPage()))),
                              _item(Icons.credit_card_rounded, '银行卡管理', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CardsPage()))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        UCard(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _item(Icons.confirmation_num_outlined, '我的优惠券', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CouponsPage())), badge: '${session.couponCount}'),
                              _item(Icons.card_giftcard_rounded, '邀请有礼', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvitePage())), badge: '最高 200 元'),
                              _item(Icons.notifications_none_rounded, '消息中心', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MessagesPage())).then((_) => _refresh()), badge: session.unread > 0 ? '${session.unread}' : null, badgeDanger: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        UCard(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              _item(Icons.help_outline_rounded, '帮助与客服', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage()))),
                              _item(Icons.shield_outlined, '隐私与协议', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'privacy')))),
                              _item(Icons.info_outline_rounded, '关于 UCash', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('UCash v2.4.0 · 理性借贷 量力而行', style: UText.tiny),
                        const SizedBox(height: 8),
                        Text('综合年化利率 9%–24% · 以审批结果为准', style: UText.tiny.copyWith(fontSize: 10)),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _limitCol(String k, String v, {bool highlight = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(v, style: TextStyle(color: highlight ? UColors.goldLight : Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(k, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _line() => Container(width: 1, height: 26, color: Colors.white.withValues(alpha: 0.12));

  Widget _item(IconData icon, String label, VoidCallback onTap, {String? badge, bool badgeDanger = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: UColors.navy.withValues(alpha: 0.75)),
            const SizedBox(width: 12),
            Text(label, style: UText.body.copyWith(fontSize: 14)),
            const Spacer(),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeDanger ? UColors.danger : UColors.gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge, style: TextStyle(fontSize: 10.5, color: badgeDanger ? Colors.white : UColors.goldDark, fontWeight: FontWeight.w600)),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
          ],
        ),
      ),
    );
  }
}
