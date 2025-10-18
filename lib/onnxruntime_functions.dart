
/* Don't delete, might be useful later
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:onnxruntime/onnxruntime.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:offline_engine/src/rust/api/tokenizer.dart' as api;
import 'dart:math' show sqrt, max;
import 'dart:io';
import 'package:path/path.dart' as path;

// Move this from main.dart
OrtSession? _modelSession;
late final OrtSessionOptions _sessionOptions;

// Add initialization function
Future<void> initializeOnnxRuntime() async {
  OrtEnv.instance.init();
  _sessionOptions = OrtSessionOptions()
    ..setIntraOpNumThreads(4)  // Limit threads
    ..setInterOpNumThreads(2); // Limit threads
    
  // Initialize model
  final rawAssetFile = await rootBundle.load('assets/pretrainedMiniLM-L6-v2/model.onnx');
  final modelBytes = rawAssetFile.buffer.asUint8List();
  _modelSession = OrtSession.fromBuffer(modelBytes, _sessionOptions);

  // Get the application directory
  final appDir = await getApplicationDocumentsDirectory();

  // Create tokenizer directory and copy file
  final tokenizerDir = Directory(path.join(appDir.path, 'tokenizer'));
  await tokenizerDir.create(recursive: true);
  
  // Copy tokenizer.json from assets
  final tokenizerFile = File(path.join(tokenizerDir.path, 'tokenizer.json'));
  if (!await tokenizerFile.exists()) {
    final bytes = await rootBundle.load('assets/pretrainedMiniLM-L6-v2/tokenizer.json');
    await tokenizerFile.writeAsBytes(bytes.buffer.asUint8List());
    debugPrint("Copied tokenizer file to: ${tokenizerFile.path}");
  }

  // Test the embedding
  await getEmbeddingTokenizerAndOnnxInferenceMiniLM("This is an example sentence");
}

// Move meanPooling function here since it's used by the onnx functions
Future<List<double>> meanPooling(List<List<dynamic>> tokenEmbeddings, List<int> attentionMask) async {
  final embeddingDim = (tokenEmbeddings[0] as List).length;
  List<double> meanEmbedding = List.filled(embeddingDim, 0.0);

  // Expand attention mask
  final expandedMask = List.generate(
    tokenEmbeddings.length,
    (i) => attentionMask[i] == 1 ? 1.0 : 0.0,
  );

  // Sum embeddings for tokens with attention mask = 1
  for (var i = 0; i < tokenEmbeddings.length; i++) {
    final embedding = tokenEmbeddings[i] as List;
    for (var j = 0; j < embeddingDim; j++) {
      meanEmbedding[j] += (embedding[j] as num).toDouble() * expandedMask[i];
    }
  }

  // Calculate mean
  final maskSum = expandedMask.reduce((a, b) => a + b);
  debugPrint("\nCalculated mask sum: $maskSum");

  if (maskSum > 0) {
    for (var i = 0; i < embeddingDim; i++) {
      meanEmbedding[i] /= maskSum;
    }
  }

  // L2 normalize
  double sumSquares = 0.0;
  for (var val in meanEmbedding) {
    sumSquares += val * val;
  }
  debugPrint("Sum squares before normalization: $sumSquares");

  final norm = sqrt(max(sumSquares, 1e-12));
  debugPrint("Normalization factor: $norm");

  if (norm > 1e-12) {
    for (var i = 0; i < embeddingDim; i++) {
      meanEmbedding[i] /= norm;
    }
  }

  return meanEmbedding;
}

Future<List<double>> getEmbeddingTokenizerAndOnnxInferenceMiniLM(String text) async {
  // Initialize model session if not already initialized
  if (_modelSession == null) {
    final rawAssetFile = await rootBundle.load('assets/pretrainedMiniLM-L6-v2/model.onnx');
    final modelBytes = rawAssetFile.buffer.asUint8List();
    final sessionOptions = OrtSessionOptions();
    _modelSession = OrtSession.fromBuffer(modelBytes, sessionOptions);
  }
  
  final appDir = await getApplicationDocumentsDirectory();
  
  final encoded = await api.encodeText(input: text, appDir: appDir.path);

  final runOptions = OrtRunOptions();
  final inputs = {
    "input_ids": OrtValueTensor.createTensorWithDataList(
      encoded.inputIds.map((e) => e.toInt()).toList(), 
      [1, encoded.inputIds.length],
    ),
    "attention_mask": OrtValueTensor.createTensorWithDataList(
      encoded.attentionMask.map((e) => e.toInt()).toList(), 
      [1, encoded.attentionMask.length],
    ),
    "token_type_ids": OrtValueTensor.createTensorWithDataList(
      encoded.tokenTypeIds.map((e) => e.toInt()).toList(), 
      [1, encoded.tokenTypeIds.length],
    ),
  };

  // Use cached session
  final outputs = await _modelSession!.runAsync(runOptions, inputs);
  List<double> meanEmbedding = [];
  
  if (outputs != null && outputs.isNotEmpty) {
    final firstOutput = outputs[0];
    if (firstOutput != null) {
      final value = firstOutput.value;
      if (value is List && value.isNotEmpty) {
        final tokenEmbeddings = value[0] as List<List<dynamic>>;
        final attentionMask = encoded.attentionMask.map((e) => e.toInt()).toList();
        
        meanEmbedding = await meanPooling(tokenEmbeddings, attentionMask);

        final first10 = meanEmbedding.take(10).map((e) => e.toStringAsFixed(6)).toList();
        debugPrint("First 10 values for text $text: $first10");
      }
    }
  }

  // Clean up
  for (var output in outputs ?? []) {
    output?.release();
  }
  runOptions.release();
  
  return meanEmbedding;
}

Future<List<List<double>>> getEmbeddingsTokenizerAndOnnxInferenceMiniLM(List<String> texts) async {
  List<List<double>> allEmbeddings = [];
  
  // Process each text using the working function
  for (final text in texts) {
    try {
      final embedding = await getEmbeddingTokenizerAndOnnxInferenceMiniLM(text);
      allEmbeddings.add(embedding);
    } catch (e, stack) {
      debugPrint('Error processing text: $e');
      debugPrint('Stack trace: $stack');
      rethrow;
    }
  }
  
  return allEmbeddings;
}
*/