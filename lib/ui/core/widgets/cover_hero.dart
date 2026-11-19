import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class CoverHeroInfo {
  const CoverHeroInfo({
    required this.sourceKey,
    required this.id,
    required this.name,
    this.pic = '',
    this.remarks = '',
    this.typeName = '',
  });

  final String sourceKey;
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String typeName;

  static String tag(String sourceKey, String id) => 'cover-$sourceKey-$id';
}

void openDetail(BuildContext context, CoverHeroInfo preview) {
  context.push(
    '/detail/${Uri.encodeComponent(preview.sourceKey)}/${Uri.encodeComponent(preview.id)}',
    extra: preview,
  );
}

CoverHeroInfo? coverHeroInfoOf(Object? extra) {
  return extra is CoverHeroInfo ? extra : null;
}
