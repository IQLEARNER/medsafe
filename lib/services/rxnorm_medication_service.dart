import 'dart:convert';

import 'package:http/http.dart' as http;

class RxNormMedicationService {
  const RxNormMedicationService._();

  static Future<String?> findLikelyMedicationName(
    Iterable<String> textLines, {
    Set<String> excludedNames = const {},
  }) async {
    final excluded = excludedNames.map(_normalize).toSet();
    final lines = textLines
        .map((line) => line.trim())
        .where((line) => line.length >= 3)
        .where((line) => !_containsExcludedName(line, excluded))
        .take(6)
        .toList(growable: false);
    final matches = <({String name, double score})>[];

    for (final line in lines) {
      final uri = Uri.https('rxnav.nlm.nih.gov', '/REST/approximateTerm.json', {
        'term': line,
        'maxEntries': '5',
      });
      try {
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;

        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final group = body['approximateGroup'] as Map<String, dynamic>?;
        final candidates = group?['candidate'] as List? ?? const [];
        for (final candidate in candidates.whereType<Map>()) {
          final name = candidate['name']?.toString().trim() ?? '';
          final score = double.tryParse(candidate['score']?.toString() ?? '');
          if (name.isEmpty || score == null || score < 7.0) continue;
          if (excluded.contains(_normalize(name))) continue;
          if (!_hasStrongLexicalMatch(line, name)) continue;
          matches.add((name: name, score: score));
        }
      } catch (_) {
        continue;
      }
    }

    if (matches.isEmpty) return null;
    matches.sort((left, right) => right.score.compareTo(left.score));
    return matches.first.name;
  }

  static Future<List<String>> findSimilarNames(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.length < 3) return const [];

    try {
      final uri = Uri.https('rxnav.nlm.nih.gov', '/REST/approximateTerm.json', {
        'term': normalizedQuery,
        'maxEntries': '5',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final group = body['approximateGroup'] as Map<String, dynamic>?;
      final candidates = group?['candidate'] as List? ?? const [];
      final seen = <String>{};
      return candidates
          .whereType<Map>()
          .map((candidate) => candidate['name']?.toString().trim() ?? '')
          .where((name) => name.isNotEmpty && seen.add(name.toLowerCase()))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

  static bool _containsExcludedName(String line, Set<String> excluded) {
    final normalizedLine = _normalize(line);
    return excluded.any(
      (name) => name.isNotEmpty && normalizedLine.contains(name),
    );
  }

  static bool _hasStrongLexicalMatch(String query, String candidate) {
    final queryWords = _normalize(
      query,
    ).split(' ').where((word) => word.length >= 4);
    final candidateWords = _normalize(
      candidate,
    ).split(' ').where((word) => word.length >= 4);
    for (final queryWord in queryWords) {
      for (final candidateWord in candidateWords) {
        if (queryWord == candidateWord) return true;
        final longestLength = queryWord.length > candidateWord.length
            ? queryWord.length
            : candidateWord.length;
        if (_editDistance(queryWord, candidateWord) / longestLength <= 0.25) {
          return true;
        }
      }
    }
    return false;
  }

  static int _editDistance(String first, String second) {
    var previous = List<int>.generate(second.length + 1, (index) => index);
    for (var firstIndex = 0; firstIndex < first.length; firstIndex++) {
      final current = List<int>.filled(second.length + 1, 0);
      current[0] = firstIndex + 1;
      for (var secondIndex = 0; secondIndex < second.length; secondIndex++) {
        final substitutionCost =
            first.codeUnitAt(firstIndex) == second.codeUnitAt(secondIndex)
            ? 0
            : 1;
        current[secondIndex + 1] = [
          current[secondIndex] + 1,
          previous[secondIndex + 1] + 1,
          previous[secondIndex] + substitutionCost,
        ].reduce((left, right) => left < right ? left : right);
      }
      previous = current;
    }
    return previous.last;
  }
}
