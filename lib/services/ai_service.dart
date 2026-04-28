import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

enum AiProvider { openai, deepseek }

class AiService {
  String providerName(AiProvider provider) {
    return provider == AiProvider.deepseek ? 'DeepSeek' : 'OpenAI';
  }

  String actionTitle(String action) {
    switch (action) {
      case 'spiega':
        return 'Spiegazione';
      case 'riassumi':
        return 'Riassunto';
      case 'vocabolario':
        return 'Vocabolario';
      case 'traduci':
      default:
        return 'Traduzione';
    }
  }

  String buildPrompt(String action, String text) {
    switch (action) {
      case 'spiega':
        return 'Spiega in italiano questo estratto in modo chiaro e semplice:\n\n$text';

      case 'riassumi':
        return 'Riassumi in italiano questo estratto in poche frasi:\n\n$text';

      case 'vocabolario':
        return 'Estrai le parole o espressioni inglesi piÃ¹ utili da questo estratto. '
            'Per ciascuna scrivi: termine inglese, traduzione italiana, breve spiegazione:\n\n$text';

      case 'traduci':
      default:
        return 'Traduci in italiano in modo naturale e fedele questo estratto. '
            'Mantieni i nomi propri invariati. Rispondi solo con la traduzione:\n\n$text';
    }
  }

  String makeCacheKey({
    required String action,
    required String provider,
    required String text,
  }) {
    return '$provider|$action|$text';
  }

  Future<String> callSelectedAi({
    required AiProvider provider,
    required String prompt,
  }) async {
    switch (provider) {
      case AiProvider.deepseek:
        return callDeepSeek(prompt);
      case AiProvider.openai:
        return callOpenAi(prompt);
    }
  }

  Future<String> callOpenAi(String prompt) async {
    final openAiApiKey = dotenv.env['OPENAI_API_KEY']?.trim() ?? '';

    if (openAiApiKey.isEmpty) {
      throw Exception('Inserisci la tua OpenAI API key nel file .env.');
    }

    final response = await http.post(
      Uri.parse('https://api.openai.com/v1/responses'),
      headers: {
        'Authorization': 'Bearer $openAiApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'model': 'gpt-4.1-mini', 'input': prompt}),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Errore OpenAI ${response.statusCode}:\n${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    try {
      return data['output_text'] ?? data['output'][0]['content'][0]['text'];
    } catch (_) {
      throw Exception(
        'Formato risposta OpenAI non riconosciuto:\n${response.body}',
      );
    }
  }

  Future<String> callDeepSeek(String prompt) async {
    final deepSeekApiKey = dotenv.env['DEEPSEEK_API_KEY']?.trim() ?? '';

    if (deepSeekApiKey.isEmpty) {
      throw Exception('Inserisci la tua DeepSeek API key nel file .env.');
    }

    final response = await http.post(
      Uri.parse('https://api.deepseek.com/chat/completions'),
      headers: {
        'Authorization': 'Bearer $deepSeekApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {
            'role': 'system',
            'content':
                'Sei un assistente utile. Rispondi sempre in italiano, in modo chiaro e fedele alla richiesta.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'stream': false,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Errore DeepSeek ${response.statusCode}:\n${response.body}',
      );
    }

    final data = jsonDecode(response.body);

    try {
      return data['choices'][0]['message']['content'];
    } catch (_) {
      throw Exception(
        'Formato risposta DeepSeek non riconosciuto:\n${response.body}',
      );
    }
  }

  Future<String> getDeepSeekBalance() async {
    final deepSeekApiKey = dotenv.env['DEEPSEEK_API_KEY']?.trim() ?? '';

    if (deepSeekApiKey.isEmpty) {
      return 'DeepSeek: inserisci prima la API key.';
    }

    final response = await http.get(
      Uri.parse('https://api.deepseek.com/user/balance'),
      headers: {
        'Authorization': 'Bearer $deepSeekApiKey',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode != 200) {
      return 'DeepSeek errore ${response.statusCode}:\n${response.body}';
    }

    final data = jsonDecode(response.body);

    try {
      final isAvailable = data['is_available'];
      final infos = data['balance_infos'] as List;

      if (infos.isEmpty) {
        return 'DeepSeek disponibile: $isAvailable\nSaldo non trovato.';
      }

      final buffer = StringBuffer();
      buffer.writeln('DeepSeek disponibile: $isAvailable');

      for (final item in infos) {
        buffer.writeln(
          '${item['currency']}: totale ${item['total_balance']} Â· concesso ${item['granted_balance']} Â· ricaricato ${item['topped_up_balance']}',
        );
      }

      return buffer.toString();
    } catch (_) {
      return 'Risposta DeepSeek non riconosciuta:\n${response.body}';
    }
  }
}
