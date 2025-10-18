import 'dart:math' as math;
import 'package:flutter/foundation.dart';

class Model2VecProcessor {
  List<double> processEmbedding(List<double> rawEmbedding, List<int> tokenIds) {
    debugPrint("Raw embedding stats before processing:");
    _printStats(rawEmbedding);

    // Just L2 normalize since model already does mean pooling
    var normalized = _l2Normalize(rawEmbedding);
    debugPrint("After L2 normalization:");
    _printStats(normalized);
    
    return normalized;
  }

  void _printStats(List<double> vec) {
    double minVal = vec.reduce((a, b) => math.min(a, b));
    double maxVal = vec.reduce((a, b) => math.max(a, b));
    double mean = vec.reduce((a, b) => a + b) / vec.length;
    debugPrint("min: $minVal, max: $maxVal, mean: $mean");
  }

  List<double> _l2Normalize(List<double> embedding) {
    // Use a more numerically stable algorithm like numpy's norm
    double maxAbs = 0.0;
    for (var val in embedding) {
      maxAbs = math.max(maxAbs, val.abs());
    }

    if (maxAbs == 0.0) {
      return List<double>.filled(embedding.length, 0.0);
    }

    // Scale to avoid overflow/underflow
    var scaled = embedding.map((x) => x / maxAbs).toList();
    
    double sumSquares = 0.0;
    for (var val in scaled) {
      sumSquares += val * val;
    }
    
    final norm = maxAbs * math.sqrt(math.max(sumSquares, 1e-12));
    var normalized = List<double>.from(embedding);
    for (var i = 0; i < embedding.length; i++) {
      normalized[i] /= norm;
    }

    // Verify normalization
    double checkNorm = 0.0;
    for (var val in normalized) {
      checkNorm += val * val;
    }
    debugPrint("L2 norm after normalization: ${math.sqrt(checkNorm)}");
    
    return normalized;
  }
} 