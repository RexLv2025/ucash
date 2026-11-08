import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/session.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'agreements_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _showDev = false;

  Future<void> _setPassword() async {
    final pwd = TextEditingController();
    final old = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('设置登录密码', style: UText.h3),
                const SizedBox(height: 16),
                UField(label: '原密码（首次设置可留空）', hint: '请输入原密码', controller: old, obscure: true),
                const SizedBox(height: 14),
                UField(label: '新密码', hint: '6-20 位，建议字母 + 数字', controller: pwd, obscure: true),
                const SizedBox(height: 20),
                UButton(
                  text: '确认',
                  onPressed: () async {
                    if (pwd.text.length < 6) {
                      showToast(ctx, '密码至少 6 位', error: true);
                      return;
                    }
                    try {
                      await ApiClient.instance.post('/api/auth/password', {'oldPassword': old.text, 'password': pwd.text});
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) showToast(ctx, e.toString(), error: true);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    pwd.dispose();
    old.dispose();
    if (ok == true && mounted) showToast(context, '密码已设置');
  }

  Future<void> _editBaseUrl() async {
    final c = TextEditingController(text: ApiClient.instance.baseUrl);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('服务端地址', style: UText.h3),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              decoration: const InputDecoration(hintText: 'http://192.168.1.10:4000', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Text('真机调试请填写电脑局域网 IP；Android 模拟器使用 10.0.2.2', style: UText.tiny),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              await ApiClient.instance.setBaseUrl(c.text.isEmpty ? 'http://10.0.2.2:4000' : c.text);
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: const Text('保存', style: TextStyle(color: UColors.navy, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    c.dispose();
    if (ok == true && mounted) {
      showToast(context, '已保存，重新登录后生效');
      setState(() {});
    }
  }

  Future<void> _closeAccount() async {
    final ok = await showConfirm(context, title: '注销账户', content: '注销后账户将无法登录，需结清全部借款后方可注销。确认继续？', confirmText: '确认注销');
    if (!ok) return;
    try {
      await ApiClient.instance.post('/api/auth/close');
      await session.logout();
      if (mounted) showToast(context, '账户已注销');
    } catch (e) {
      if (mounted) showToast(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      appBar: UNavBar(title: '设置'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          UCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _item(Icons.lock_outline_rounded, '登录密码', onTap: _setPassword),
                const Divider(height: 1, indent: 52),
                _item(Icons.phone_iphone_rounded, '手机号', trailing: session.phone, onTap: () => showToast(context, '如需更换手机号请联系客服')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          UCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _item(Icons.description_outlined, '隐私政策', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'privacy')))),
                const Divider(height: 1, indent: 52),
                _item(Icons.shield_outlined, '个人信息授权书', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'personalInfo')))),
                const Divider(height: 1, indent: 52),
                _item(Icons.verified_outlined, '征信授权书', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AgreementsPage(type: 'credit')))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          UCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _showDev = !_showDev),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                    child: Row(
                      children: [
                        const Icon(Icons.settings_suggest_outlined, size: 20, color: UColors.navy),
                        const SizedBox(width: 12),
                        Text('开发者选项', style: UText.body.copyWith(fontSize: 14)),
                        const Spacer(),
                        Text(ApiClient.instance.baseUrl, style: UText.tiny.copyWith(fontSize: 11)),
                        const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
                      ],
                    ),
                  ),
                ),
                if (_showDev) ...[
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('服务端地址（用于真机联调）', style: UText.tiny),
                        const SizedBox(height: 8),
                        UButton(text: '修改服务端地址', small: true, ghost: true, onPressed: _editBaseUrl),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          UCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _item(Icons.info_outline_rounded, '关于 UCash', trailing: 'v2.4.0', onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'UCash',
                    applicationVersion: '2.4.0 (build 24)',
                    applicationLegalese: '© 2026 UCash. 持牌小额贷款服务。\n理性借贷，量力而行。',
                  );
                }),
                const Divider(height: 1, indent: 52),
                _item(Icons.cleaning_services_outlined, '清除缓存', trailing: '12.6 MB', onTap: () => showToast(context, '缓存已清除')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          UButton(
            text: '退出登录',
            ghost: true,
            onPressed: () async {
              final ok = await showConfirm(context, title: '退出登录', content: '退出后需重新验证手机号登录');
              if (ok) await session.logout();
            },
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _closeAccount,
              child: Text('注销账户', style: UText.tiny.copyWith(color: UColors.danger, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 8),
          Center(child: Text('UCash v2.4.0 · 综合年化利率 9%–24%', style: UText.tiny.copyWith(fontSize: 10))),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String label, {String? trailing, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        child: Row(
          children: [
            Icon(icon, size: 20, color: UColors.navy),
            const SizedBox(width: 12),
            Text(label, style: UText.body.copyWith(fontSize: 14)),
            const Spacer(),
            if (trailing != null) Text(trailing, style: UText.tiny),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: UColors.textLight),
          ],
        ),
      ),
    );
  }
}
