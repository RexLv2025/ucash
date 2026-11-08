import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiException implements Exception {
  final int code;
  final String message;
  ApiException(this.code, this.message);
  @override
  String toString() => message;

  bool get isAuth => code == 1002;
}

class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _kBaseUrl = 'ucash.baseUrl';
  static const _kToken = 'ucash.token';
  static const _envBase = String.fromEnvironment('API_BASE');

  String? _token;
  String? _baseUrl;
  final http.Client _client = http.Client();

  String get baseUrl => _baseUrl ?? (_envBase.isNotEmpty ? _envBase : _defaultBaseUrl());

  static String _defaultBaseUrl() {
    if (kIsWeb) return 'http://localhost:4000';
    if (Platform.isAndroid) return 'http://10.0.2.2:4000';
    return 'http://localhost:4000';
  }

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString(_kToken);
    _baseUrl = sp.getString(_kBaseUrl);
  }

  String? get token => _token;

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kBaseUrl, _baseUrl!);
  }

  Future<void> setToken(String? token) async {
    _token = token;
    final sp = await SharedPreferences.getInstance();
    if (token == null) {
      await sp.remove(_kToken);
    } else {
      await sp.setString(_kToken, token);
    }
  }

  Map<String, String> _headersWith([Map<String, String>? extra]) => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
        ...?extra,
      };

  Map<String, String> get _headers => _headersWith();

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final uri = Uri.parse('${baseUrl}$path').replace(
      queryParameters: query?.map((k, v) => MapEntry(k, '$v')),
    );
    final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    return _unwrap(res);
  }

  Future<dynamic> post(String path, [Object? body, Map<String, String>? extraHeaders]) async {
    final res = await _client
        .post(Uri.parse('${baseUrl}$path'), headers: _headersWith(extraHeaders), body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 25));
    return _unwrap(res);
  }

  Future<dynamic> patch(String path, [Object? body]) async {
    final res = await _client
        .patch(Uri.parse('${baseUrl}$path'), headers: _headers, body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 20));
    return _unwrap(res);
  }

  Future<dynamic> delete(String path) async {
    final res = await _client.delete(Uri.parse('${baseUrl}$path'), headers: _headers).timeout(const Duration(seconds: 20));
    return _unwrap(res);
  }

  dynamic _unwrap(http.Response res) {
    if (res.body.isEmpty) return null;
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is Map && body['code'] == 0) return body['data'];
    final code = body is Map ? (body['code'] as int? ?? 9001) : 9001;
    final msg = body is Map ? (body['message'] as String? ?? '请求失败') : '请求失败';
    throw ApiException(code, msg);
  }
}
