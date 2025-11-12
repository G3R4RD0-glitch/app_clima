import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'weather_model.dart';

class WeatherException implements Exception {
  final String message;
  WeatherException(this.message);

  @override
  String toString() => message;
}

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final String _host = 'api.openweathermap.org';
  final Duration _timeout = const Duration(seconds: 8);
  final int _maxRetries = 3;

  Future<Weather> fetchWeather(String city) async {
    final apiKey = dotenv.env['OPENWEATHER_API_KEY'] ?? '';
    if (apiKey.isEmpty) {
      throw WeatherException(
        'API key no configurada. Agrega OPENWEATHER_API_KEY en assets/.env',
      );
    }

    final sanitizedCity = _sanitizeCity(city);

    final params = <String, String>{
      'q': sanitizedCity, // ej: "Querétaro,MX"
      'appid': apiKey,
      'units': 'metric',
      'lang': 'es',
    };

    final uri = Uri.https(_host, '/data/2.5/weather', params);

    int attempt = 0;
    while (true) {
      attempt++;

      try {
        final resp = await _client.get(uri).timeout(_timeout);

        if (resp.statusCode == 200) {
          final jsonMap = jsonDecode(resp.body) as Map<String, dynamic>;
          return Weather.fromJson(jsonMap);
        } else if (resp.statusCode == 401) {
          throw WeatherException(
            'No autorizado (401). Revisa tu API key de OpenWeatherMap.',
          );
        } else if (resp.statusCode == 404) {
          throw WeatherException('Ciudad no encontrada (404).');
        } else if (resp.statusCode == 429) {
          // demasiadas peticiones: retry exponencial
          if (attempt >= _maxRetries) {
            throw WeatherException(
              'Demasiadas peticiones (429). Intenta de nuevo más tarde.',
            );
          }
          await _waitWithBackoff(attempt);
          continue;
        } else {
          throw WeatherException(
            'Error del servidor (${resp.statusCode}).',
          );
        }
      } on TimeoutException {
        if (attempt >= _maxRetries) {
          rethrow;
        }
        await _waitWithBackoff(attempt);
      } on SocketException {
        if (attempt >= _maxRetries) {
          throw WeatherException('Sin conexión a internet.');
        }
        await _waitWithBackoff(attempt);
      }
    }
  }

  String _sanitizeCity(String input) {
    var value = input.trim();
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    value =
        value.replaceAll(RegExp(r'[^a-zA-Z0-9áéíóúÁÉÍÓÚñÑ\s,.-]'), '');
    return value;
  }

  Future<void> _waitWithBackoff(int attempt) async {
    // retry exponencial: 1s, 2s, 4s
    final seconds = 1 << (attempt - 1);
    await Future.delayed(Duration(seconds: seconds));
  }
}
