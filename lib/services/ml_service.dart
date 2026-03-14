import 'dart:convert';
import 'package:http/http.dart' as http;

class MLPrediction {
  final String category;
  final String severity;
  final double categoryConfidence;
  final double severityConfidence;

  MLPrediction({
    required this.category,
    required this.severity,
    required this.categoryConfidence,
    required this.severityConfidence,
  });
}

class MLService {
  // Change this to your machine's IP if running on a physical device
  // e.g. 'http://192.168.1.100:5000'
  static const String _baseUrl = 'http://127.0.0.1:5000';

  /// Returns null if the ML server is unreachable or returns an error.
  static Future<MLPrediction?> predict(String description) async {
    try {
      final response = await http
          .post(
            Uri.parse('$_baseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'description': description}),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        // Parse category scores
        final catScores =
            (data['category_scores'] as Map<String, dynamic>?) ?? {};
        final topCatScore = catScores.values.fold<double>(
          0,
          (prev, v) => (v as double) > prev ? v : prev,
        );

        // Parse severity scores
        final sevScores =
            (data['severity_scores'] as Map<String, dynamic>?) ?? {};
        final topSevScore = sevScores.values.fold<double>(
          0,
          (prev, v) => (v as double) > prev ? v : prev,
        );

        // Map ML model labels → app labels
        final rawCategory = data['category'] as String? ?? '';
        final rawSeverity = data['severity'] as String? ?? '';

        return MLPrediction(
          category: _mapCategory(rawCategory),
          severity: _mapSeverity(rawSeverity),
          categoryConfidence: topCatScore,
          severityConfidence: topSevScore,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Check if the ML server is running
  static Future<bool> isServerOnline() async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Label mappers ──────────────────────────────────────────────────────────
  // Maps the ML model's output labels to the app's category/severity values.

  static String _mapCategory(String raw) {
    final r = raw.toLowerCase();
    if (r.contains('flood')) return 'Flooding';
    if (r.contains('fire')) return 'Fire';
    if (r.contains('medical') || r.contains('health')) {
      return 'Medical Emergency';
    }
    if (r.contains('road') ||
        r.contains('infra') ||
        r.contains('damage') ||
        r.contains('obstruction')) {
      return 'Infrastructure Damage';
    }
    // Fallback: return as-is if it already matches one of the app's categories
    const appCategories = [
      'Flooding',
      'Fire',
      'Medical Emergency',
      'Infrastructure Damage',
    ];
    if (appCategories.contains(raw)) return raw;
    return 'Infrastructure Damage'; // safe fallback
  }

  static String _mapSeverity(String raw) {
    final r = raw.toLowerCase();
    if (r == 'critical' || r == 'high') return 'High';
    if (r == 'moderate' || r == 'medium') return 'Medium';
    if (r == 'low') return 'Low';
    return 'Medium'; // safe fallback
  }
}