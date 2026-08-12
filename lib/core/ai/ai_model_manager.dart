import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../storage/database.dart';
import 'ai_model_catalog.dart';

enum AiModelDownloadPhase {
  idle,
  downloading,
  paused,
  verifying,
  installed,
  failed,
}

class AiModelDownloadState {
  const AiModelDownloadState({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final AiModelDownloadPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final String? error;

  double? get progress => totalBytes <= 0 ? null : receivedBytes / totalBytes;
}

class AiModelManager extends ChangeNotifier {
  AiModelManager._({required this.modelsDirectory, required this.database});

  final Directory modelsDirectory;
  final AppDatabase database;
  final Map<String, AiModelDownloadState> _states =
      <String, AiModelDownloadState>{};
  bool _cancelRequested = false;
  String? selectedModelId;

  static Future<AiModelManager> open(AppDatabase database) async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory(p.join(support.path, 'Git Desktop', 'models'));
    return openAt(directory, database);
  }

  static Future<AiModelManager> openAt(
    Directory directory,
    AppDatabase database,
  ) async {
    await directory.create(recursive: true);
    final manager = AiModelManager._(
      modelsDirectory: directory,
      database: database,
    );
    manager.selectedModelId = database.readPreference('ai.selected_model');
    for (final model in aiModelCatalog) {
      final file = File(manager.modelPath(model));
      final partial = File(manager.partialPath(model));
      if (file.existsSync() && file.lengthSync() == model.sizeBytes) {
        manager._states[model.id] = AiModelDownloadState(
          phase: AiModelDownloadPhase.installed,
          receivedBytes: model.sizeBytes,
          totalBytes: model.sizeBytes,
        );
      } else if (partial.existsSync()) {
        manager._states[model.id] = AiModelDownloadState(
          phase: AiModelDownloadPhase.paused,
          receivedBytes: partial.lengthSync(),
          totalBytes: model.sizeBytes,
        );
      }
    }
    return manager;
  }

  AiModelDownloadState stateFor(AiModelCatalogItem model) =>
      _states[model.id] ??
      const AiModelDownloadState(phase: AiModelDownloadPhase.idle);

  String modelPath(AiModelCatalogItem model) =>
      p.join(modelsDirectory.path, model.fileName);
  String partialPath(AiModelCatalogItem model) => '${modelPath(model)}.part';

  Future<void> select(AiModelCatalogItem model) async {
    if (stateFor(model).phase != AiModelDownloadPhase.installed) return;
    selectedModelId = model.id;
    database.writePreference('ai.selected_model', model.id);
    notifyListeners();
  }

  void pause() {
    _cancelRequested = true;
  }

  Future<void> download(AiModelCatalogItem model) async {
    if (stateFor(model).phase == AiModelDownloadPhase.downloading) return;
    if (_states.values.any(
      (state) => state.phase == AiModelDownloadPhase.downloading,
    )) {
      return;
    }
    _cancelRequested = false;
    final partial = File(partialPath(model));
    var offset = partial.existsSync() ? await partial.length() : 0;
    if (offset > model.sizeBytes) {
      await partial.delete();
      offset = 0;
    }
    _set(
      model,
      AiModelDownloadState(
        phase: AiModelDownloadPhase.downloading,
        receivedBytes: offset,
        totalBytes: model.sizeBytes,
      ),
    );
    final client = HttpClient();
    try {
      final request = await client.getUrl(model.url);
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException(
          'Download returned HTTP ${response.statusCode}',
          uri: model.url,
        );
      }
      if (offset > 0 && response.statusCode == HttpStatus.ok) {
        await partial.writeAsBytes(const <int>[], flush: true);
        offset = 0;
      }
      final sink = partial.openWrite(mode: FileMode.append);
      var received = offset;
      try {
        await for (final chunk in response) {
          if (_cancelRequested) break;
          sink.add(chunk);
          received += chunk.length;
          _set(
            model,
            AiModelDownloadState(
              phase: AiModelDownloadPhase.downloading,
              receivedBytes: received,
              totalBytes: model.sizeBytes,
            ),
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }
      if (_cancelRequested) {
        _set(
          model,
          AiModelDownloadState(
            phase: AiModelDownloadPhase.paused,
            receivedBytes: await partial.length(),
            totalBytes: model.sizeBytes,
          ),
        );
        return;
      }
      if (await partial.length() != model.sizeBytes) {
        throw const FileSystemException(
          'Downloaded model size does not match the catalog.',
        );
      }
      _set(
        model,
        AiModelDownloadState(
          phase: AiModelDownloadPhase.verifying,
          receivedBytes: model.sizeBytes,
          totalBytes: model.sizeBytes,
        ),
      );
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != model.sha256) {
        await partial.delete();
        throw const FileSystemException(
          'SHA-256 verification failed. The corrupt download was removed.',
        );
      }
      await partial.rename(modelPath(model));
      _set(
        model,
        AiModelDownloadState(
          phase: AiModelDownloadPhase.installed,
          receivedBytes: model.sizeBytes,
          totalBytes: model.sizeBytes,
        ),
      );
      await select(model);
    } on Object catch (error) {
      _set(
        model,
        AiModelDownloadState(
          phase: AiModelDownloadPhase.failed,
          receivedBytes: partial.existsSync() ? await partial.length() : 0,
          totalBytes: model.sizeBytes,
          error: error.toString(),
        ),
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<void> delete(AiModelCatalogItem model) async {
    final complete = File(modelPath(model));
    final partial = File(partialPath(model));
    if (complete.existsSync()) await complete.delete();
    if (partial.existsSync()) await partial.delete();
    if (selectedModelId == model.id) {
      selectedModelId = null;
      database.deletePreference('ai.selected_model');
    }
    _states.remove(model.id);
    notifyListeners();
  }

  void _set(AiModelCatalogItem model, AiModelDownloadState state) {
    _states[model.id] = state;
    notifyListeners();
  }
}
