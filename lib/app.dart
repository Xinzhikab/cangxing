import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
    // Monet 动态取色：Android 12+ 取壁纸配色；可在设置中关闭，回退种子色
    final useDynamic = ref.watch(
          appSettingsProvider.select((s) => s.valueOrNull?.dynamicColor),
        ) ??
        true;
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
          themeMode: ThemeMode.system,
          routerConfig: _router,
        );
      },
    );
  }
}
