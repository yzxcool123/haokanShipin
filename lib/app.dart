import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'data/repositories/catalog_repository.dart';
import 'data/repositories/source_repository.dart';
import 'domain/models/playable.dart';
import 'ui/app_shell.dart';
import 'ui/core/app_theme.dart';
import 'ui/features/catalog/catalog_view.dart';
import 'ui/features/catalog/catalog_view_model.dart';
import 'ui/features/detail/detail_view.dart';
import 'ui/features/player/player_view.dart';
import 'ui/features/search/search_view.dart';
import 'ui/features/search/search_view_model.dart';
import 'ui/features/sources/sources_view.dart';
import 'ui/features/sources/sources_view_model.dart';

class HaoKanShiPinApp extends StatefulWidget {
  const HaoKanShiPinApp({super.key, required this.sourceRepository});

  final SourceRepository sourceRepository;

  @override
  State<HaoKanShiPinApp> createState() => _HaoKanShiPinAppState();
}

class _HaoKanShiPinAppState extends State<HaoKanShiPinApp> {
  late final CatalogRepository _catalogRepository;
  late final CatalogViewModel _catalogViewModel;
  late final SearchViewModel _searchViewModel;
  late final SourcesViewModel _sourcesViewModel;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _catalogRepository = CatalogRepository(sourceRepository: widget.sourceRepository);
    _catalogViewModel = CatalogViewModel(
      catalogRepository: _catalogRepository,
      sourceRepository: widget.sourceRepository,
    );
    _searchViewModel = SearchViewModel(catalogRepository: _catalogRepository);
    _sourcesViewModel = SourcesViewModel(sourceRepository: widget.sourceRepository);
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
                  builder: (context, state) => CatalogView(viewModel: _catalogViewModel),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/search',
                  builder: (context, state) => SearchView(viewModel: _searchViewModel),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: '/sources',
                  builder: (context, state) => SourcesView(viewModel: _sourcesViewModel),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/detail/:sourceKey/:id',
          builder: (context, state) {
            final sourceKey = Uri.decodeComponent(state.pathParameters['sourceKey'] ?? '');
            final id = Uri.decodeComponent(state.pathParameters['id'] ?? '');
            return DetailView(
              key: ValueKey('detail_${sourceKey}_$id'),
              catalogRepository: _catalogRepository,
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
            return PlayerView(playable: playable);
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
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '好看视频',
      theme: AppTheme.dark(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
