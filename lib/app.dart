import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/favorite_repository.dart';
import 'data/repositories/history_repository.dart';
import 'data/repositories/offline_cache_repository.dart';
import 'data/repositories/source_repository.dart';
import 'domain/models/playable.dart';
import 'ui/app_shell.dart';
import 'ui/core/app_theme.dart';
import 'ui/core/widgets/cover_hero.dart';
import 'ui/features/catalog/catalog_view.dart';
import 'ui/features/catalog/catalog_view_model.dart';
import 'ui/features/detail/detail_view.dart';
import 'ui/features/player/player_view.dart';
import 'ui/features/profile/about_view.dart';
import 'ui/features/profile/downloads_view.dart';
import 'ui/features/profile/favorites_view.dart';
import 'ui/features/profile/history_view.dart';
import 'ui/features/profile/profile_view.dart';
import 'ui/features/profile/settings_view.dart';
import 'ui/features/profile/profile_view_model.dart';
import 'ui/features/search/search_view.dart';
import 'ui/features/search/search_view_model.dart';
import 'ui/features/sources/sources_view.dart';
import 'ui/features/sources/sources_view_model.dart';


String _decodeRouteParam(String? value) {
  final raw = value ?? '';
  if (raw.isEmpty || !raw.contains('%')) return raw;
  try {
    return Uri.decodeComponent(raw);
  } on ArgumentError {
    // go_router 可能已经解码过；源 key / 影片 id 里若带不完整的 %，不能再解一次。
    return raw;
  } on FormatException {
    return raw;
  }
}


class HaoKanShiPinApp extends StatefulWidget {
  const HaoKanShiPinApp({
    super.key,
    required this.sourceRepository,
    required this.prefs,
  });

  final SourceRepository sourceRepository;
  final SharedPreferences prefs;

  @override
  State<HaoKanShiPinApp> createState() => _HaoKanShiPinAppState();
}

class _HaoKanShiPinAppState extends State<HaoKanShiPinApp> {
  late final CatalogRepository _catalogRepository;
  late final HistoryRepository _historyRepository;
  late final FavoriteRepository _favoriteRepository;
  late final OfflineCacheRepository _offlineCacheRepository;
  late final CatalogViewModel _catalogViewModel;
  late final SearchViewModel _searchViewModel;
  late final SourcesViewModel _sourcesViewModel;
  late final ProfileViewModel _profileViewModel;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _catalogRepository = CatalogRepository(
      sourceRepository: widget.sourceRepository,
      prefs: widget.prefs,
    );
    _historyRepository = HistoryRepository(
      prefs: widget.prefs,
      sourceRepository: widget.sourceRepository,
    );
    _favoriteRepository = FavoriteRepository(
      prefs: widget.prefs,
      sourceRepository: widget.sourceRepository,
    );
    _offlineCacheRepository = OfflineCacheRepository(
      prefs: widget.prefs,
      sourceRepository: widget.sourceRepository,
      catalogRepository: _catalogRepository,
    );
    _catalogViewModel = CatalogViewModel(
      catalogRepository: _catalogRepository,
      sourceRepository: widget.sourceRepository,
    );
    _searchViewModel = SearchViewModel(
      catalogRepository: _catalogRepository,
      prefs: widget.prefs,
    );
    _sourcesViewModel =
        SourcesViewModel(sourceRepository: widget.sourceRepository);
    _profileViewModel = ProfileViewModel(
      historyRepository: _historyRepository,
      favoriteRepository: _favoriteRepository,
      offlineCacheRepository: _offlineCacheRepository,
      sourceRepository: widget.sourceRepository,
    );
    _router = _createRouter();
  }

  GoRouter _createRouter() {
    return GoRouter(
      initialLocation: '/home',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) {
            return AppShell(navigationShell: navigationShell);
          },
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/home',
                  builder: (context, state) =>
                      CatalogView(viewModel: _catalogViewModel),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/search',
                  builder: (context, state) =>
                      SearchView(viewModel: _searchViewModel),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/me',
                  builder: (context, state) =>
                      ProfileView(viewModel: _profileViewModel),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/sources',
          builder: (context, state) =>
              SourcesView(viewModel: _sourcesViewModel),
        ),
        GoRoute(
          path: '/history',
          builder: (context, state) =>
              HistoryView(historyRepository: _historyRepository),
        ),
        GoRoute(
          path: '/favorites',
          builder: (context, state) =>
              FavoritesView(favoriteRepository: _favoriteRepository),
        ),
        GoRoute(
          path: '/downloads',
          builder: (context, state) => DownloadsView(
            offlineCacheRepository: _offlineCacheRepository,
            historyRepository: _historyRepository,
          ),
        ),
        GoRoute(
          path: '/about',
          builder: (context, state) => const AboutView(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => SettingsView(
            sourceRepository: widget.sourceRepository,
          ),
        ),
        GoRoute(
          path: '/detail/:sourceKey/:id',
          builder: (context, state) {
            final sourceKey =
                _decodeRouteParam(state.pathParameters['sourceKey']);
            final id = _decodeRouteParam(state.pathParameters['id']);
            return DetailView(
              key: ValueKey('detail_${sourceKey}_$id'),
              catalogRepository: _catalogRepository,
              historyRepository: _historyRepository,
              favoriteRepository: _favoriteRepository,
              offlineCacheRepository: _offlineCacheRepository,
              sourceKey: sourceKey,
              vodId: id,
              preview: coverHeroInfoOf(state.extra),
            );
          },
        ),
        GoRoute(
          path: '/player',
          builder: (context, state) {
            final extra = state.extra;
            final session = extra is PlayerSession
                ? extra
                : extra is Playable
                    ? PlayerSession(playable: extra)
                    : null;
            if (session == null) {
              return const Scaffold(body: Center(child: Text('没有可播放的地址')));
            }
            return PlayerView(
              session: session,
              historyRepository: _historyRepository,
              offlineCacheRepository: _offlineCacheRepository,
              catalogRepository: _catalogRepository,
            );
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    _catalogViewModel.dispose();
    _searchViewModel.dispose();
    _sourcesViewModel.dispose();
    _profileViewModel.dispose();
    _historyRepository.dispose();
    _favoriteRepository.dispose();
    _offlineCacheRepository.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '蓝果短剧',
      theme: AppTheme.dark(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
