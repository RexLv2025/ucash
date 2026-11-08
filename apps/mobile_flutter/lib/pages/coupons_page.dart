import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class CouponsPage extends StatefulWidget {
  final bool selectMode;
  const CouponsPage({super.key, this.selectMode = false});

  @override
  State<CouponsPage> createState() => _CouponsPageState();
}

class _CouponsPageState extends State<CouponsPage> {
  int _tab = 0;
  List<Map<String, dynamic>> _list = [];
  List<Map<String, dynamic>> _available = [];
  bool _loading = true;

  static const _statusKeys = ['unused', 'used', 'expired'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiClient.instance.get('/api/coupons', query: {'status': _statusKeys[_tab]});
      if (!mounted) return;
      setState(() {
        _list = ((data['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _available = ((data['available'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _receive(int id) async {
    try {
      await ApiClient.instance.post('/api/coupons/$id/receive');
      if (mounted) showToast(context, '领取成功');
      _load();
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(
        title: '我的优惠券',
        trailing: widget.selectMode
            ? TextButton(
                onPressed: () => Navigator.pop(context, -1),
                child: const Text('不使用', style: TextStyle(fontSize: 13, color: UColors.textSub)),
              )
            : null,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  _seg(0, '待使用'),
                  _seg(1, '已使用'),
                  _seg(2, '已过期'),
                ],
              ),
            ),
          ),
          if (_tab == 0 && _available.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: UColors.gold.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: UColors.gold.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('可领取', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: UColors.goldDark)),
                  const SizedBox(height: 10),
                  ..._available.map((c) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text('${c['name']} · ${c['type'] == 'cash' ? '减 ${money(c['amountCents'] as num)} 元' : '降息 ${rate(c['rateOffBp'] as num)}%'}', style: UText.sub.copyWith(fontSize: 12))),
                            GestureDetector(
                              onTap: () => _receive(c['id'] as int),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(gradient: UColors.goldGradient, borderRadius: BorderRadius.circular(12)),
                                child: const Text('领取', style: TextStyle(fontSize: 11, color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const ULoading()
                : _list.isEmpty
                    ? const UEmpty(text: '暂无优惠券', sub: '参与活动可获得更多优惠', icon: Icons.confirmation_num_outlined)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: _list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final c = _list[i];
                          final cash = c['type'] == 'cash';
                          final usable = c['status'] == 'unused';
                          return Opacity(
                            opacity: usable ? 1 : 0.5,
                            child: UCard(
                              padding: EdgeInsets.zero,
                              onTap: widget.selectMode && usable ? () => Navigator.pop(context, c['id'] as int) : null,
                              child: Row(
                                children: [
                                  Container(
                                    width: 116,
                                    padding: const EdgeInsets.symmetric(vertical: 22),
                                    decoration: BoxDecoration(
                                      gradient: usable ? UColors.goldGradient : const LinearGradient(colors: [Color(0xFFB9C0CC), Color(0xFF9AA3B2)]),
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (cash) ...[
                                              const Text('¥', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                              Text(money(c['amountCents'] as num, decimals: false), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
                                            ] else ...[
                                              Text(rate(c['rateOffBp'] as num, digits: 0), style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1)),
                                              const Text('%', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(cash ? '满 ${money(c['minAmountCents'] as num, decimals: false)} 可用' : '首借降息', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10.5)),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(14),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(c['name'] as String? ?? '--', style: UText.body.copyWith(fontSize: 14, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${(c['termLimit'] as num? ?? 0) == 0 ? '不限期限' : '限 ${c['termLimit']} 期'} · 有效期至 ${dateShort(c['validTo'] as String?)}',
                                            style: UText.tiny,
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              UTag(text: usable ? '可使用' : c['status'] == 'used' ? '已使用' : '已过期', color: usable ? UColors.goldDark : UColors.textLight),
                                              const Spacer(),
                                              if (widget.selectMode && usable)
                                                const Text('选择', style: TextStyle(fontSize: 12, color: UColors.navy, fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _seg(int i, String text) {
    final active = _tab == i;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _tab = i);
          _load();
        },
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: active ? UColors.navy : Colors.transparent, borderRadius: BorderRadius.circular(9)),
          child: Text(text, style: TextStyle(fontSize: 13, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? Colors.white : UColors.textSub)),
        ),
      ),
    );
  }
}
