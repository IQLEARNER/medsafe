import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/pill_prediction.dart';

class PillRecognitionService {
  PillRecognitionService._(this._interpreter, this._labels, this._loadError);

  static const String defaultModelAssetPath =
      'assets/models/pill_classifier.tflite';
  static const String defaultLabelsAssetPath = 'assets/models/pill_labels.txt';

  static bool get isSupportedPlatform => Platform.isAndroid || Platform.isIOS;

  final Interpreter? _interpreter;
  final List<String> _labels;
  final String? _loadError;

  bool get isReady => _interpreter != null;
  String? get loadErrorMessage => _loadError;

  static Future<PillRecognitionService> create({
    String modelAssetPath = defaultModelAssetPath,
    String labelsAssetPath = defaultLabelsAssetPath,
  }) async {
    if (!isSupportedPlatform) {
      return PillRecognitionService._(
        null,
        const [],
        'Pill recognition is only supported on Android and iOS. '
            'This Linux desktop build cannot load the TensorFlow Lite native runtime.',
      );
    }

    try {
      final interpreter = await Interpreter.fromAsset(modelAssetPath);
      List<String> labels = const [];

      try {
        final labelsText = await rootBundle.loadString(labelsAssetPath);
        labels = labelsText
            .split('\n')
            .map((label) => label.trim())
            .where((label) => label.isNotEmpty)
            .toList();
      } on Object {
        labels = const [];
      }

      return PillRecognitionService._(interpreter, labels, null);
    } on Object catch (error) {
      return PillRecognitionService._(
        null,
        const [],
        'Could not load the pill recognition model from $modelAssetPath. '
            'Make sure the TFLite model exists in assets/models/. '
            'Original error: $error',
      );
    }
  }

  void dispose() {
    _interpreter?.close();
  }

  Future<PillPrediction?> recognizeImage(
    File imageFile, {
    double confidenceThreshold = 0.4,
  }) async {
    final interpreter = _interpreter;
    if (interpreter == null) {
      return null;
    }

    final imageBytes = await imageFile.readAsBytes();
    final decodedImage = img.decodeImage(imageBytes);

    if (decodedImage == null) {
      throw StateError('Could not decode the selected image.');
    }

    final inputTensor = interpreter.getInputTensor(0);
    final inputShape = inputTensor.shape;

    if (inputShape.length < 4) {
      throw StateError('Unsupported model input shape: $inputShape');
    }

    final inputHeight = inputShape[1];
    final inputWidth = inputShape[2];
    final inputChannels = inputShape[3];

    if (inputChannels != 3) {
      throw StateError('The pill model must accept RGB input.');
    }

    final resizedImage = img.copyResize(
      decodedImage,
      width: inputWidth,
      height: inputHeight,
      interpolation: img.Interpolation.linear,
    );

    final inputData = _buildInputData(resizedImage, inputTensor.type);
    final outputTensor = interpreter.getOutputTensor(0);
    final outputShape = outputTensor.shape;

    if (outputShape.isEmpty) {
      throw StateError('Unsupported model output shape: $outputShape');
    }

    final classCount = outputShape.last;
    final outputData = _buildOutputData(outputTensor.type, classCount);

    interpreter.run(inputData, outputData);

    final scores = _extractScores(outputData);
    final normalizedScores = _normalizeScores(scores);
    final bestIndex = _bestIndex(normalizedScores);
    final confidence = normalizedScores[bestIndex];

    if (confidence < confidenceThreshold) {
      return null;
    }

    return PillPrediction(
      label: _labelForIndex(bestIndex),
      confidence: confidence,
      index: bestIndex,
      rawScores: normalizedScores,
    );
  }

  dynamic _buildInputData(img.Image image, TensorType type) {
    if (type == TensorType.float32) {
      return [
        for (var y = 0; y < image.height; y++)
          [
            for (var x = 0; x < image.width; x++)
              _pixelToFloatList(image.getPixel(x, y)),
          ],
      ];
    }

    if (type == TensorType.uint8) {
      return [
        for (var y = 0; y < image.height; y++)
          [
            for (var x = 0; x < image.width; x++)
              _pixelToUint8List(image.getPixel(x, y)),
          ],
      ];
    }

    throw StateError('Unsupported input tensor type: $type');
  }

  dynamic _buildOutputData(TensorType type, int classCount) {
    if (type == TensorType.float32) {
      return [List<double>.filled(classCount, 0)];
    }

    if (type == TensorType.uint8) {
      return [List<int>.filled(classCount, 0)];
    }

    throw StateError('Unsupported output tensor type: $type');
  }

  List<double> _extractScores(dynamic outputData) {
    final values = (outputData as List).first as List;
    return values.map((value) => (value as num).toDouble()).toList();
  }

  List<double> _normalizeScores(List<double> scores) {
    if (scores.isEmpty) {
      throw StateError('The model returned no predictions.');
    }

    final sum = scores.fold<double>(0, (total, value) => total + value);
    final looksLikeProbabilityDistribution =
        scores.every((value) => value >= 0 && value <= 1) &&
        sum > 0.9 &&
        sum < 1.1;

    if (looksLikeProbabilityDistribution) {
      return scores;
    }

    final maxScore = scores.reduce(math.max);
    final expScores = scores
        .map((score) => math.exp(score - maxScore))
        .toList(growable: false);
    final expSum = expScores.fold<double>(0, (total, value) => total + value);

    if (expSum == 0) {
      return List<double>.filled(scores.length, 0);
    }

    return expScores.map((value) => value / expSum).toList(growable: false);
  }

  int _bestIndex(List<double> scores) {
    var bestIndex = 0;
    var bestScore = scores.first;

    for (var index = 1; index < scores.length; index++) {
      if (scores[index] > bestScore) {
        bestIndex = index;
        bestScore = scores[index];
      }
    }

    return bestIndex;
  }

  String _labelForIndex(int index) {
    if (index >= 0 && index < _labels.length) {
      return _labels[index];
    }

    return 'Class ${index + 1}';
  }

  List<double> _pixelToFloatList(img.Pixel pixel) {
    return [pixel.r / 255.0, pixel.g / 255.0, pixel.b / 255.0];
  }

  List<int> _pixelToUint8List(img.Pixel pixel) {
    return [pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt()];
  }
}
