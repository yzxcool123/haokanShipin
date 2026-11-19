import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/cover_image.dart';
import '../../core/widgets/status_views.dart';
import '../../core/widgets/vod_card.dart';
import 'search_view_model.dart';

class SearchView extends StatefulWidget {
  const SearchView({super.key, required this.viewModel});

  final SearchViewModel viewModel;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final _controller = ScrollController();
  final _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.extentAfter < 600) {
        widget.viewModel.loadMore();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _searchFromHistory(String keyword) async {
    _queryController.value = TextEditingValue(
      text: keyword,
      selection: TextSelection.collapsed(offset: keyword.length),
    );
    await widget.viewModel.submit(keyword);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            appBar: AppBar(title: const Text('搜索')),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: TextField(
                    controller: _queryController,
                    decoration: InputDecoration(
                      hintText: '输入片名或关键词',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: vm.onQueryChanged,
                    onSubmitted: vm.submit,
                  ),
                ),
                Expanded(child: _body(vm)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _body(SearchViewModel vm) {
    if (vm.keyword.isEmpty) {
      if (vm.history.isEmpty) {
        return const EmptyView(message: '输入关键词后搜索当前源');
      }
      return _HistoryList(
        history: vm.history,
        onSelect: _searchFromHistory,
        onClear: vm.clearHistory,
      );
    }
    if (vm.loading) return const LoadingView();
    if (vm.error != null) {
      return ErrorView(message: vm.error!, onRetry: vm.search);
    }
    if (vm.items.isEmpty) {
      return const EmptyView(message: '没有搜到相关内容');
    }
    final cacheWidth = CoverImage.cacheWidthForGrid(context);
    return GridView.builder(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      addAutomaticKeepAlives: false,
      addSemanticIndexes: false,
      cacheExtent: 400,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.58,
      ),
      itemCount: vm.items.length,
      itemBuilder: (context, index) {
        final item = vm.items[index];
        return VodCard(
          key: ValueKey('${item.sourceKey}_${item.id}'),
          item: item,
          cacheWidth: cacheWidth,
          onTap: () => context.push(
            '/detail/${Uri.encodeComponent(item.sourceKey)}/${Uri.encodeComponent(item.id)}',
          ),
        );
      },
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.history,
    required this.onSelect,
    required this.onClear,
  });

  final List<String> history;
  final ValueChanged<String> onSelect;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
          child: Row(
            children: [
              Text(
                '搜索历史',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              IconButton(
                tooltip: '清空搜索历史',
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final keyword in history)
              ActionChip(
                label: Text(keyword),
                onPressed: () => onSelect(keyword),
              ),
          ],
        ),
      ],
    );
  }
}
