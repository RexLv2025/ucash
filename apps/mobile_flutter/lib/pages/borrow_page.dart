import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'agreements_page.dart';
import 'borrow_result_page.dart';
import 'cards_page.dart';
import 'coupons_page.dart';
import 'help_page.dart';

class BorrowPage extends StatefulWidget {
  const BorrowPage({super.key});

  @override
  State<BorrowPage> createState() => _BorrowPageState();
}

class _BorrowPageState extends State<BorrowPage> {
  int _amountCents = 300000;
  int _term = 6;
  Map<String, dynamic>? _quote;
  bool _quoting = false;
  bool _submitting = false;
  bool _agreed = false;
  bool _showSchedule = false;
  List<Map<String, dynamic>> _cards = [];
  int? _cardId;
  List<Map<String, dynamic>> _coupons = [];
  int? _couponId;
  String? _quoteError;
  late final String _idemKey = 'ln-${DateTime.now().millisecondsSinceEpoch}';

  int get _maxCents {
    final avail = session.availableCents;
    final cap = 5000000;
    final v = avail < cap ? avail : cap;
    return v < 50000 ? 50000 : v;
  }

  @override
  void initState() {
    super.initState();
    final avail = session.availableCents;
    _amountCents = avail >= 300000 ? 300000 : (avail >= 50000 ? (avail ~/ 10000) * 10000 : 50000);
    _loadAux();
    _doQuote();
  }

  Future<void> _loadAux() async {
    try {
      final results = await Future.wait([
        ApiClient.instance.get('/api/cards'),
        ApiClient.instance.get('/api/coupons', query: {'status': 'unused'}),
      ]);
      if (!mounted) return;
      final cards = ((results[0]['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final coupons = ((results[1]['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        _cards = cards;
        _cardId = cards.isNotEmpty ? cards.first['id'] as int : null;
        _coupons = coupons;
      });
    } catch (_) {}
  }

  Future<void> _doQuote() async {
    if (_quoting) return;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final data = await ApiClient.instance.post('/api/loans/quote', {
        'amountCents': _amountCents,
        'termMonths': _term,
        'couponId': _couponId,
      });
      if (!mounted) return;
      setState(() => _quote = Map<String, dynamic>.from(data as Map));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quote = null;
        _quoteError = e.toString();
      });
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _submit() async {
    if (_quote == null) return;
    if (!_agreed) {
      showToast(context, '请先阅读并同意《借款合同》', error: true);
      return;
    }
    if (_cardId == null) {
      showToast(context, '请先绑定收款银行卡', error: true);
      return;
    }
    setState(() => _submitting = true);
    try {
      final data = await ApiClient.instance.post(
        '/api/loans',
        {
          'quoteToken': _quote!['quoteToken'],
          'bankCardId': _cardId,
          'purpose': '日常消费',
          'contractSigned': true,
        },
        {'Idempotency-Key': _idemKey},
      );
      if (!mounted) return;
      await session.refreshProfile(silent: true);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => BorrowResultPage(loanId: data['id'] as int, initial: Map<String, dynamic>.from(data as Map))),
      );
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = (_quote?['schedule'] as List?) ?? [];
    return Scaffold(
      backgroundColor: UColors.bg,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 顶部金额区
                  Container(
                    decoration: const BoxDecoration(gradient: UColors.navyGradient),
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                              ),
                              const Expanded(
                                child: Text('确认借款', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
                              ),
                              IconButton(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpPage())),
                                icon: const Icon(Icons.help_outline, size: 20, color: Colors.white),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text('借款金额（元）', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(_amountCents, decimals: false),
                                style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w700, height: 1.05),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '可借额度 ${money(session.availableCents)} 元',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                          ),
                          const SizedBox(height: 20),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: UColors.gold,
                              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
                              thumbColor: Colors.white,
                              overlayColor: UColors.gold.withValues(alpha: 0.2),
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                            ),
                            child: Slider(
                              value: _amountCents.clamp(50000, _maxCents).toDouble(),
                              min: 50000,
                              max: _maxCents.toDouble(),
                              divisions: ((_maxCents - 50000) / 10000).clamp(1, 500).toInt(),
                              onChanged: (v) {
                                final cents = (v / 10000).round() * 10000;
                                if (cents != _amountCents) {
                                  setState(() => _amountCents = cents);
                                }
                              },
                              onChangeEnd: (_) => _doQuote(),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('¥500', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                                Text('¥${money(_maxCents, decimals: false)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [100000, 300000, 500000, 1000000].map((v) {
                                final selected = _amountCents == v;
                                final disabled = v > _maxCents;
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: GestureDetector(
                                      onTap: disabled
                                          ? null
                                          : () {
                                              setState(() => _amountCents = v);
                                              _doQuote();
                                            },
                                      child: Container(
                                        height: 36,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: selected ? UColors.gold.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: selected ? UColors.gold : Colors.transparent),
                                        ),
                                        child: Text(
                                          money(v, decimals: false),
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: disabled ? Colors.white.withValues(alpha: 0.25) : (selected ? UColors.goldLight : Colors.white.withValues(alpha: 0.8)),
                                            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                  // 表单区
                  Transform.translate(
                    offset: const Offset(0, -16),
                    child: Column(
                      children: [
                        UCard(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Text('借款期限', style: UText.h3),
                                  const Spacer(),
                                  if (_quote != null)
                                    Text('月供 ${money(_quote!['monthlyPaymentCents'] as num)} 元', style: UText.sub.copyWith(fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [3, 6, 12].map((t) {
                                  final selected = _term == t;
                                  return Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() => _term = t);
                                          _doQuote();
                                        },
                                        child: Container(
                                          height: 62,
                                          decoration: BoxDecoration(
                                            color: selected ? UColors.navy.withValues(alpha: 0.05) : UColors.bg,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: selected ? UColors.navy : Colors.transparent, width: 1.2),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text('$t 期', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: selected ? UColors.navy : UColors.text)),
                                              const SizedBox(height: 3),
                                              Text(t == 3 ? '短期周转' : t == 6 ? '灵活适中' : '压力更小', style: UText.tiny.copyWith(fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 费用明细
                        UCard(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              _feeRow('借款金额', '${money(_amountCents)} 元'),
                              _feeRow('综合年化利率（IRR）', _quote == null ? '--' : '${rate(_quote!['aprBp'] as num)}%', highlight: true),
                              _feeRow('总利息', _quote == null ? '--' : '${money(_quote!['totalInterestCents'] as num)} 元'),
                              if ((_quote?['couponDiscountCents'] as num? ?? 0) > 0)
                                _feeRow('优惠券抵扣', '-${money(_quote!['couponDiscountCents'] as num)} 元', success: true),
                              _feeRow('总还款', _quote == null ? '--' : '${money(_quote!['totalRepayCents'] as num)} 元', bold: true),
                              _feeRow('首期还款日', _quote == null ? '--' : dateShort(_quote!['firstDueDate'] as String?)),
                              const Divider(height: 22),
                              InkWell(
                                onTap: () => setState(() => _showSchedule = !_showSchedule),
                                child: Row(
                                  children: [
                                    Text('还款计划', style: UText.sub.copyWith(fontSize: 13)),
                                    const Spacer(),
                                    Text(_showSchedule ? '收起' : '展开', style: UText.tiny.copyWith(color: UColors.navy)),
                                    Icon(_showSchedule ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 18, color: UColors.textLight),
                                  ],
                                ),
                              ),
                              if (_showSchedule) ...[
                                const SizedBox(height: 10),
                                ...schedule.map((s) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        children: [
                                          SizedBox(width: 46, child: Text('${s['periodNo']}期', style: UText.tiny)),
                                          Expanded(child: Text(dateShort(s['dueDate'] as String?), style: UText.tiny)),
                                          Text('本金 ${money(s['principalCents'] as num)}', style: UText.tiny),
                                          const SizedBox(width: 10),
                                          Text('利息 ${money(s['interestCents'] as num)}', style: UText.tiny),
                                          const SizedBox(width: 10),
                                          SizedBox(width: 62, child: Text(money(s['totalCents'] as num), textAlign: TextAlign.right, style: UText.tiny.copyWith(color: UColors.text, fontWeight: FontWeight.w600))),
                                        ],
                                      ),
                                    )),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 收款卡 + 优惠券
                        UCard(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              InkWell(
                                onTap: () async {
                                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const CardsPage()));
                                  _loadAux();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.credit_card_rounded, size: 19, color: UColors.navy),
                                      const SizedBox(width: 10),
                                      Text('收款银行卡', style: UText.body.copyWith(fontSize: 14)),
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
                              const Divider(indent: 16, endIndent: 16, height: 1),
                              InkWell(
                                onTap: () async {
                                  final picked = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => const CouponsPage(selectMode: true)));
                                  if (picked != null) {
                                    setState(() => _couponId = picked == -1 ? null : picked);
                                    _doQuote();
                                  }
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.confirmation_num_outlined, size: 19, color: UColors.goldDark),
                                      const SizedBox(width: 10),
                                      Text('优惠券', style: UText.body.copyWith(fontSize: 14)),
                                      const Spacer(),
                                      Text(
                                        _couponId == null
                                            ? (_coupons.isEmpty ? '暂无可用' : '${_coupons.length} 张可用')
                                            : '已减 ${money(_quote?['couponDiscountCents'] ?? 0)} 元',
                                        style: UText.tiny.copyWith(color: _couponId != null ? UColors.danger : UColors.textLight),
                                      ),
                                      const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: Checkbox(
                                  value: _agreed,
                                  onChanged: (v) => setState(() => _agreed = v ?? false),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                  side: const BorderSide(color: UColors.textLight, width: 1.4),
                                  activeColor: UColors.navy,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: GestureDetector(
                                  onTap: () => setState(() => _agreed = !_agreed),
                                  child: Text.rich(
                                    TextSpan(
                                      style: UText.tiny,
                                      children: [
                                        const TextSpan(text: '我已阅读并同意 '),
                                        WidgetSpan(
                                          child: GestureDetector(
                                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'loan'))),
                                            child: Text('《借款合同》', style: UText.tiny.copyWith(color: UColors.navy)),
                                          ),
                                        ),
                                        WidgetSpan(
                                          child: GestureDetector(
                                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'credit'))),
                                            child: Text('《征信授权书》', style: UText.tiny.copyWith(color: UColors.navy)),
                                          ),
                                        ),
                                        const TextSpan(text: '，并承诺借款用于合法消费用途。'),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_quoteError != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                            child: Text(_quoteError!, style: UText.tiny.copyWith(color: UColors.danger)),
                          ),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 底部按钮
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: UColors.navy.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, -3))],
            ),
            child: SafeArea(
              top: false,
              child: UButton(
                text: _quote == null ? '试算中…' : '确认借款 ¥${money(_amountCents, decimals: false)}',
                onPressed: _quote == null ? null : _submit,
                loading: _submitting || _quoting,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool highlight = false, bool bold = false, bool success = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: UText.sub.copyWith(fontSize: 13)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: success ? UColors.success : (highlight ? UColors.goldDark : UColors.text),
            ),
          ),
        ],
      ),
    );
  }
}
