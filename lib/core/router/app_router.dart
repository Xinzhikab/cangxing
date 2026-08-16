import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fav_app/features/collections/presentation/pages/categories_page.dart';
import 'package:fav_app/features/collections/presentation/pages/category_articles_page.dart';
import 'package:fav_app/features/collections/presentation/pages/collections_page.dart';
import 'package:fav_app/features/collections/presentation/widgets/collections_shell.dart';
import 'package:fav_app/features/learning/presentation/pages/learning_page.dart';
import 'package:fav_app/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:fav_app/features/read/presentation/pages/article_chat_page.dart';
import 'package:fav_app/features/read/presentation/pages/read_page.dart';
import 'package:fav_app/features/save/presentation/pages/save_page.dart';
import 'package:fav_app/features/settings/data/providers/app_settings_provider.dart';
import 'package:fav_app/features/settings/presentation/pages/cookies_page.dart';
import 'package:fav_app/features/settings/presentation/pages/list_style_settings_page.dart';
import 'package:fav_app/features/settings/presentation/pages/llm_settings_page.dart';
import 'package:fav_app/features/settings/presentation/pages/settings_page.dart';
import 'package:fav_app/features/settings/presentation/pages/smtp_settings_page.dart';

class AppRouter {
  static GoRouter createRouter(WidgetRef ref) {
    return GoRouter(
      initialLocation: '/collections',
      redirect: (context, state) {
        final settings = ref.read(appSettingsProvider).valueOrNull;
        final onboardingNotCompleted =
            settings != null && !settings.hasCompletedOnboarding;
        final goingToOnboarding = state.matchedLocation == '/onboarding';

        if (onboardingNotCompleted && !goingToOnboarding) {
          return '/onboarding';
        }
        if (!onboardingNotCompleted && goingToOnboarding) {
          return '/collections';
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingPage(),
        ),
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) => CollectionsShell(
            navigationShell: navigationShell,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/collections',
                  builder: (context, state) => const CollectionsPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/learning',
                  builder: (context, state) => const LearningPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/categories',
                  builder: (context, state) => const CategoriesPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/settings',
                  builder: (context, state) => const SettingsPage(),
                  routes: [
                    GoRoute(
                      path: 'llm',
                      builder: (context, state) => const LlmSettingsPage(),
                    ),
                    GoRoute(
                      path: 'list-style',
                      builder: (context, state) =>
                          const ListStyleSettingsPage(),
                    ),
                    GoRoute(
                      path: 'cookies',
                      builder: (context, state) => const CookiesPage(),
                    ),
                    GoRoute(
                      path: 'smtp',
                      builder: (context, state) => const SmtpSettingsPage(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/categories/articles',
          builder: (context, state) {
            final args = state.extra as CategoryArticlesArgs;
            return CategoryArticlesPage(
              categoryPath: args.categoryPath,
              platform: args.platform,
              author: args.author,
              tag: args.tag,
            );
          },
        ),
        GoRoute(
          path: '/save',
          builder: (context, state) => SavePage(extra: state.extra),
        ),
        GoRoute(
          path: '/read/:id',
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            final fromLearning = state.extra as bool? ?? false;
            return ReadPage(id: id, fromLearning: fromLearning);
          },
          routes: [
            GoRoute(
              path: 'chat',
              builder: (context, state) => ArticleChatPage(
                collectionId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
