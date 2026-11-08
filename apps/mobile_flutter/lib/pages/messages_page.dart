import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.get('/api/messages');
      if (!mounted) return;
      setState(() {
        _list = ((data['list'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context, e.toString(), error: true);
    }
  }

  Future<void> _readAll() async {
    await ApiClient.instance.post('/api/messages/read-all');
    _load();
  }

  IconData _icon(String type) {
    switch (type) {
      case 'loan':
        return Icons.account_balance_wallet_outlined;
      case 'repay':
        return Icons.payments_outlined;
      case 'risk':
        return Icons.shield_outlined;
      case 'marketing':
        return Icons.card_giftcard_rounded;
      default:
        return Icons.campaign_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '消息中心', trailing: TextButton(onPressed: _readAll, child: const Text('全部已读', style: TextStyle(fontSize: 12.5, color: UColors.textSub)))),
      body: _loading
          ? const ULoading()
          : _list.isEmpty
              ? const UEmpty(text: '暂无消息', sub: '放款、还款、额度变动通知将在这里展示', icon: Icons.notifications_none_rounded)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  itemCount: _list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final m = _list[i];
                    final read = m['read'] == true;
                    return UCard(
                      onTap: () async {
                        if (!read) await ApiClient.instance.post('/api/messages/${m['id']}/read');
                        if (!mounted) return;
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            title: Text(m['title'] as String? ?? '', style: UText.h3),
                            content: Text(m['content'] as String? ?? '', style: UText.sub.copyWith(height: 1.7)),
                            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了', style: TextStyle(color: UColors.navy)))],
                          ),
                        );
                        _load();
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(color: UColors.navy.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(11)),
                            child: Icon(_icon(m['type'] as String? ?? ''), size: 19, color: UColors.navy.withValues(alpha: 0.8)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: Text(m['title'] as String? ?? '', style: UText.body.copyWith(fontSize: 14, fontWeight: read ? FontWeight.w400 : FontWeight.w600))),
                                    if (!read)
                                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: UColors.danger, shape: BoxShape.circle)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(m['content'] as String? ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: UText.tiny.copyWith(height: 1.6)),
                                const SizedBox(height: 6),
                                Text(dateTimeShort(m['createdAt'] as String?), style: UText.tiny.copyWith(fontSize: 10)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
