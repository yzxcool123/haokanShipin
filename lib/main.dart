import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/repositories/source_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final sourceRepository = SourceRepository(
    prefs: prefs,
    bundle: rootBundle,
  );
  await sourceRepository.load();
  runApp(AiKanYingShiApp(sourceRepository: sourceRepository));
}
