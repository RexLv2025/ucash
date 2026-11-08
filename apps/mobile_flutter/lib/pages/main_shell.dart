import 'package:flutter/material.dart';

import '../core/session.dart';
import '../theme/app_theme.dart';
import 'bills_page.dart';
import 'home_page.dart';
import 'profile_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    session.refreshProfile(silent: true).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UColors.bg,
      body: IndexedStack(
        index: _index,
        children: const [HomePage(), BillsPage(), ProfilePage()],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: UColors.navy.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, -4))],
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 58,
            child: Row(
              children: [
                _tab(0, Icons.home_outlined, Icons.home_rounded, '首页'),
                _tab(1, Icons.receipt_long_outlined, Icons.receipt_long_rounded, '账单'),
                _tab(2, Icons.person_outline_rounded, Icons.person_rounded, '我的'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _tab(int index, IconData icon, IconData activeIcon, String label) {
    final active = _index == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _index = index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? activeIcon : icon, size: 24, color: active ? UColors.navy : UColors.textLight),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w400, color: active ? UColors.navy : UColors.textLight),
            ),
          ],
        ),
      ),
    );
  }
}
