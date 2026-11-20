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
    this.scope = 'catalog',
  });

  final String sourceKey;
  final String id;
  final String name;
  final String pic;
  final String remarks;
  final String typeName;
  /// Distinguishes the same title when it appears in multiple lists
  /// that stay mounted together (catalog, search, profile).
  final String scope;

  static String tag(String sourceKey, String id, {String scope = 'catalog'}) =>
      'cover-$scope-$sourceKey-$id';

  String get heroTag => tag(sourceKey, id, scope: scope);
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
