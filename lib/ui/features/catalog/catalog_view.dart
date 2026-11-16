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

  @override
  void initState() {
    super.initState();
    widget.viewModel.load();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (_controller.position.extentAfter < 600) {
      widget.viewModel.loadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openDetail(VodItem item) {
    context.push('/detail/${Uri.encodeComponent(item.sourceKey)}/${Uri.encodeComponent(item.id)}');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final sourceName = vm.source?.name ?? '未选择源';
        return Scaffold(
          appBar: AppBar(
            title: const Text('源盒'),
            actions: [
              TextButton(
                onPressed: () => context.go('/sources'),
                child: Text(sourceName, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          body: Column(
            children: [
              if (vm.categories.isNotEmpty)
                SizedBox(
                  height: 48,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('推荐'),
                          selected: vm.selectedCategoryId == null,
                          onSelected: (_) => vm.selectCategory(null),
                        ),
                      ),
                      for (final category in vm.categories)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(category.name),
                            selected: vm.selectedCategoryId == category.id,
                            onSelected: (_) => vm.selectCategory(category.id),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(child: _body(vm)),
            ],
          ),
        );
      },
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
