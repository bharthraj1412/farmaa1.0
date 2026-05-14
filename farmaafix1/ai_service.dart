import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// OpenRouter-powered AI service for Farmaa agricultural advisor.
/// Uses the free LLaMA model via OpenRouter API.
class AIService {
  AIService._();
  static final AIService instance = AIService._();

  // ── OpenRouter config ────────────────────────────────────────────────────
  static const String _apiKey =
      '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';
  static const String _model = 'meta-llama/llama-3.1-8b-instruct:free';
  static const String _fallbackModel = 'mistralai/mistral-7b-instruct:free';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://openrouter.ai/api/v1',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 90),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
        'HTTP-Referer': 'https://farmaa.app',
        'X-Title': 'Farmaa Agricultural AI',
      },
    ),
  );

  // ── System prompt ────────────────────────────────────────────────────────
  static const String _systemPrompt = '''You are Farmaa AI, an expert agricultural assistant for Indian farmers. 
Your specialties:
- Grain market prices in India (Rice, Wheat, Millet/Ragi/Bajra, Barley, Sorghum/Jowar, Maize, Pulses/Dal)
- Crop cultivation and yield optimization techniques
- Pest and disease identification and management using IPM
- Government schemes: PM-KISAN, PMFBY crop insurance, KCC loans, Soil Health Card, PM-KUSUM
- Seasonal farming calendar for Kharif, Rabi, and Zaid seasons
- Tamil Nadu APMC market prices and local context
- Farmaa marketplace guidance (listing crops, placing orders, pricing)

Rules:
- Keep responses under 180 words, practical, and actionable
- Always use Indian Rupees (₹) for prices
- Provide specific numbers when discussing prices or yields
- Default to Tamil Nadu/South India context unless user specifies otherwise
- End with 1 actionable tip when relevant''';

  // ── Main chat method ─────────────────────────────────────────────────────

  Future<({String content, List<String> suggestions})> getChatResponse(
      List<Map<String, String>> messages) async {
    try {
      final result = await _callApi(messages, _model);
      return result;
    } on DioException catch (e) {
      debugPrint('[AIService] Primary model failed: ${e.message}');
      // Try fallback model
      try {
        final result = await _callApi(messages, _fallbackModel);
        return result;
      } catch (_) {
        return _offlineResponse(messages.last['content'] ?? '');
      }
    } catch (e) {
      debugPrint('[AIService] Unexpected error: $e');
      return _offlineResponse(messages.last['content'] ?? '');
    }
  }

  Future<({String content, List<String> suggestions})> _callApi(
      List<Map<String, String>> messages, String model) async {
    final apiMessages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt},
      ...messages.map((m) => {'role': m['role'] ?? 'user', 'content': m['content'] ?? ''}),
    ];

    final response = await _dio.post('/chat/completions', data: {
      'model': model,
      'messages': apiMessages,
      'max_tokens': 512,
      'temperature': 0.7,
      'top_p': 0.9,
    });

    final content =
        (response.data['choices'][0]['message']['content'] as String).trim();
    final suggestions = _buildSuggestions(messages.last['content'] ?? '');

    debugPrint('[AIService] Response from $model: ${content.length} chars');
    return (content: content, suggestions: suggestions);
  }

  // ── Offline fallback (knowledge base) ────────────────────────────────────

  ({String content, List<String> suggestions}) _offlineResponse(String query) {
    final q = query.toLowerCase();

    if (q.contains('price') || q.contains('rate') || q.contains('market')) {
      return (
        content: '📊 **Current Market Rates (Approximate)**\n\n'
            '• Rice (Sona Masoori): ₹32–38/kg\n'
            '• Wheat: ₹24–28/kg\n'
            '• Ragi (Finger Millet): ₹30–36/kg\n'
            '• Bajra (Pearl Millet): ₹22–26/kg\n'
            '• Toor Dal: ₹85–100/kg\n\n'
            '💡 Check the Market Prices tab for live APMC data.\n\n'
            '_Note: AI connection unavailable. Showing cached data._',
        suggestions: ['Rice prices', 'Wheat rates', 'Millet market', 'Pulse prices']
      );
    }

    if (q.contains('pest') || q.contains('disease') || q.contains('insect')) {
      return (
        content: '🐛 **Pest Management Tips**\n\n'
            '• Use Trichogramma biocontrol for stem borers\n'
            '• Neem oil spray (5ml/L) for aphids and mites\n'
            '• Pheromone traps for monitoring moth populations\n'
            '• Crop rotation breaks pest cycles\n'
            '• Apply Tricyclazole for rice blast disease\n\n'
            '💡 Always scout fields every 3–4 days during critical growth stages.',
        suggestions: ['Rice pests', 'Organic control', 'Spray schedule', 'IPM methods']
      );
    }

    if (q.contains('scheme') || q.contains('subsidy') || q.contains('kisan')) {
      return (
        content: '🏛️ **Government Schemes for Farmers**\n\n'
            '• **PM-KISAN**: ₹6,000/year in 3 installments → pmkisan.gov.in\n'
            '• **PMFBY**: Crop insurance at 1.5–2% premium\n'
            '• **KCC**: Farm loans at 4% interest rate\n'
            '• **Soil Health Card**: Free soil testing + recommendations\n'
            '• **PM-KUSUM**: Solar pump subsidy up to 60%\n\n'
            '💡 Visit your nearest CSC or Block Agricultural Office to apply.',
        suggestions: ['PM-KISAN status', 'Crop insurance', 'KCC application', 'Soil card']
      );
    }

    return (
      content: '👋 **Farmaa AI Advisor** (Offline Mode)\n\n'
          'I\'m currently unable to connect to my knowledge base. '
          'Please check your internet connection and try again.\n\n'
          'While offline, I can still help with:\n'
          '• Market price estimates\n'
          '• Basic pest management tips\n'
          '• Government scheme information\n\n'
          'Try asking: "What\'s the price of rice?" or "How do I control pests?"',
      suggestions: ['Market prices', 'Pest control', 'Government schemes', 'Crop advice']
    );
  }

  // ── Suggestion engine ─────────────────────────────────────────────────────

  List<String> _buildSuggestions(String query) {
    final q = query.toLowerCase();

    if (q.contains('price') || q.contains('rate') || q.contains('mandi')) {
      return ['Rice APMC price', 'Wheat market rate', 'Millet prices today', 'Dal prices'];
    }
    if (q.contains('pest') || q.contains('disease') || q.contains('fungus') || q.contains('blight')) {
      return ['Organic pest control', 'Chemical spray guide', 'Resistant varieties', 'IPM strategy'];
    }
    if (q.contains('yield') || q.contains('grow') || q.contains('cultivat') || q.contains('harvest')) {
      return ['Soil testing labs', 'Fertilizer schedule', 'Best sowing time', 'High-yield varieties'];
    }
    if (q.contains('soil') || q.contains('fertilizer') || q.contains('npk') || q.contains('compost')) {
      return ['Soil health card', 'Organic farming', 'Vermicompost tips', 'NPK ratio guide'];
    }
    if (q.contains('scheme') || q.contains('subsidy') || q.contains('government') || q.contains('loan')) {
      return ['PM-KISAN eligibility', 'PMFBY enrollment', 'KCC loan apply', 'Solar pump subsidy'];
    }
    if (q.contains('millet') || q.contains('ragi') || q.contains('bajra') || q.contains('thinai')) {
      return ['Millet varieties', 'Ragi cultivation', 'Millet market price', 'Millet benefits'];
    }
    if (q.contains('order') || q.contains('buy') || q.contains('sell')) {
      return ['List a crop', 'Order tracking', 'Payment help', 'Pricing strategy'];
    }
    if (q.contains('weather') || q.contains('rain') || q.contains('monsoon')) {
      return ['Kharif crops guide', 'Rabi season crops', 'Drought management', 'IMD forecast'];
    }

    return [
      'Market prices today',
      'Crop yield tips',
      'Government schemes',
      'Pest management',
      'Soil health',
    ];
  }
}
