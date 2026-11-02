/// Local storage + validation for Zipformer Quran 3.2 model files.
///
/// M2.4-A: import via SAF, size + streaming SHA256 checks.
/// Does NOT initialize OnlineRecognizer — Ready stays false until M2.4-B.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Expected artifacts (from compatibility audit).
class Zipformer32Specs {
  static const onnxFileName = 'zipformer_p_arabic_v3.2.int8.onnx';
  static const tokensFileName = 'tokens.txt';
  static const onnxExpectedBytes = 72705740;
  static const onnxSha256 =
      '5225f8e06930526905b8df2c05cb2c58649b68f0566b1751769f8eb51553e46a';
  static const tokensSha256 =
      '252c10687e442aa9291973065fae19fa39bcd681c4f5612ec496a647e20b43a1';
}

enum Zipformer32InstallState {
  notInstalled,
  filesImported,
  // Ready is reserved for M2.4-B after OnlineRecognizer init succeeds.
  // Until then we never report ready.
  error,
}

class ValidationResult {
  final bool ok;
  final String message;
  final String? actualSha256;
  final int? actualSize;

  const ValidationResult({
    required this.ok,
    required this.message,
    this.actualSha256,
    this.actualSize,
  });
}

class Zipformer32ModelStore {
  Zipformer32InstallState state = Zipformer32InstallState.notInstalled;
  String? lastError;
  double importProgress = 0.0; // 0..1 during copy+hash
  String statusDetail = 'Not installed';

  String? _onnxPath;
  String? _tokensPath;

  String? get onnxPath => _onnxPath;
  String? get tokensPath => _tokensPath;

  /// Files present and hash-verified — still NOT inference-ready (M2.4-B).
  bool get filesVerified =>
      state == Zipformer32InstallState.filesImported &&
      _onnxPath != null &&
      _tokensPath != null;

  /// Always false in M2.4-A. Inference init is M2.4-B.
  bool get isReadyForInference => false;

  Future<Directory> _dir() async {
    final root = await getApplicationSupportDirectory();
    final d = Directory(p.join(root.path, 'models', 'zipformer_quran_3_2'));
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    return d;
  }

  /// Stream SHA256 of [file] without loading entire file into RAM.
  static Future<String> sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<ValidationResult> validateOnnxFile(File file) async {
    if (!await file.exists()) {
      return const ValidationResult(ok: false, message: 'ONNX file missing');
    }
    final size = await file.length();
    if (size != Zipformer32Specs.onnxExpectedBytes) {
      return ValidationResult(
        ok: false,
        message:
            'ONNX size $size ≠ expected ${Zipformer32Specs.onnxExpectedBytes}',
        actualSize: size,
      );
    }
    final hash = await sha256File(file);
    if (hash != Zipformer32Specs.onnxSha256) {
      return ValidationResult(
        ok: false,
        message: 'ONNX SHA256 mismatch',
        actualSha256: hash,
        actualSize: size,
      );
    }
    return ValidationResult(
      ok: true,
      message: 'ONNX OK',
      actualSha256: hash,
      actualSize: size,
    );
  }

  static Future<ValidationResult> validateTokensFile(File file) async {
    if (!await file.exists()) {
      return const ValidationResult(ok: false, message: 'tokens.txt missing');
    }
    final hash = await sha256File(file);
    if (hash != Zipformer32Specs.tokensSha256) {
      return ValidationResult(
        ok: false,
        message: 'tokens.txt SHA256 mismatch',
        actualSha256: hash,
      );
    }
    return ValidationResult(
      ok: true,
      message: 'tokens.txt OK',
      actualSha256: hash,
    );
  }

  /// Scan private storage for previously imported files.
  Future<void> refreshFromDisk() async {
    lastError = null;
    final dir = await _dir();
    final onnx = File(p.join(dir.path, Zipformer32Specs.onnxFileName));
    final tokens = File(p.join(dir.path, Zipformer32Specs.tokensFileName));

    if (!await onnx.exists() || !await tokens.exists()) {
      state = Zipformer32InstallState.notInstalled;
      statusDetail = 'Not installed';
      _onnxPath = null;
      _tokensPath = null;
      return;
    }

    final o = await validateOnnxFile(onnx);
    final t = await validateTokensFile(tokens);
    if (o.ok && t.ok) {
      _onnxPath = onnx.path;
      _tokensPath = tokens.path;
      state = Zipformer32InstallState.filesImported;
      statusDetail =
          'Files imported (not inference-ready until engine init)';
    } else {
      state = Zipformer32InstallState.error;
      lastError = [if (!o.ok) o.message, if (!t.ok) t.message].join('; ');
      statusDetail = 'Validation failed';
      _onnxPath = null;
      _tokensPath = null;
    }
  }

  /// Pick both files via SAF (file_picker) and copy into app-private storage.
  Future<bool> importViaSaf({void Function(double)? onProgress}) async {
    lastError = null;
    importProgress = 0.0;
    onProgress?.call(0.0);

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) {
        lastError = 'Import cancelled';
        return false;
      }

      File? onnxSrc;
      File? tokensSrc;
      for (final f in result.files) {
        final name = f.name;
        final path = f.path;
        if (path == null) continue;
        if (name == Zipformer32Specs.onnxFileName ||
            name.endsWith(Zipformer32Specs.onnxFileName)) {
          onnxSrc = File(path);
        } else if (name == Zipformer32Specs.tokensFileName) {
          tokensSrc = File(path);
        }
      }

      if (onnxSrc == null || tokensSrc == null) {
        lastError =
            'Select both ${Zipformer32Specs.onnxFileName} and ${Zipformer32Specs.tokensFileName}';
        state = Zipformer32InstallState.error;
        statusDetail = 'Missing required files';
        return false;
      }

      if (!await onnxSrc.exists() || !await tokensSrc.exists()) {
        lastError = 'Selected path not readable';
        return false;
      }

      final dir = await _dir();
      final onnxDst =
          File(p.join(dir.path, Zipformer32Specs.onnxFileName));
      final tokensDst =
          File(p.join(dir.path, Zipformer32Specs.tokensFileName));

      // Copy ONNX (large)
      onProgress?.call(0.05);
      await onnxSrc.copy(onnxDst.path);
      importProgress = 0.45;
      onProgress?.call(0.45);

      await tokensSrc.copy(tokensDst.path);
      importProgress = 0.55;
      onProgress?.call(0.55);

      final o = await validateOnnxFile(onnxDst);
      importProgress = 0.9;
      onProgress?.call(0.9);
      final t = await validateTokensFile(tokensDst);
      importProgress = 1.0;
      onProgress?.call(1.0);

      if (!o.ok || !t.ok) {
        // Remove bad copies
        if (await onnxDst.exists()) await onnxDst.delete();
        if (await tokensDst.exists()) await tokensDst.delete();
        state = Zipformer32InstallState.error;
        lastError = [if (!o.ok) o.message, if (!t.ok) t.message].join('; ');
        statusDetail = 'Validation failed';
        _onnxPath = null;
        _tokensPath = null;
        return false;
      }

      _onnxPath = onnxDst.path;
      _tokensPath = tokensDst.path;
      state = Zipformer32InstallState.filesImported;
      statusDetail =
          'Files imported (not inference-ready until engine init)';
      lastError = null;
      return true;
    } catch (e) {
      lastError = 'Import failed: $e';
      state = Zipformer32InstallState.error;
      statusDetail = 'Import failed';
      return false;
    }
  }

  /// Remove installed files (settings action).
  Future<void> clear() async {
    final dir = await _dir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    _onnxPath = null;
    _tokensPath = null;
    state = Zipformer32InstallState.notInstalled;
    statusDetail = 'Not installed';
    lastError = null;
    importProgress = 0.0;
  }
}
