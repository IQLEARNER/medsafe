class PillPrediction {
  const PillPrediction({
    required this.label,
    required this.confidence,
    required this.index,
    required this.rawScores,
  });

  final String label;
  final double confidence;
  final int index;
  final List<double> rawScores;

  bool get isConfident => confidence >= 0.6;

  String get confidenceText => '${(confidence * 100).toStringAsFixed(1)}%';
}
