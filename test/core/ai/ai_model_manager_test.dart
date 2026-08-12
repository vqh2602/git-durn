import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop_client/core/ai/ai_model_catalog.dart';
import 'package:git_desktop_client/core/ai/ai_model_manager.dart';
import 'package:git_desktop_client/core/storage/database.dart';

void main() {
  test(
    'resumes a partial model with HTTP Range and verifies SHA-256',
    () async {
      final bytes = List<int>.generate(8192, (index) => index % 251);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      String? rangeHeader;
      server.listen((request) async {
        rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        final start = rangeHeader == null
            ? 0
            : int.parse(
                RegExp(r'bytes=(\d+)-').firstMatch(rangeHeader!)!.group(1)!,
              );
        request.response.statusCode = start == 0
            ? HttpStatus.ok
            : HttpStatus.partialContent;
        request.response.contentLength = bytes.length - start;
        request.response.add(bytes.sublist(start));
        await request.response.close();
      });

      final temporary = await Directory.systemTemp.createTemp(
        'ai-resume-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final manager = await AiModelManager.openAt(temporary, database);
      final model = AiModelCatalogItem(
        id: 'test-model',
        name: 'Test',
        description: 'Test',
        fileName: 'test.gguf',
        url: Uri.parse('http://${server.address.host}:${server.port}/model'),
        sizeBytes: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
      await File(
        manager.partialPath(model),
      ).writeAsBytes(bytes.sublist(0, 1024));

      await manager.download(model);

      expect(rangeHeader, 'bytes=1024-');
      expect(manager.stateFor(model).phase, AiModelDownloadPhase.installed);
      expect(await File(manager.modelPath(model)).readAsBytes(), bytes);
      expect(manager.selectedModelId, model.id);
    },
  );
}
