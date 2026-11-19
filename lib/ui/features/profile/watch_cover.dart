import 'package:flutter/material.dart';

import '../../../domain/models/watch_record.dart';
import '../../core/widgets/cover_hero.dart';
import '../../core/widgets/cover_image.dart';

class WatchCover extends StatelessWidget {
  const WatchCover({
    super.key,
    required this.record,
    this.width,
    this.height,
    this.borderRadius = 10,
  });

  final WatchRecord record;
  final double? width;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Hero(
        tag: CoverHeroInfo.tag(record.sourceKey, record.vodId),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xFF2A2B31),
                child: CoverImage(url: record.pic, sourceKey: record.sourceKey),
              ),
              if (record.progress > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    value: record.progress,
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    color: const Color(0xFF7C9CFF),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
