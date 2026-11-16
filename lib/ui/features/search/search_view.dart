import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        return Scaffold(
          appBar: AppBar(title: const Text('搜索')),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '输入片名或关键词',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onChanged: vm.onQueryChanged,
                  onSubmitted: (_) => vm.search(),
                ),
              ),
              Expanded(child: _body(vm)),
            ],
          ),
        );
      },
    );
  }

  Widget _body(SearchViewModel vm) {
    if (vm.keyword.isEmpty) {
      return const EmptyView(message: '输入关键词后搜索当前源');
    }
    if (vm.loading) return const LoadingView();
    if (vm.error != null) {
      return ErrorView(message: vm.error!, onRetry: vm.search);
    }
    if (vm.items.isEmpty) {
      return const EmptyView(message: '没有搜到相关内容');
    }
    return GridView.builder(
      controller: _controller,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
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
          item: item,
          onTap: () => context.push(
            '/detail/${Uri.encodeComponent(item.sourceKey)}/${Uri.encodeComponent(item.id)}',
          ),
        );
      },
    );
  }
}
