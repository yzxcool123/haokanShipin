import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/vod_item.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/vod_card.dart';
import 'catalog_view_model.dart';

class CatalogView extends StatefulWidget {
  const CatalogView({super.key, required this.viewModel});

  final CatalogViewModel viewModel;

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  final _controller = ScrollController();
  final _categoryScrollController = ScrollController();
  final _recommendKey = GlobalKey();
  final _categoryKeys = <String, GlobalKey>{};
  String? _centeredToken;
  bool _animateNextCenter = false;

  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
    _controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant CatalogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      _centeredToken = null;
    }
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 600) {
      widget.viewModel.loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String? categoryId) {
    if (categoryId == null) return _recommendKey;
    return _categoryKeys.putIfAbsent(categoryId, GlobalKey.new);
  }

  void _maybeCenterSelected(CatalogViewModel vm) {
    if (vm.categories.isEmpty) return;
    final token = '${vm.source?.key ?? ''}|${vm.selectedCategoryId ?? ''}';
    if (token == _centeredToken) return;
    _centeredToken = token;
    final animate = _animateNextCenter;
    _animateNextCenter = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerSelected(vm.selectedCategoryId, animate: animate);
    });
  }

  void _centerSelected(String? selectedId,
      {required bool animate, int attempt = 0}) {
    if (!mounted) return;
    final itemContext = _keyFor(selectedId).currentContext;
    if (itemContext == null || !_categoryScrollController.hasClients) {
      if (attempt < 8) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _centerSelected(selectedId, animate: animate, attempt: attempt + 1);
        });
      }
      return;
    }
    Scrollable.ensureVisible(
      itemContext,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 280) : Duration.zero,
      curve: Curves.easeOutCubic,
    );
  }

  void _onSelectCategory(String? id) {
    if (widget.viewModel.selectedCategoryId == id) {
      _centerSelected(id, animate: true);
      return;
    }
    _animateNextCenter = true;
    widget.viewModel.selectCategory(id);
  }

  void _openDetail(VodItem item) {
    context.push(
        '/detail/${Uri.encodeComponent(item.sourceKey)}/${Uri.encodeComponent(item.id)}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final sourceName = vm.sourceDisplayName;
        final sourceStyle = vm.isCurrentUnavailable
            ? TextStyle(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.55),
              )
            : null;
        _maybeCenterSelected(vm);
        return Scaffold(
          appBar: AppBar(
            title: const Text('影视'),
            actions: [
              TextButton(
                onPressed: () => context.push('/sources'),
                child: Text(
                  sourceName,
                  overflow: TextOverflow.ellipsis,
                  style: sourceStyle,
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              if (vm.refreshing && vm.items.isNotEmpty)
                const LinearProgressIndicator(minHeight: 2),
              if (vm.categories.isNotEmpty) _categoryBar(vm),
              Expanded(child: _body(vm)),
            ],
          ),
        );
      },
    );
  }

  Widget _categoryBar(CatalogViewModel vm) {
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        controller: _categoryScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _CategoryTab(
              key: _keyFor(null),
              label: '推荐',
              selected: vm.selectedCategoryId == null,
              onTap: () => _onSelectCategory(null),
            ),
            for (final category in vm.categories)
              _CategoryTab(
                key: _keyFor(category.id),
                label: category.name,
                selected: vm.selectedCategoryId == category.id,
                onTap: () => _onSelectCategory(category.id),
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(CatalogViewModel vm) {
    if (vm.loading && vm.items.isEmpty) {
      return const LoadingView();
    }
    if (vm.error != null && vm.items.isEmpty) {
      return ErrorView(message: vm.error!, onRetry: vm.load);
    }
    if (vm.items.isEmpty) {
      return const EmptyView(message: '当前源没有列表数据');
    }
    return RefreshIndicator(
      onRefresh: vm.load,
      child: GridView.builder(
        controller: _controller,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          childAspectRatio: 0.58,
        ),
        itemCount: vm.items.length + (vm.loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= vm.items.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final item = vm.items[index];
          return VodCard(item: item, onTap: () => _openDetail(item));
        },
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              fontSize: selected ? 18 : 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              height: 1.2,
              color: onSurface.withValues(alpha: selected ? 1 : 0.55),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}
