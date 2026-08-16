import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fav_app/core/constants/app_constants.dart';
import 'package:fav_app/core/router/app_router.dart';
import 'package:fav_app/core/theme/app_theme.dart';
import 'package:fav_app/features/learning/data/providers/review_notification_provider.dart';
import 'package:fav_app/features/save/data/providers/share_input_provider.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';

class FavApp extends ConsumerStatefulWidget {
  const FavApp({super.key});

  @override
  ConsumerState<FavApp> createState() => _FavAppState();
}

class _FavAppState extends ConsumerState<FavApp> {
  late final GoRouter _router;
  ValueListenable<String?>? _payloadNotifier;
  VoidCallback? _removeListener;

  @override
  void initState() {
    super.initState();
    _router = AppRouter.createRouter(ref);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shareSubscriptionProvider);
      _payloadNotifier = ref.read(notificationPayloadProvider);
      _listenPayload();
    });
  }

  void _listenPayload() {
    void handler() {
      final payload = _payloadNotifier?.value;
      if (payload != null && payload.isNotEmpty && mounted) {
        _router.go('/read/$payload');
      }
    }
    _payloadNotifier?.addListener(handler);
    _removeListener = () => _payloadNotifier?.removeListener(handler);
  }

  @override
  void dispose() {
    _removeListener?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.read(shareSubscriptionProvider);
    final settings = ref.watch(appSettingsProvider);
    return settings.when(
      loading: () => MaterialApp(
        title: '藏星',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => MaterialApp(
        title: '藏星',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        themeMode: ThemeMode.system,
        home: Scaffold(body: Center(child: Text('设置加载失败：$e'))),
      ),
      data: (s) {
        final useDynamic = s.dynamicColor;
        final mode = ThemeModeValue.fromInt(s.themeMode).toMaterial();
        return DynamicColorBuilder(
          builder: (lightDynamic, darkDynamic) {
            return MaterialApp.router(
              title: '藏星',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme(
                dynamicScheme: useDynamic ? lightDynamic : null,
              ),
              darkTheme: AppTheme.darkTheme(
                dynamicScheme: useDynamic ? darkDynamic : null,
              ),
              themeMode: mode,
              routerConfig: _router,
            );
          },
        );
      },
    );
  }
}
