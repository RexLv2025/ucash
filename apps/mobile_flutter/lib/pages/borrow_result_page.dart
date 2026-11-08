import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'cards_page.dart';
import 'help_page.dart';
import 'main_shell.dart';

class BorrowResultPage extends StatefulWidget {
  final int loanId;
  final Map<String, dynamic> initial;
  const BorrowResultPage({super.key, required this.loanId, required this.initial});

  @override
  State<BorrowResultPage> createState() => _BorrowResultPageState();
}

class _BorrowResultPageState extends State<BorrowResultPage> {
  Map<String, dynamic> _loan = {};
  Timer? _timer;
  int _tries = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loan = widget.initial;
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _pending => ['reviewing', 'disbursing'].contains(_loan['status']);

  Future<void> _poll() async {
    _tries++;
    try {
      final data = await ApiClient.instance.get('/api/loans/${widget.loanId}');
      if (!mounted) return;
      setState(() {
        _loan = Map<String, dynamic>.from(data as Map);
        _loading = false;
      });
      if (['reviewing', 'disbursing'].contains(_loan['status']) && _tries < 20) {
        _timer = Timer(const Duration(milliseconds: 800), _poll);
      } else {
        session.refreshProfile(silent: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _retry() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CardsPage()));
    final cards = await ApiClient.instance.get('/api/cards');
    final list = (cards['list'] as List?) ?? [];
    if (list.isEmpty) return;
    final id = (list.first as Map)['id'] as int;
    try {
      await ApiClient.instance.post('/api/loans/${widget.loanId}/retry', {'bankCardId': id});
      setState(() {
        _loan['status'] = 'reviewing';
        _tries = 0;
      });
      _poll();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    final status = _loan['status'];
    final success = status == 'active';
    final failed = ['failed', 'rejected'].contains(status);

    return Scaffold(
      backgroundColor: UColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _pending ? null : _goHome,
                child: Text('完成', style: UText.sub.copyWith(color: _pending ? UColors.textLight : UColors.navy)),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    _iconArea(success: success, failed: failed),
                    const SizedBox(height: 22),
                    Text(
                      _pending ? '正在为您放款' : success ? '借款成功' : '放款失败',
                      style: UText.h2.copyWith(fontSize: 24),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _pending
                          ? '预计 1 分钟内到账，请勿重复提交'
                          : success
                              ? '款项已发放至您的银行卡，请注意查收'
                              : (_loan['failReason'] as String? ?? '请更换银行卡后重试'),
                      textAlign: TextAlign.center,
                      style: UText.sub,
                    ),
                    if (success) ...[
                      const SizedBox(height: 26),
                      Text(money(_loan['principalCents'] as num), style: UText.money.copyWith(fontSize: 40, color: UColors.navy)),
                      const SizedBox(height: 4),
                      Text('到账金额（元）', style: UText.tiny),
                    ],
                    const SizedBox(height: 28),
                    // 进度
                    UCard(
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                      child: Column(
                        children: [
                          _step(0, '提交申请', '${dateTimeShort(_loan['createdAt'] as String?)}', true, true),
                          _stepLine(true),
                          _step(1, '风控审核', _pending || success || failed ? '已完成' : '处理中', _pending || success || failed, _pending),
                          _stepLine(_pending || success || failed),
                          _step(2, '放款到账', success ? '已到账' : failed ? '失败' : '处理中', success, _pending),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (success)
                      UCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _row('借款单号', _loan['loanNo'] as String? ?? '--'),
                            _row('借款期限', '${_loan['termMonths']} 期'),
                            _row('合同年利率', '${rate(_loan['rateBp'] as num)}%'),
                            _row('综合年化（IRR）', '${rate(_loan['aprBp'] as num)}%'),
                            _row('首期还款日', dateShort(_loan['firstDueDate'] as String?)),
                            _row('每期应还', '${money(_loan['monthlyPaymentCents'] as num)} 元'),
                            _row('总还款', '${money(_loan['totalRepayCents'] as num)} 元'),
                          ],
                        ),
                      ),
                    if (failed)
                      UCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _row('错误码', _loan['failCode'] as String? ?? 'E1024'),
                            _row('借款单号', _loan['loanNo'] as String? ?? '--'),
                            _row('处理建议', '请更换本人名下状态正常的储蓄卡'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 28),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                children: [
                  if (_pending)
                    UButton(text: '处理中…', onPressed: null, loading: true)
                  else if (success) ...[
                    UButton(text: '查看还款计划', onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const MainShell()), (r) => false)),
                    const SizedBox(height: 10),
                    UButton(text: '返回首页', ghost: true, onPressed: _goHome),
                  ] else ...[
                    UButton(text: '更换银行卡并重试', onPressed: _retry),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: UButton(text: '联系客服', ghost: true, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage())))),
                      const SizedBox(width: 10),
                      Expanded(child: UButton(text: '稍后处理', ghost: true, onPressed: _goHome)),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Text('如遇问题请联系客服 400-000-8888', style: UText.tiny),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconArea({required bool success, required bool failed}) {
    if (_pending) {
      return Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(color: UColors.gold.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: const Center(child: SizedBox(width: 34, height: 34, child: CircularProgressIndicator(strokeWidth: 2.6, color: UColors.gold))),
      );
    }
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: (success ? UColors.success : UColors.danger).withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(success ? Icons.check_rounded : Icons.close_rounded, size: 46, color: success ? UColors.success : UColors.danger),
    );
  }

  Widget _step(int index, String title, String sub, bool done, bool active) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: done ? UColors.navy : (active ? UColors.gold.withValues(alpha: 0.2) : UColors.bg),
            shape: BoxShape.circle,
          ),
          child: Icon(
            done ? Icons.check : Icons.circle,
            size: done ? 14 : 7,
            color: done ? Colors.white : (active ? UColors.gold : UColors.textLight),
          ),
        ),
        const SizedBox(width: 12),
        Text(title, style: UText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(sub, style: UText.tiny),
      ],
    );
  }

  Widget _stepLine(bool done) {
    return Container(
      margin: const EdgeInsets.only(left: 11.5),
      height: 22,
      width: 1.2,
      color: done ? UColors.navy.withValues(alpha: 0.3) : UColors.line,
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(k, style: UText.sub.copyWith(fontSize: 13)),
            const Spacer(),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: UText.body.copyWith(fontSize: 13, fontWeight: FontWeight.w500))),
          ],
        ),
      );
}
