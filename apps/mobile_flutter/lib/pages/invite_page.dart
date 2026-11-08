import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class InvitePage extends StatefulWidget {
  const InvitePage({super.key});

  @override
  State<InvitePage> createState() => _InvitePageState();
}

class _InvitePageState extends State<InvitePage> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/api/invitations');
      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(data as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, e.toString(), error: true);
    }
  }

  void _copy(String text, String tip) {
    Clipboard.setData(ClipboardData(text: text));
    showToast(context, tip);
  }

  @override
  Widget build(BuildContext context) {
    final code = (_data?['inviteCode'] as String?) ?? session.inviteCode;
    final list = (_data?['list'] as List?) ?? [];
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '邀请有礼', transparent: true),
      body: _loading
          ? const ULoading()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1C3F78), Color(0xFF0F2B5B)]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(color: UColors.navy.withValues(alpha: 0.2), blurRadius: 20, offset: const Offset(0, 8))],
                    ),
                    child: Column(
                      children: [
                        const Text('邀请好友借款', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('好友完成首借，您最高得 200 元奖励', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5)),
                        const SizedBox(height: 22),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: UColors.gold.withValues(alpha: 0.35))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('邀请码', style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 12)),
                              const SizedBox(width: 12),
                              Text(code, style: const TextStyle(color: UColors.goldLight, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 3)),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => _copy(code, '邀请码已复制'),
                                child: const Icon(Icons.copy_rounded, size: 16, color: UColors.goldLight),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: UButton(
                            text: '分享给好友',
                            onPressed: () => _copy('我在用 UCash，额度灵活到账快。填写我的邀请码 $code，一起领福利～', '邀请文案已复制，去粘贴给好友吧'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  UCard(
                    child: Row(
                      children: [
                        _stat('已邀请', '${_data?['totalInvited'] ?? 0}', '人'),
                        Container(width: 1, height: 30, color: UColors.line),
                        _stat('已获奖励', money((_data?['totalRewardCents'] as num?) ?? 0), '元'),
                        Container(width: 1, height: 30, color: UColors.line),
                        _stat('待发放', money((_data?['pendingRewardCents'] as num?) ?? 0), '元'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  UCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('活动规则', style: UText.h3),
                        const SizedBox(height: 12),
                        _rule('1', '分享您的专属邀请码给好友'),
                        _rule('2', '好友注册并填写邀请码完成绑定'),
                        _rule('3', '好友完成实名认证并成功首借'),
                        _rule('4', '奖励在好友放款成功后 24 小时内到账'),
                        const SizedBox(height: 4),
                        Text('注：同一设备、同一身份证、同一银行卡视为同一用户；违规刷单将取消奖励资格。', style: UText.tiny.copyWith(height: 1.6)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Align(alignment: Alignment.centerLeft, child: Text('邀请记录', style: UText.h3)),
                  const SizedBox(height: 10),
                  if (list.isEmpty)
                    const UEmpty(text: '还没有邀请记录', sub: '分享邀请码，好友借款您得奖励', icon: Icons.people_outline)
                  else
                    UCard(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: list.asMap().entries.map((e) {
                          final r = Map<String, dynamic>.from(e.value as Map);
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                                child: Row(
                                  children: [
                                    const Icon(Icons.person_outline, size: 18, color: UColors.textLight),
                                    const SizedBox(width: 10),
                                    Text(r['phone'] as String? ?? '--', style: UText.body.copyWith(fontSize: 13.5)),
                                    const Spacer(),
                                    UTag(
                                      text: r['status'] == 'borrowed' ? '已首借' : r['status'] == 'credited' ? '已授信' : '已注册',
                                      color: r['status'] == 'borrowed' ? UColors.success : UColors.textSub,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      (r['rewardCents'] as num? ?? 0) > 0 ? '+${money(r['rewardCents'] as num)}' : '待发放',
                                      style: UText.tiny.copyWith(color: (r['rewardCents'] as num? ?? 0) > 0 ? UColors.goldDark : UColors.textLight),
                                    ),
                                  ],
                                ),
                              ),
                              if (e.key < list.length - 1) const Divider(height: 1, indent: 16, endIndent: 16),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _stat(String k, String v, String unit) => Expanded(
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 2),
                Text(unit, style: UText.tiny.copyWith(fontSize: 10)),
              ],
            ),
            const SizedBox(height: 3),
            Text(k, style: UText.tiny.copyWith(fontSize: 10.5)),
          ],
        ),
      );

  Widget _rule(String no, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(color: UColors.navy.withValues(alpha: 0.06), shape: BoxShape.circle),
              child: Center(child: Text(no, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: UColors.navy))),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: UText.sub.copyWith(fontSize: 12.5))),
          ],
        ),
      );
}
