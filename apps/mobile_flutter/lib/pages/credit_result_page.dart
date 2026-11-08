import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'borrow_page.dart';
import 'main_shell.dart';

class CreditResultPage extends StatelessWidget {
  final Map<String, dynamic> result;
  const CreditResultPage({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final status = result['status'] as String? ?? 'manual';
    final credit = result['credit'] as Map? ?? session.credit ?? {};
    final approved = status == 'approved' || status == 'approve';
    final rejected = status == 'rejected' || status == 'reject';
    final reason = (result['risk'] as Map?)?['rejectReason'] as String? ?? credit['rejectReason'] as String?;

    return Scaffold(
      backgroundColor: UColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 1),
              Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: (approved ? UColors.success : rejected ? UColors.danger : UColors.warning).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  approved ? Icons.check_rounded : rejected ? Icons.close_rounded : Icons.access_time_rounded,
                  size: 46,
                  color: approved ? UColors.success : rejected ? UColors.danger : UColors.warning,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                approved ? '额度已激活' : rejected ? '本次申请未通过' : '申请已提交',
                style: UText.h2.copyWith(fontSize: 23),
              ),
              const SizedBox(height: 8),
              Text(
                approved
                    ? '恭喜，您的额度已生效，可立即借款'
                    : rejected
                        ? (reason ?? '综合评估未通过，建议 3 个月后重试')
                        : '人工审核预计 1 个工作日内完成，请留意站内信',
                textAlign: TextAlign.center,
                style: UText.sub,
              ),
              if (approved) ...[
                const SizedBox(height: 26),
                UCard(
                  gradient: UColors.navyGradient,
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                  child: Column(
                    children: [
                      Text('可用额度（元）', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        money((credit['availableLimitCents'] as num?) ?? 0),
                        style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '综合年化利率 ${rate((credit['interestRateBp'] as num?) ?? 0)}% 起 · 额度有效期 ${dateShort(credit['expiresAt'] as String?)}',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
              if (!approved) ...[
                const SizedBox(height: 24),
                UCard(
                  child: Column(
                    children: [
                      _row('申请编号', 'CR${result['applicationId'] ?? '--'}'),
                      _row('综合评分', '${(result['risk'] as Map?)?['score'] ?? credit['score'] ?? '--'}'),
                      _row('申请时间', dateTimeShort(DateTime.now().toIso8601String())),
                    ],
                  ),
                ),
              ],
              const Spacer(flex: 2),
              if (approved) ...[
                UButton(text: '立即借款', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BorrowPage()))),
                const SizedBox(height: 10),
                UButton(text: '返回首页', ghost: true, onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (r) => false)),
              ] else ...[
                UButton(text: '返回首页', onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (r) => false)),
                const SizedBox(height: 10),
                UButton(text: '联系客服', ghost: true, onPressed: () => showToast(context, '客服热线 400-000-8888')),
              ],
              const SizedBox(height: 24),
              Text('额度与利率由系统综合评估确定', style: UText.tiny),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Text(k, style: UText.sub.copyWith(fontSize: 13)),
          const Spacer(),
          Text(v, style: UText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
        ]),
      );
}
