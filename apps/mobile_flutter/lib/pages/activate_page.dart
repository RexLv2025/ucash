import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'borrow_page.dart';
import 'credit_result_page.dart';
import 'kyc_contacts_page.dart';
import 'kyc_face_page.dart';
import 'kyc_realname_page.dart';

class ActivatePage extends StatefulWidget {
  const ActivatePage({super.key});

  @override
  State<ActivatePage> createState() => _ActivatePageState();
}

class _ActivatePageState extends State<ActivatePage> {
  Map<String, dynamic>? _kyc;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/api/kyc/status');
      if (!mounted) return;
      setState(() => _kyc = Map<String, dynamic>.from(data as Map));
      await session.refreshProfile(silent: true);
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _nextStep() async {
    final steps = (_kyc?['steps'] as List?) ?? [];
    final next = steps.cast<Map>().where((s) => s['done'] != true).toList();
    if (next.isEmpty) {
      await _applyCredit();
      return;
    }
    final key = next.first['key'] as String;
    Widget page = key == 'realname'
        ? const KycRealnamePage()
        : key == 'face'
            ? const KycFacePage()
            : const KycContactsPage();
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Future<void> _applyCredit() async {
    setState(() => _submitting = true);
    try {
      final data = await ApiClient.instance.post('/api/credit/applications', {'amountCents': 5000000, 'purpose': '日常消费'});
      await session.refreshProfile(silent: true);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => CreditResultPage(result: Map<String, dynamic>.from(data as Map))));
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final credit = session.credit;
    final status = session.creditStatus;
    final approved = status == 'approved';
    final steps = (_kyc?['steps'] as List?) ?? [];
    final doneCount = (_kyc?['doneCount'] as num?)?.toInt() ?? 0;

    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: approved ? '我的额度' : '激活额度'),
      body: _loading
          ? const ULoading()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: Column(
                children: [
                  // 额度展示
                  UCard(
                    gradient: UColors.navyGradient,
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(approved ? '可用额度（元）' : '预估额度（元）', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                            const Spacer(),
                            UTag(
                              text: approved ? '已激活' : statusText(status),
                              color: approved ? UColors.goldLight : Colors.white,
                              filled: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          approved ? money(session.availableCents) : '${money(_estimateCents(), decimals: false)}',
                          style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w700, height: 1.05),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          approved
                              ? '综合年化利率 ${rate(session.rateBp ?? 0)}% · 额度有效期至 ${dateShort(credit?['expiresAt'] as String?)}'
                              : '完成认证后即可获得额度，最高 5 万元',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            _badge(Icons.bolt_rounded, '最快 1 分钟'),
                            const SizedBox(width: 8),
                            _badge(Icons.autorenew_rounded, '随借随还'),
                            const SizedBox(width: 8),
                            _badge(Icons.lock_outline_rounded, '信息加密'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 认证进度
                  UCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('认证进度', style: UText.h3),
                            const Spacer(),
                            Text('$doneCount/3', style: UText.sub.copyWith(color: UColors.goldDark, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: doneCount / 3,
                            minHeight: 6,
                            backgroundColor: UColors.line,
                            valueColor: const AlwaysStoppedAnimation(UColors.gold),
                          ),
                        ),
                        const SizedBox(height: 18),
                        ...steps.map((raw) {
                          final s = raw as Map;
                          final done = s['done'] == true;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: done ? UColors.success.withValues(alpha: 0.1) : UColors.bg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(done ? Icons.check_rounded : Icons.circle_outlined, size: done ? 15 : 13, color: done ? UColors.success : UColors.textLight),
                                ),
                                const SizedBox(width: 10),
                                Text(s['title'] as String, style: UText.body.copyWith(fontSize: 14)),
                                const Spacer(),
                                Text(done ? '已完成' : '去完成', style: UText.tiny.copyWith(color: done ? UColors.success : UColors.navy, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          );
                        }),
                        if (status == 'rejected') ...[
                          const Divider(height: 18),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: UColors.danger.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(10)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('本次授信未通过', style: UText.sub.copyWith(color: UColors.danger, fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(height: 4),
                                Text(credit?['rejectReason'] as String? ?? '综合评估未通过，建议 3 个月后重试', style: UText.tiny.copyWith(height: 1.6)),
                              ],
                            ),
                          ),
                        ],
                        if (status == 'manual') ...[
                          const Divider(height: 18),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: UColors.warning.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                            child: Text('申请已提交人工审核，预计 1 个工作日内完成，请留意站内信通知。', style: UText.tiny.copyWith(height: 1.6)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 提额任务
                  if (approved)
                    UCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('提额任务', style: UText.h3),
                          const SizedBox(height: 4),
                          Text('补充资质认证，可提升额度与降低利率', style: UText.tiny),
                          const SizedBox(height: 14),
                          ..._boostRows(),
                        ],
                      ),
                    ),
                  if (approved) const SizedBox(height: 16),
                  UCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('为什么选择 UCash', style: UText.h3),
                        const SizedBox(height: 14),
                        _feature(Icons.speed_rounded, '极速审批', '自动化风控决策，最快 1 分钟出额度'),
                        _feature(Icons.account_balance_wallet_outlined, '灵活借款', '500-50000 元，3/6/12 期自由选择'),
                        _feature(Icons.verified_outlined, '合规透明', '综合年化利率明示，无砍头息、无会员费'),
                        _feature(Icons.support_agent_rounded, '贴心服务', '7×12 小时客服在线，还款提醒不打扰'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!approved)
                    UButton(
                      text: doneCount < 3 ? '继续完成认证' : status == 'manual' ? '审核中，查看进度' : status == 'rejected' ? '重新申请' : '提交授信申请',
                      onPressed: status == 'manual' ? () => showToast(context, '人工审核中，预计 1 个工作日内完成') : _nextStep,
                      loading: _submitting,
                    )
                  else
                    UButton(text: '立即借款', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BorrowPage()))),
                  const SizedBox(height: 12),
                  Text('额度与利率由系统综合评估确定，以实际审批结果为准', style: UText.tiny, textAlign: TextAlign.center),
                ],
              ),
            ),
    );
  }

  int _estimateCents() {
    final income = (session.me?['profile']?['monthlyIncomeCents'] as num?)?.toInt() ?? 0;
    if (income >= 2000000) return 5000000;
    if (income >= 1000000) return 3000000;
    if (income >= 500000) return 1500000;
    return 800000;
  }

  List<Widget> _boostRows() {
    final boosts = (_kyc?['boosts'] as Map?) ?? {};
    final items = [
      ['provider', '运营商认证', '验证手机号在网时长', '+3000 元'],
      ['fund', '公积金认证', '连续缴存满 6 个月', '+5000 元'],
      ['cardbill', '信用卡账单', '近 6 期账单正常', '+3000 元'],
    ];
    return items.map((it) {
      final done = boosts[it[0]] == true;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(done ? Icons.check_rounded : Icons.add_rounded, size: 17, color: UColors.goldDark),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(it[1], style: UText.body.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  Text(it[2], style: UText.tiny.copyWith(fontSize: 10.5)),
                ],
              ),
            ),
            Text(done ? '已认证' : it[3], style: UText.tiny.copyWith(color: done ? UColors.success : UColors.goldDark, fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            if (!done)
              GestureDetector(
                onTap: () async {
                  try {
                    await ApiClient.instance.post('/api/kyc/boost', {'type': it[0]});
                    await _load();
                    if (mounted) showToast(context, '认证成功');
                  } catch (e) {
                    if (mounted) showToast(context, e.toString(), error: true);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: UColors.navy, borderRadius: BorderRadius.circular(14)),
                  child: const Text('去认证', style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
          ],
        ),
      );
    }).toList();
  }

  Widget _badge(IconData icon, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: UColors.goldLight),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.8))),
        ]),
      );

  Widget _feature(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: UColors.navy.withValues(alpha: 0.75)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: UText.body.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(sub, style: UText.tiny),
                ],
              ),
            ),
          ],
        ),
      );
}
