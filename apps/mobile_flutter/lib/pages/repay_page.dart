import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'cards_page.dart';
import 'repay_result_page.dart';

class RepayPage extends StatefulWidget {
  final int loanId;
  final bool settle;
  const RepayPage({super.key, required this.loanId, this.settle = false});

  @override
  State<RepayPage> createState() => _RepayPageState();
}

class _RepayPageState extends State<RepayPage> {
  Map<String, dynamic>? _quote;
  List<Map<String, dynamic>> _cards = [];
  int? _cardId;
  bool _settle = false;
  bool _loading = true;
  bool _submitting = false;
  late final String _idemKey = 'rp-${widget.loanId}-${DateTime.now().millisecondsSinceEpoch}';

  @override
  void initState() {
    super.initState();
    _settle = widget.settle;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/repayments/quote', query: {'loanId': widget.loanId, 'type': _settle ? 'settle' : 'normal'}),
        ApiClient.instance.get('/api/cards'),
      ]);
      if (!mounted) return;
      setState(() {
        _quote = Map<String, dynamic>.from(results[0] as Map);
        _cards = ((results[1]['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _cardId = _cards.isNotEmpty ? _cards.first['id'] as int : null;
      });
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switch(bool settle) async {
    if (_settle == settle) return;
    setState(() => _settle = settle);
    await _load();
  }

  Future<void> _submit() async {
    if (_quote == null || _cardId == null) return;
    final ok = await showConfirm(
      context,
      title: _settle ? '确认提前结清？' : '确认还款？',
      content: '将从尾号 ${(_cards.firstWhere((c) => c['id'] == _cardId, orElse: () => _cards.first)['cardNoMask'] as String).substring(11)} 的银行卡扣款 ${money(_quote!['totalCents'] as num)} 元',
    );
    if (!ok) return;
    setState(() => _submitting = true);
    try {
      final data = await ApiClient.instance.post(
        '/api/repayments',
        {
          'loanId': widget.loanId,
          'type': _settle ? 'settle' : 'normal',
          'bankCardId': _cardId,
        },
        {'Idempotency-Key': _idemKey},
      );
      await session.refreshProfile(silent: true);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RepayResultPage(
            amountCents: data['amountCents'] as int,
            settled: (data['loanStatus'] as Map?)?['status'] == 'settled',
            loanId: widget.loanId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _quote;
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: _settle ? '提前结清' : '还款'),
      body: _loading
          ? const ULoading()
          : q == null
              ? const UEmpty(text: '暂无可还账单')
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        child: Column(
                          children: [
                            UCard(
                              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                              child: Column(
                                children: [
                                  Text(_settle ? '结清应还（元）' : '本期应还（元）', style: UText.sub.copyWith(fontSize: 13)),
                                  const SizedBox(height: 10),
                                  Text(money(q['totalCents'] as num), style: UText.money.copyWith(fontSize: 42, color: UColors.navy)),
                                  const SizedBox(height: 10),
                                  Text(
                                    _settle
                                        ? '一次性结清剩余全部本息，后续利息免除'
                                        : '第 ${q['periodNo']} 期 · 到期日 ${dateShort(q['dueDate'] as String?)}',
                                    style: UText.tiny,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            UCard(
                              child: Column(
                                children: [
                                  _row('剩余本金', '${money(q['principalCents'] as num)} 元'),
                                  _row('应还利息', '${money(q['interestCents'] as num)} 元'),
                                  if ((q['penaltyCents'] as num? ?? 0) > 0) _row('逾期罚息', '${money(q['penaltyCents'] as num)} 元', danger: true),
                                  if (_settle) _row('减免未来利息', '${money(q['savedInterestCents'] as num? ?? 0)} 元', success: true),
                                  if (_settle && (q['settlePenaltyCents'] as num? ?? 0) > 0)
                                    _row('提前结清违约金', '${money(q['settlePenaltyCents'] as num)} 元'),
                                  const Divider(height: 24),
                                  Row(
                                    children: [
                                      Text('合计', style: UText.sub.copyWith(fontSize: 13)),
                                      const Spacer(),
                                      Text(money(q['totalCents'] as num), style: UText.h3.copyWith(fontSize: 18)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            UCard(
                              padding: const EdgeInsets.all(4),
                              child: Column(
                                children: [
                                  _modeTile(false, '按期还款', '归还本期应还金额，保持良好信用记录'),
                                  _modeTile(true, '提前结清', '一次性结清全部剩余本息，节省后续利息'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            UCard(
                              padding: EdgeInsets.zero,
                              child: InkWell(
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const CardsPage()));
                                  _load();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.credit_card_rounded, size: 20, color: UColors.navy),
                                      const SizedBox(width: 10),
                                      Text('还款银行卡', style: UText.body.copyWith(fontSize: 14)),
                                      const Spacer(),
                                      Text(
                                        _cards.isEmpty
                                            ? '去绑定'
                                            : '${_cards.firstWhere((c) => c['id'] == _cardId, orElse: () => _cards.first)['bankName']} ${_cards.firstWhere((c) => c['id'] == _cardId, orElse: () => _cards.first)['cardNoMask']}',
                                        style: UText.tiny,
                                      ),
                                      const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text('还款将实时划扣，请确保卡内余额充足。如已逾期，请尽快处理以免影响信用记录。', style: UText.tiny, textAlign: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: UColors.navy.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, -3))]),
                      child: SafeArea(
                        top: false,
                        child: UButton(
                          text: '确认${_settle ? '结清' : '还款'} ¥${money(q['totalCents'] as num)}',
                          onPressed: _cards.isEmpty ? null : _submit,
                          loading: _submitting,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _modeTile(bool settle, String title, String sub) {
    final active = _settle == settle;
    return InkWell(
      onTap: () => _switch(settle),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: active ? UColors.navy.withValues(alpha: 0.04) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? UColors.navy.withValues(alpha: 0.2) : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(active ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: active ? UColors.navy : UColors.textLight),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: UText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sub, style: UText.tiny),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, {bool danger = false, bool success = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Text(k, style: UText.sub.copyWith(fontSize: 13)),
          const Spacer(),
          Text(v, style: UText.body.copyWith(fontSize: 13, color: danger ? UColors.danger : success ? UColors.success : UColors.text)),
        ],
      ),
    );
  }
}
