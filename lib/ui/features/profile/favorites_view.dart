import 'package:flutter/material.dart';
import '../../../data/repositories/favorite_repository.dart';
import '../../../domain/models/favorite_item.dart';
import '../../core/widgets/cover_hero.dart';
import '../../core/widgets/cover_image.dart';

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key, required this.favoriteRepository});

  final FavoriteRepository favoriteRepository;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: favoriteRepository,
      builder: (context, _) {
        final items = favoriteRepository.items;
        return Scaffold(
          appBar: AppBar(title: const Text('收藏')),
          body: items.isEmpty
              ? Center(
                  child: Text(
                    '还没有收藏',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.55),
                        ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Dismissible(
                      key: ValueKey(item.key),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      onDismissed: (_) => favoriteRepository.remove(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF181A20),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _FavoriteTile(
                            item: item,
                            onTap: () => openDetail(
                              context,
                              CoverHeroInfo(
                                sourceKey: item.sourceKey,
                                id: item.vodId,
                                name: item.name,
                                pic: item.pic,
                                remarks: item.remarks,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _FavoriteTile extends StatelessWidget {
  const _FavoriteTile({required this.item, required this.onTap});

  final FavoriteItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitleParts = [
      if (item.sourceName.isNotEmpty) item.sourceName,
      if (item.remarks.isNotEmpty) item.remarks,
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 76,
              child: Hero(
                tag: CoverHeroInfo.tag(item.sourceKey, item.vodId),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: ColoredBox(
                    color: const Color(0xFF2A2B31),
                    child: CoverImage(url: item.pic, sourceKey: item.sourceKey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  if (subtitleParts.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitleParts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.62),
                            height: 1.3,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right,
              color: scheme.onSurface.withValues(alpha: 0.28),
            ),
          ],
        ),
      ),
    );
  }
}
