import 'package:flutter/foundation.dart';

import '../../../data/repositories/source_repository.dart';
import '../../../domain/models/media_source.dart';

class SourcesViewModel extends ChangeNotifier {
  SourcesViewModel({required SourceRepository sourceRepository})
      : _sourceRepository = sourceRepository {
    _sourceRepository.addListener(notifyListeners);
  }

  final SourceRepository _sourceRepository;

  List<MediaSource> get sources => _sourceRepository.sources;
  MediaSource? get current => _sourceRepository.current;
  bool refreshing = false;
  String? message;

  String displayNameOf(MediaSource source) =>
      _sourceRepository.displayNameOf(source);

  bool isUnavailable(MediaSource source) =>
      _sourceRepository.availabilityOf(source.key) ==
      SourceAvailability.unavailable;

  Future<void> select(MediaSource source) async {
    await _sourceRepository.select(source);
  }

  Future<void> addCustom({required String name, required String api}) async {
    final uri = Uri.tryParse(api.trim());
    if (uri == null ||
        !(uri.isScheme('http') || uri.isScheme('https')) ||
        uri.host.isEmpty) {
      message = '请输入有效的接口地址，例如 https://example.com/api.php/provide/vod/';
      notifyListeners();
      return;
    }
    await _sourceRepository.addCustom(name: name, api: api);
    message = '已添加并切换到「${name.trim().isEmpty ? '自定义源' : name.trim()}」';
    notifyListeners();
  }

  Future<void> removeCustom(MediaSource source) async {
    await _sourceRepository.removeCustom(source);
  }

  Future<void> refreshRemote() async {
    refreshing = true;
    message = null;
    notifyListeners();
    Object? listError;
    try {
      await _sourceRepository.refreshRemote();
    } catch (e) {
      listError = e;
    }
    try {
      await _sourceRepository.probeAll();
      message = listError == null
          ? '源列表已更新，并完成可用性检测'
          : '源列表刷新失败，已按当前列表完成可用性检测：$listError';
    } catch (e) {
      message = listError == null ? '源列表已更新，但可用性检测失败：$e' : '刷新失败：$listError';
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sourceRepository.removeListener(notifyListeners);
    super.dispose();
  }
}
