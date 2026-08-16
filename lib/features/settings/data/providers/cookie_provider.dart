import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SiteCookie {
  final String domain;
  final String cookie;

  const SiteCookie({
    required this.domain,
    required this.cookie,
  });

  SiteCookie copyWith({
    String? domain,
    String? cookie,
  }) {
    return SiteCookie(
      domain: domain ?? this.domain,
      cookie: cookie ?? this.cookie,
    );
  }
}

class CookieNotifier extends AsyncNotifier<List<SiteCookie>> {
  static const String _kLegacyKey = 'cookiejar_entries';
  static const String _kSecKey = 'sec_cookiejar_entries';
  static FlutterSecureStorage? _secureCache;
  FlutterSecureStorage get _secure => _secureCache ??= const FlutterSecureStorage();

  @override
  Future<List<SiteCookie>> build() async {
    final prefs = await SharedPreferences.getInstance();
    final legacy = prefs.getString(_kLegacyKey);
    if (legacy != null && legacy.isNotEmpty) {
      await _secure.write(key: _kSecKey, value: legacy);
      await prefs.remove(_kLegacyKey);
    }

    final s = await _secure.read(key: _kSecKey);
    if (s == null || s.isEmpty) return const [];
    final List list = jsonDecode(s);
    return list
        .map((e) => SiteCookie(domain: e['d'], cookie: e['c']))
        .toList(growable: false);
  }

  Future<void> _persist() async {
    final data = state.valueOrNull ?? const [];
    await _secure.write(
      key: _kSecKey,
      value: jsonEncode(data.map((c) => {'d': c.domain, 'c': c.cookie}).toList()),
    );
  }

  Future<void> upsert(SiteCookie old, SiteCookie next) async {
    final current = state.valueOrNull ?? const [];
    final exists = current.any((c) => c == old || c.domain == old.domain);
    final List<SiteCookie> updated;
    if (!exists) {
      updated = [...current, next];
    } else {
      updated = current
          .map((c) => c == old || c.domain == old.domain ? next : c)
          .toList(growable: false);
    }
    state = AsyncValue.data(updated);
    await _persist();
  }

  Future<void> remove(String domain) async {
    final current = state.valueOrNull ?? const [];
    final updated = current.where((c) => c.domain != domain).toList(growable: false);
    state = AsyncValue.data(updated);
    await _persist();
  }

  static bool shouldInjectCookie({
    required Uri pageUri,
    required SiteCookie cookie,
  }) {
    final pageHost = pageUri.host.toLowerCase();
    var cookieDomain = cookie.domain.toLowerCase().trim();
    if (cookieDomain.isEmpty) return false;
    cookieDomain = cookieDomain.replaceAll('www.', '');
    if (cookieDomain.isEmpty) return false;
    final exactMatch = cookieDomain == pageHost;
    final wildcardMatch = cookieDomain.startsWith('.') &&
        pageHost.endsWith(cookieDomain);
    bool match = exactMatch || wildcardMatch;
    if (match && !exactMatch && cookieDomain.length < 4) {
      match = false;
    }
    return match;
  }

  String matchForUrl(String url) {
    try {
      final current = state.valueOrNull ?? const [];
      final pageUri = Uri.parse(url);
      final hits = current.where((c) {
        return shouldInjectCookie(pageUri: pageUri, cookie: c);
      }).toList();
      if (hits.isEmpty) return '';
      return hits
          .map((c) => c.cookie.trim().replaceAll(RegExp(r';\s*$'), ''))
          .join('; ');
    } catch (_) {
      return '';
    }
  }
}

final cookieListProvider =
    AsyncNotifierProvider<CookieNotifier, List<SiteCookie>>(
  CookieNotifier.new,
);
