import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/history_repository.dart';
import 'data/repositories/source_repository.dart';
import 'domain/models/playable.dart';
import 'ui/app_shell.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/catalog/catalog_view.dart';
import 'ui/features/catalog/catalog_view_model.dart';
import 'ui/features/detail/detail_view.dart';
import 'ui/features/player/player_view.dart';
import 'ui/features/profile/history_view.dart';
import 'ui/features/profile/profile_view.dart';
import 'ui/features/profile/profile_view_model.dart';
import 'ui/features/search/search_view.dart';
import 'ui/features/search/search_view_model.dart';
import 'ui/features/sources/sources_view.dart';
import 'ui/features/sources/sources_view_model.dart';

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
          path: '/detail/:sourceKey/:id',
          builder: (context, state) {
            final sourceKey =
                Uri.decodeComponent(state.pathParameters['sourceKey'] ?? '');
            final id = Uri.decodeComponent(state.pathParameters['id'] ?? '');
            return DetailView(
              key: ValueKey('detail_${sourceKey}_$id'),
              catalogRepository: _catalogRepository,
              historyRepository: _historyRepository,
              sourceKey: sourceKey,
              vodId: id,
            );
          },
        ),
        GoRoute(
          path: '/player',
          builder: (context, state) {
            final playable = state.extra;
            if (playable is! Playable) {
              return const Scaffold(body: Center(child: Text('没有可播放的地址')));
            }
            return PlayerView(
              playable: playable,
              historyRepository: _historyRepository,
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
