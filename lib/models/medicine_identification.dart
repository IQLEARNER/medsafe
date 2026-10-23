class MedicineIdentification {
  const MedicineIdentification({
    required this.brandNames,
    required this.genericNames,
    required this.purposes,
    required this.warnings,
    required this.ingredients,
  });

  final List<String> brandNames;
  final List<String> genericNames;
  final List<String> purposes;
  final List<String> warnings;
  final List<String> ingredients;

  factory MedicineIdentification.fromFdaLabel(Map<String, dynamic> label) {
    final openfda = label['openfda'] as Map? ?? {};

    final brandNames = _toStringList(openfda['brand_name']);
    final genericNames = _toStringList(openfda['generic_name']);
    final purposes = _toStringList(label['purpose']);
    final warnings = _toStringList(label['warnings']);

    final ingredients = <String>[];
    for (final raw in [
      _joinRawText(label['active_ingredient']),
      _joinRawText(label['inactive_ingredient']),
    ]) {
      if (raw.isEmpty) {
        continue;
      }

      ingredients.addAll(
        raw
            .split(RegExp(r'[,\n]'))
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
    }

    return MedicineIdentification(
      brandNames: brandNames,
      genericNames: genericNames,
      purposes: purposes,
      warnings: warnings,
      ingredients: ingredients,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'brandNames': brandNames,
      'genericNames': genericNames,
      'purposes': purposes,
      'warnings': warnings,
      'ingredients': ingredients,
    };
  }

  bool matchesMedicationName(String selectedName) {
    final query = selectedName.toLowerCase();

    bool matchesAny(List<String> names) {
      return names.any((name) {
        final value = name.toLowerCase();
        return value.contains(query) || query.contains(value);
      });
    }

    return matchesAny(brandNames) || matchesAny(genericNames);
  }

  bool hasAllergenMatch(Iterable<String> allergies) {
    final lowerIngredients = ingredients.map(
      (ingredient) => ingredient.toLowerCase(),
    );
    return allergies.any((allergy) {
      final needle = allergy.toLowerCase();
      return lowerIngredients.any((ingredient) => ingredient.contains(needle));
    });
  }

  static List<String> _toStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }

    if (value == null) {
      return const [];
    }

    return [value.toString()];
  }

  static String _joinRawText(dynamic value) {
    if (value is List) {
      return value.join('\n');
    }

    return value?.toString() ?? '';
  }
}
