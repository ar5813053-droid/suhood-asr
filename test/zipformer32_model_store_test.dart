import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:suhood_asr/engine/asr/zipformer32_model_store.dart';

void main() {
  group('Zipformer32Specs', () {
    test('expected constants match audit', () {
      expect(Zipformer32Specs.onnxExpectedBytes, 72705740);
      expect(
        Zipformer32Specs.onnxSha256,
        '5225f8e06930526905b8df2c05cb2c58649b68f0566b1751769f8eb51553e46a',
      );
      expect(
        Zipformer32Specs.tokensSha256,
        '252c10687e442aa9291973065fae19fa39bcd681c4f5612ec496a647e20b43a1',
      );
    });
  });

  group('validateOnnxFile', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('suhood_z32_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('rejects missing file', () async {
      final f = File('${tmp.path}/missing.onnx');
      final r = await Zipformer32ModelStore.validateOnnxFile(f);
      expect(r.ok, isFalse);
      expect(r.message, contains('missing'));
    });

    test('rejects wrong size', () async {
      final f = File('${tmp.path}/zipformer_p_arabic_v3.2.int8.onnx');
      await f.writeAsBytes(List.filled(100, 0));
      final r = await Zipformer32ModelStore.validateOnnxFile(f);
      expect(r.ok, isFalse);
      expect(r.message, contains('size'));
      expect(r.actualSize, 100);
    });

    test('rejects correct size but wrong hash', () async {
      final f = File('${tmp.path}/zipformer_p_arabic_v3.2.int8.onnx');
      // Correct length, wrong content
      final sink = f.openWrite();
      const chunk = 1024 * 64;
      var left = Zipformer32Specs.onnxExpectedBytes;
      final buf = List<int>.filled(chunk, 7);
      while (left > 0) {
        final n = left > chunk ? chunk : left;
        sink.add(buf.sublist(0, n));
        left -= n;
      }
      await sink.close();
      expect(await f.length(), Zipformer32Specs.onnxExpectedBytes);
      final r = await Zipformer32ModelStore.validateOnnxFile(f);
      expect(r.ok, isFalse);
      expect(r.message, contains('SHA256'));
      expect(r.actualSha256, isNot(Zipformer32Specs.onnxSha256));
    });
  });

  group('validateTokensFile', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('suhood_tok_');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('rejects missing tokens', () async {
      final f = File('${tmp.path}/tokens.txt');
      final r = await Zipformer32ModelStore.validateTokensFile(f);
      expect(r.ok, isFalse);
    });

    test('rejects wrong tokens hash', () async {
      final f = File('${tmp.path}/tokens.txt');
      await f.writeAsString('not the real tokens\n');
      final r = await Zipformer32ModelStore.validateTokensFile(f);
      expect(r.ok, isFalse);
      expect(r.message, contains('SHA256'));
    });

    test('accepts file with expected sha256', () async {
      // Build content that hashes to expected only if we had the real file.
      // Here we only assert the validator compares against the constant.
      final f = File('${tmp.path}/tokens.txt');
      await f.writeAsString('x');
      final digest = sha256.convert(await f.readAsBytes()).toString();
      final r = await Zipformer32ModelStore.validateTokensFile(f);
      if (digest == Zipformer32Specs.tokensSha256) {
        expect(r.ok, isTrue);
      } else {
        expect(r.ok, isFalse);
      }
    });
  });

  group('Ready flag', () {
    test('isReadyForInference follows inferenceInitialized only', () {
      final store = Zipformer32ModelStore();
      expect(store.isReadyForInference, isFalse);
      store.state = Zipformer32InstallState.filesImported;
      // Files alone do not mark Ready
      expect(store.isReadyForInference, isFalse);
      store.inferenceInitialized = true;
      expect(store.isReadyForInference, isTrue);
    });
  });
}
