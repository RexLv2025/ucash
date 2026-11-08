import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'main_shell.dart';

class RepayResultPage extends StatelessWidget {
  final int amountCents;
  final bool settled;
  final int loanId;
  const RepayResultPage({super.key, required this.amountCents, required this.settled, required this.loanId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(color: UColors.success.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, size: 48, color: UColors.success),
              ),
              const SizedBox(height: 24),
              Text(settled ? '结清成功' : '还款成功', style: UText.h2.copyWith(fontSize: 24)),
              const SizedBox(height: 10),
              Text(money(amountCents, symbol: true), style: UText.money.copyWith(fontSize: 34, color: UColors.navy)),
              const SizedBox(height: 10),
              Text(
                settled ? '该笔借款已全部结清，感谢您的守信' : '本期账单已还清，请继续保持良好还款记录',
                textAlign: TextAlign.center,
                style: UText.sub,
              ),
              const Spacer(flex: 3),
              UButton(
                text: '返回账单',
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (r) => false),
              ),
              const SizedBox(height: 12),
              Text('还款凭证已生成，可在「我的-还款记录」中查看', style: UText.tiny),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
