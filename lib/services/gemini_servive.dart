import 'dart:convert';
import 'package:http/http.dart' as http;

// No changes needed to your models, they are actually perfect.
class GeminiAnalysis {
  final String riskLevel;
  final String riskSummary;
  final String recommendedAction;
  final String urgency;
  final String additionalNotes;

  GeminiAnalysis({
    required this.riskLevel,
    required this.riskSummary,
    required this.recommendedAction,
    required this.urgency,
    required this.additionalNotes,
  });

  factory GeminiAnalysis.fromJson(Map<String, dynamic> j) => GeminiAnalysis(
    riskLevel: j['risk_level'] ?? 'UNKNOWN',
    riskSummary: j['risk_summary'] ?? '',
    recommendedAction: j['recommended_action'] ?? '',
    urgency: j['urgency'] ?? 'Unknown',
    additionalNotes: j['additional_notes'] ?? '',
  );
}

class SituationBriefing {
  final String overallStatus;
  final String summary;
  final String topPriority;
  final String recommendation;

  SituationBriefing({
    required this.overallStatus,
    required this.summary,
    required this.topPriority,
    required this.recommendation,
  });

  factory SituationBriefing.fromJson(Map<String, dynamic> j) =>
      SituationBriefing(
        overallStatus: j['overall_status'] ?? 'NORMAL',
        summary: j['summary'] ?? '',
        topPriority: j['top_priority'] ?? '',
        recommendation: j['recommendation'] ?? '',
      );
}

class GeminiService {
  // ⚠️ NOTE: I noticed you updated your key.
  // If "theres a flood in my area lol" is a test, the AI needs
  // to be told explicitly NOT to ignore casual language.
  static const String _apiKey = 'AIzaSyAWW48umWsFvxVIUP-nSZHXN0A0r4T4rjU';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';

  static Future<GeminiAnalysis?> analyzeReport({
    required String description,
    required String category,
    required String severity,
    required String location,
  }) async {
    // We make the prompt super direct so it understands slang like "lol"
    // but still gives back professional data.
    final prompt =
        '''
Directly analyze this incident for BDRRMC Philippines. 
Even if the description is casual, identify the core problem.

DATA:
Category: $category
Severity: $severity
Location: $location
Text: $description

Return JSON:
{
  "risk_level": "use LOW, MEDIUM, HIGH, or CRITICAL",
  "risk_summary": "one short sentence",
  "recommended_action": "what should the barangay do first?",
  "urgency": "how fast?",
  "additional_notes": "none"
}
''';

    return await _callGemini<GeminiAnalysis>(
      prompt: prompt,
      fromJson: GeminiAnalysis.fromJson,
    );
  }

  static Future<SituationBriefing?> generateSituationBriefing({
    required List<Map<String, String>> reports,
  }) async {
    if (reports.isEmpty) return null;

    final reportsList = reports
        .map((r) => "- ${r['category']}: ${r['description']}")
        .join('\n');

    final prompt =
        '''
Summarize these reports for a Dashboard. 
Reports:
$reportsList

Return JSON:
{
  "overall_status": "NORMAL, ALERT, or EMERGENCY",
  "summary": "Short summary",
  "top_priority": "The biggest problem",
  "recommendation": "What to do"
}
''';

    return await _callGemini<SituationBriefing>(
      prompt: prompt,
      fromJson: SituationBriefing.fromJson,
    );
  }

  static Future<T?> _callGemini<T>({
    required String prompt,
    required T Function(Map<String, dynamic>) fromJson,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            'temperature':
                0.5, // Increased slightly so it's not "stiff" with slang
            'response_mime_type': 'application/json',
          },
        }),
      );

      if (response.statusCode != 200) {
        print(
          "API ERROR: ${response.body}",
        ); // Check if quota exceeded or key blocked
        return null;
      }

      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];

      if (text == null) return null;

      return fromJson(jsonDecode(text.trim()));
    } catch (e) {
      print("SERVICE ERROR: $e");
      return null;
    }
  }
}