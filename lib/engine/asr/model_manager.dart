/// Downloads and stores the Quran ASR model files locally.
/// Model is never committed to the git repository.
library;

import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Hugging Face files for Abdou/quran-asr-small (MIT).
class QuranAsrModelFiles {
  static const repo = 'Abdou/quran-asr-small';
  static const modelFileName = 'model.int8.onnx';
  static const tokensFileName = 'tokens.txt';

  /// Direct resolve URLs (HF CDN).
  static String modelUrl =
      'https://huggingface.co/$repo/resolve/main/$modelFileName';
  static String tokensUrl =
      'https://huggingface.co/$repo/resolve/main/$tokensFileName';
}

enum ModelDownloadState {
  unknown,
  missing,
  downloading,
  ready,
  error,
}

class ModelManager {
  ModelDownloadState state = ModelDownloadState.unknown;
  String? lastError;
  double progress = 0.0; // 0..1 while downloading

  String? _modelPath;
  String? _tokensPath;

  String? get modelPath => _modelPath;
  String? get tokensPath => _tokensPath;

  Future<Directory> _modelDir() async {
    final root = await getApplicationSupportDirectory();
    final dir = Directory(p.join(root.path, 'models', 'quran-asr-small'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Check whether model files already exist on disk.
  Future<bool> isReady() async {
    final dir = await _modelDir();
    final model = File(p.join(dir.path, QuranAsrModelFiles.modelFileName));
    final tokens = File(p.join(dir.path, QuranAsrModelFiles.tokensFileName));
    if (await model.exists() && await tokens.exists()) {
      // Basic size sanity (model should be ~36 MB).
      final len = await model.length();
      if (len > 10 * 1024 * 1024) {
        _modelPath = model.path;
        _tokensPath = tokens.path;
        state = ModelDownloadState.ready;
        return true;
      }
    }
    state = ModelDownloadState.missing;
    return false;
  }

  /// Download model + tokens if missing. Reports [progress] 0..1.
  Future<bool> ensureDownloaded({
    void Function(double progress)? onProgress,
  }) async {
    if (await isReady()) return true;

    state = ModelDownloadState.downloading;
    progress = 0.0;
    lastError = null;
    onProgress?.call(0.0);

    try {
      final dir = await _modelDir();
      final modelFile =
          File(p.join(dir.path, QuranAsrModelFiles.modelFileName));
      final tokensFile =
          File(p.join(dir.path, QuranAsrModelFiles.tokensFileName));

      // Tokens first (tiny).
      final tokensResp = await http.get(Uri.parse(QuranAsrModelFiles.tokensUrl));
      if (tokensResp.statusCode != 200) {
        throw HttpException(
          'tokens.txt download failed: HTTP ${tokensResp.statusCode}',
        );
      }
      await tokensFile.writeAsBytes(tokensResp.bodyBytes);

      // Model with progress (stream).
      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(QuranAsrModelFiles.modelUrl));
        final resp = await client.send(req);
        if (resp.statusCode != 200) {
          throw HttpException(
            'model.int8.onnx download failed: HTTP ${resp.statusCode}',
          );
        }
        final total = resp.contentLength ?? 36000000;
        final sink = modelFile.openWrite();
        var received = 0;
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          progress = (received / total).clamp(0.0, 1.0);
          onProgress?.call(progress);
        }
        await sink.close();
      } finally {
        client.close();
      }

      _modelPath = modelFile.path;
      _tokensPath = tokensFile.path;
      state = ModelDownloadState.ready;
      progress = 1.0;
      onProgress?.call(1.0);
      return true;
    } catch (e) {
      state = ModelDownloadState.error;
      lastError = e.toString();
      return false;
    }
  }

  /// Delete local model files (for testing / reset).
  Future<void> clear() async {
    final dir = await _modelDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _modelPath = null;
    _tokensPath = null;
    state = ModelDownloadState.missing;
    progress = 0.0;
  }
}
