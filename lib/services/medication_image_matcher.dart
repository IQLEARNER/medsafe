import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

class MedicationImageMatch {
  const MedicationImageMatch({required this.score, required this.isMatch});

  final double score;
  final bool isMatch;

  String get confidenceText => '${(score * 100).round()}% visual similarity';
}

class MedicationImageMatcher {
  const MedicationImageMatcher();

  static const _size = 64;
  static const _matchThreshold = 0.86;

  Future<MedicationImageMatch> compare(File first, File second) async {
    final firstImage = img.decodeImage(await first.readAsBytes());
    final secondImage = img.decodeImage(await second.readAsBytes());
    if (firstImage == null || secondImage == null) {
      throw StateError('One of the medication photos could not be decoded.');
    }

    final left = img.copyResize(firstImage, width: _size, height: _size);
    final right = img.copyResize(secondImage, width: _size, height: _size);
    var squaredError = 0.0;
    var absoluteError = 0.0;
    var leftMean = 0.0;
    var rightMean = 0.0;
    final leftValues = <double>[];
    final rightValues = <double>[];

    for (var y = 0; y < _size; y++) {
      for (var x = 0; x < _size; x++) {
        final leftValue = _luminance(left.getPixel(x, y));
        final rightValue = _luminance(right.getPixel(x, y));
        leftValues.add(leftValue);
        rightValues.add(rightValue);
        leftMean += leftValue;
        rightMean += rightValue;
        squaredError += math.pow(leftValue - rightValue, 2).toDouble();
        absoluteError += (leftValue - rightValue).abs();
      }
    }

    final count = leftValues.length.toDouble();
    leftMean /= count;
    rightMean /= count;
    var covariance = 0.0;
    var leftVariance = 0.0;
    var rightVariance = 0.0;
    for (var index = 0; index < leftValues.length; index++) {
      final leftDelta = leftValues[index] - leftMean;
      final rightDelta = rightValues[index] - rightMean;
      covariance += leftDelta * rightDelta;
      leftVariance += leftDelta * leftDelta;
      rightVariance += rightDelta * rightDelta;
    }

    final correlation = covariance /
        (math.sqrt(leftVariance * rightVariance) + 0.0001);
    final normalizedCorrelation = ((correlation + 1) / 2).clamp(0.0, 1.0);
    final mseSimilarity = (1 - squaredError / count).clamp(0.0, 1.0);
    final maeSimilarity = (1 - absoluteError / count).clamp(0.0, 1.0);
    final score = (normalizedCorrelation * 0.5 +
            mseSimilarity * 0.3 +
            maeSimilarity * 0.2)
        .clamp(0.0, 1.0);

    return MedicationImageMatch(
      score: score,
      isMatch: score >= _matchThreshold,
    );
  }

  double _luminance(img.Pixel pixel) {
    return (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255;
  }
}
