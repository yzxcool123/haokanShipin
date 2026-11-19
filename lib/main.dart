import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/repositories/source_repository.dart';
import 'data/services/doh_resolver.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSize = 500;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 200 << 20;
  DohResolver.instance;
  HttpOverrides.global = DohHttpOverrides();
  final prefs = await SharedPreferences.getInstance();
  final sourceRepository = SourceRepository(
    prefs: prefs,
    bundle: rootBundle,
  );
  await sourceRepository.load();
  runApp(HaoKanShiPinApp(sourceRepository: sourceRepository, prefs: prefs));
  unawaited(sourceRepository.refreshOnColdStart());
}
