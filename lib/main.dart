import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'weather_model.dart';
import 'weather_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: "assets/.env");

  // Debug opcional: ver la key en consola (luego bórralo)
  debugPrint('API KEY LEÍDA: ${dotenv.env['OPENWEATHER_API_KEY']}');

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clima (OpenWeatherMap)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const WeatherPage(),
    );
  }
}

class WeatherPage extends StatefulWidget {
  const WeatherPage({super.key});

  @override
  State<WeatherPage> createState() => _WeatherPageState();
}

class _WeatherPageState extends State<WeatherPage> {
  final _cityController = TextEditingController();
  final _service = WeatherService();

  bool _isLoading = false;
  String? _errorMessage;
  Weather? _weather;

  Weather? _cachedWeather;
  DateTime? _lastFetchAt;

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final rawCity = _cityController.text;
    final city = rawCity.trim();

    if (city.isEmpty) {
      setState(() {
        _errorMessage = 'Ingresa una ciudad.';
        _weather = null;
      });
      return;
    }

    final regex = RegExp(r"^[a-zA-ZáéíóúÁÉÍÓÚñÑ\s,]+(,[A-Za-z]{2})?$");
    if (!regex.hasMatch(city)) {
      setState(() {
        _errorMessage =
        'Formato inválido. Usa letras, espacios y opcionalmente ,PA (ej: Querétaro,MX).';
        _weather = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final now = DateTime.now();

      if (_cachedWeather != null &&
          _lastFetchAt != null &&
          now.difference(_lastFetchAt!).inSeconds < 60 &&
          _cachedWeather!.city.toLowerCase() == city.toLowerCase()) {
        setState(() {
          _weather = _cachedWeather;
          _isLoading = false;
        });
        return;
      }

      final weather = await _service.fetchWeather(city);
      setState(() {
        _weather = weather;
        _cachedWeather = weather;
        _lastFetchAt = now;
      });
    } on WeatherException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _weather = _cachedWeather;
      });
    } on TimeoutException {
      setState(() {
        _errorMessage =
        'Se agotó el tiempo de espera. Revisa tu conexión a internet.';
        _weather = _cachedWeather;
      });
    } catch (_) {
      setState(() {
        _errorMessage = 'Ocurrió un error inesperado.';
        _weather = _cachedWeather;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Cargando clima...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
            ),
            if (_weather != null) ...[
              const SizedBox(height: 16),
              const Text(
                'Mostrando el último dato cacheado:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              _WeatherCard(weather: _weather!),
            ],
          ],
        ),
      );
    }

    if (_weather == null) {
      return const Center(
        child: Text(
          'Busca una ciudad para ver el clima.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Center(
      child: _WeatherCard(weather: _weather!),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clima (OpenWeatherMap)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _cityController,
              decoration: const InputDecoration(
                labelText: 'Ciudad (ej: Querétaro,MX)',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search),
                label: const Text('Buscar clima'),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }
}

class _WeatherCard extends StatelessWidget {
  final Weather weather;

  const _WeatherCard({required this.weather});

  @override
  Widget build(BuildContext context) {
    final city = weather.city.trim();
    final description = weather.description.trim();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              city,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '${weather.temperature.toStringAsFixed(1)} °C',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text('Sensación: ${weather.feelsLike.toStringAsFixed(1)} °C'),
            const SizedBox(height: 8),
            Text('Mín: ${weather.tempMin.toStringAsFixed(1)} °C'),
            Text('Máx: ${weather.tempMax.toStringAsFixed(1)} °C'),
            const SizedBox(height: 8),
            Text('Humedad: ${weather.humidity}%'),
          ],
        ),
      ),
    );
  }
}
