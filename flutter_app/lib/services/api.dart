import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);
  @override
  String toString() => message;
}

String errText(Object? e) =>
    e is ApiException ? e.message : 'Something went wrong. Please try again.';

class Api {
  /// Android emulator reaches your PC at 10.0.2.2. For a real phone, set the
  /// server URL from the gear icon on the login screen (e.g. http://192.168.1.5:3000).
  static String baseUrl = const String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:3000');
  static String? token;
  static VoidCallback? onUnauthorized;

  static Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);
  static Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body: body ?? <String, dynamic>{});
  static Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);

  static Future<dynamic> _send(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    var uri = Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}/api$path');
    if (query != null && query.isNotEmpty) uri = uri.replace(queryParameters: query);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    final http.Response res;
    try {
      final enc = body == null ? null : jsonEncode(body);
      final Future<http.Response> f;
      switch (method) {
        case 'POST':
          f = http.post(uri, headers: headers, body: enc);
          break;
        case 'PUT':
          f = http.put(uri, headers: headers, body: enc);
          break;
        default:
          f = http.get(uri, headers: headers);
      }
      res = await f.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException('Server timed out. Check the server URL: $baseUrl');
    } on SocketException {
      throw ApiException('Cannot reach the server at $baseUrl. Is the backend running?');
    } on http.ClientException {
      throw ApiException('Cannot reach the server at $baseUrl. Is the backend running?');
    }
    dynamic data;
    try {
      data = res.body.isEmpty ? null : jsonDecode(res.body);
    } catch (_) {
      data = null;
    }
    if (res.statusCode >= 400) {
      if (res.statusCode == 401 && token != null) onUnauthorized?.call();
      final msg = data is Map && data['error'] != null
          ? data['error'].toString()
          : 'Request failed (${res.statusCode})';
      throw ApiException(msg, res.statusCode);
    }
    return data;
  }
}

/// Cached reference data (blood groups, organs, hospitals).
class Lookups {
  static Map<String, dynamic>? _cache;
  static Future<Map<String, dynamic>> get({bool refresh = false}) async {
    if (_cache == null || refresh) {
      _cache = Map<String, dynamic>.from(await Api.get('/lookups') as Map);
    }
    return _cache!;
  }
}

class Session extends ChangeNotifier {
  Map<String, dynamic>? user;

  String get role => (user?['role'] ?? '') as String;
  int? get hospitalId => user?['hospital_id'] as int?;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('server_url');
    if (saved != null && saved.isNotEmpty) Api.baseUrl = saved;
    Api.onUnauthorized = () {
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      logout();
    };
    final t = prefs.getString('token');
    if (t != null) {
      Api.token = t;
      try {
        user = Map<String, dynamic>.from(await Api.get('/me') as Map);
      } catch (_) {
        Api.token = null;
        await prefs.remove('token');
      }
    }
  }

  Future<void> setServerUrl(String url) async {
    Api.baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('server_url', Api.baseUrl);
  }

  Future<void> _accept(dynamic r) async {
    final m = Map<String, dynamic>.from(r as Map);
    Api.token = m['token'] as String;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', Api.token!);
    user = Map<String, dynamic>.from(m['user'] as Map);
    notifyListeners();
  }

  Future<void> login(String email, String password) async =>
      _accept(await Api.post('/auth/login', {'email': email, 'password': password}));

  Future<void> register(Map<String, dynamic> body) async =>
      _accept(await Api.post('/auth/register', body));

  Future<void> refreshProfile() async {
    user = Map<String, dynamic>.from(await Api.get('/me') as Map);
    notifyListeners();
  }

  Future<void> logout() async {
    Api.token = null;
    user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }
}

final session = Session();
