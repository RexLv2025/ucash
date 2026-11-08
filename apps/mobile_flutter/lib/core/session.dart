import 'package:flutter/foundation.dart';

import '../core/api_client.dart';

/// 全局会话：登录态 + 用户资料 + 额度
class Session extends ChangeNotifier {
  static final Session instance = Session._();
  Session._();

  Map<String, dynamic>? me;
  bool bootstrapped = false;
  bool loading = false;

  bool get loggedIn => ApiClient.instance.token != null;

  String get name => (me?['user']?['name'] as String?) ?? '';
  String get phone => (me?['user']?['phone'] as String?) ?? '';
  String get inviteCode => (me?['user']?['inviteCode'] as String?) ?? '';
  Map<String, dynamic>? get credit => me?['credit'] as Map<String, dynamic>?;
  int get availableCents => (credit?['availableLimitCents'] as num?)?.toInt() ?? 0;
  int get totalLimitCents => (credit?['totalLimitCents'] as num?)?.toInt() ?? 0;
  int get usedLimitCents => (credit?['usedLimitCents'] as num?)?.toInt() ?? 0;
  String get creditStatus => (credit?['status'] as String?) ?? 'none';
  int? get rateBp => (credit?['interestRateBp'] as num?)?.toInt();
  bool get kycDone => (me?['profile']?['verified']?['contacts'] as bool?) ?? false;
  int get unread => (me?['counters']?['unreadMessages'] as num?)?.toInt() ?? 0;
  int get couponCount => (me?['counters']?['coupons'] as num?)?.toInt() ?? 0;

  Future<void> bootstrap() async {
    await ApiClient.instance.init();
    if (loggedIn) {
      try {
        await refreshProfile(silent: true);
      } catch (_) {
        await ApiClient.instance.setToken(null);
      }
    }
    bootstrapped = true;
    notifyListeners();
  }

  Future<void> refreshProfile({bool silent = false}) async {
    if (!loggedIn) return;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    try {
      final data = await ApiClient.instance.get('/api/me/profile');
      me = Map<String, dynamic>.from(data as Map);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> login(String phone, String code) async {
    final data = await ApiClient.instance.post('/api/auth/login', {'phone': phone, 'code': code, 'agreed': true});
    await ApiClient.instance.setToken(data['token'] as String);
    await refreshProfile(silent: true);
    notifyListeners();
  }

  Future<void> logout() async {
    await ApiClient.instance.setToken(null);
    me = null;
    notifyListeners();
  }

  void touch() => notifyListeners();
}

final session = Session.instance;
