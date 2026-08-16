import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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

class CookieNotifier extends Notifier<List<SiteCookie>> {
  static const String _kKey = 'cookiejar_entries';
  Future<void>? _pendingLoad;

  @override
  List<SiteCookie> build() {
    _pendingLoad ??= _load();
    return [];
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kKey);
    if (s == null) return;
    final List list = jsonDecode(s);
    state = list
        .map((e) => SiteCookie(domain: e['d'], cookie: e['c']))
        .toList(growable: false);
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _kKey,
      jsonEncode(state.map((c) => {'d': c.domain, 'c': c.cookie}).toList()),
    );
  }

  Future<void> upsert(SiteCookie old, SiteCookie next) async {
    // 等待初次加载完成，避免在空状态上写入后被异步加载结果覆盖
    await _pendingLoad;
    final exists = state.any((c) => c == old || c.domain == old.domain);
    if (!exists) {
      state = [...state, next];
    } else {
      state = state
          .map((c) => c == old || c.domain == old.domain ? next : c)
          .toList(growable: false);
    }
    await _persist();
  }

  Future<void> remove(String domain) async {
    await _pendingLoad;
    state = state.where((c) => c.domain != domain).toList(growable: false);
    await _persist();
  }

  String matchForUrl(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      final hits = state.where((c) {
        final d = c.domain.toLowerCase().trim().replaceAll('www.', '');
        return host.contains(d);
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
    NotifierProvider<CookieNotifier, List<SiteCookie>>(CookieNotifier.new);
