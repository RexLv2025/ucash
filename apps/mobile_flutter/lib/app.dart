import 'package:flutter/material.dart';

import 'core/session.dart';
import 'pages/login_page.dart';
import 'pages/main_shell.dart';
import 'theme/app_theme.dart';

class UcashApp extends StatelessWidget {
  const UcashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UCash',
      debugShowCheckedModeBanner: false,
      theme: UTheme.build(),
      home: const RootGate(),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (!session.bootstrapped) {
          return const Scaffold(
            backgroundColor: UColors.navy,
            body: Center(child: CircularProgressIndicator(color: UColors.gold)),
          );
        }
        return session.loggedIn ? const MainShell() : const LoginPage();
      },
    );
  }
}
