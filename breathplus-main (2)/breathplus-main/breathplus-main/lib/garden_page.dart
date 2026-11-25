import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// A plant the signed-in user has actually collected.
class GardenPlant {
  final int id;
  final String slug;
  final String name;
  final String plantKey;
  final String stage;
  final int completedSessions;
  final int sessionsPerStage;
  final int? progressToNext;

  const GardenPlant({
    required this.id,
    required this.slug,
    required this.name,
    required this.plantKey,
    required this.stage,
    required this.completedSessions,
    required this.sessionsPerStage,
    required this.progressToNext,
  });

  factory GardenPlant.fromJson(Map<String, dynamic> json) {
    final progress = json['progress'] as Map<String, dynamic>;

    return GardenPlant(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
      plantKey: json['plant_key'] as String,
      stage: progress['stage'] as String,
      completedSessions: progress['completed_sessions'] as int? ?? 0,
      sessionsPerStage: progress['sessions_per_stage'] as int? ?? 10,
      progressToNext: progress['progress_to_next'] as int?,
    );
  }
}

class GardenPage extends StatefulWidget {
  /// Pass the same API base URL, user ID and access token used by the rest
  /// of the signed-in Breathe+ app.
  final String apiBaseUrl;
  final String userId;
  final String accessToken;

  const GardenPage({
    super.key,
    required this.apiBaseUrl,
    required this.userId,
    required this.accessToken,
  });

  @override
  State<GardenPage> createState() => _GardenPageState();
}

class _GardenPageState extends State<GardenPage> {
  bool _loading = true;
  String? _error;
  List<GardenPlant> _plants = [];

  // Map the plant_key values from the techniques table to your final image
  // asset paths. Change the filenames here to match the images you add.
  static const Map<String, String> _plantImages = {
  'sunflower': 'assets/images/plants/sunflower.png',
  'periwinkle': 'assets/images/plants/periwinkle.png',
  'bhrama': 'assets/images/plants/bhrama.png',
  'rose': 'assets/images/plants/rose.png',
  'tulips': 'assets/images/plants/tulips.png',
  'dhalia': 'assets/images/plants/dhalia.png',
  'orchids': 'assets/images/plants/orchids.png',
  'daisy': 'assets/images/plants/daisy.png',
  'forget_me_not': 'assets/images/plants/forget_me_not.png',
  };

  static const List<Offset> _potPositions = [
    Offset(0.211, 0.300),
    Offset(0.500, 0.300),
    Offset(0.789, 0.300),
    Offset(0.211, 0.508),
    Offset(0.500, 0.508),
    Offset(0.789, 0.508),
    Offset(0.211, 0.713),
    Offset(0.500, 0.713),
    Offset(0.789, 0.713),
  ];

  @override
  void initState() {
    super.initState();
    _loadCollectedPlants();
  }

  Future<void> _loadCollectedPlants() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final baseUrl = widget.apiBaseUrl.replaceFirst(RegExp(r'/+$'), '');
      final uri = Uri.parse(
        '$baseUrl/api/users/${Uri.encodeComponent(widget.userId)}/techniques',
      );

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.accessToken}',
        },
      );

      if (response.statusCode != 200) {
        throw Exception(
          'Could not load garden plants (HTTP ${response.statusCode}). '
          '${response.body}',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final techniques = decoded['techniques'] as List<dynamic>? ?? [];

      final collected = techniques
          .map((item) => GardenPlant.fromJson(item as Map<String, dynamic>))
          .where((plant) =>
              plant.stage == 'collected' ||
              plant.stage == 'grown' ||
              plant.stage == 'flourishing')
          .toList();

      if (!mounted) return;
      setState(() {
        _plants = collected;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _buildPlant(GardenPlant plant, double width) {
    final imagePath = _plantImages[plant.plantKey];

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (imagePath != null)
          Expanded(
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.local_florist,
                color: Color(0xFFFFE7C4),
                size: 48,
              ),
            ),
          )
        else
          const Expanded(
            child: Icon(
              Icons.local_florist,
              color: Color(0xFFFFE7C4),
              size: 48,
            ),
          ),
        Text(
          plant.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFFFE7C4),
            fontSize: 9,
            fontWeight: FontWeight.bold,
            shadows: [
              Shadow(color: Colors.black87, blurRadius: 4),
            ],
          ),
        ),
        Text(
          plant.stage[0].toUpperCase() + plant.stage.substring(1),
          style: const TextStyle(
            color: Color(0xFFA6DDB8),
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildPlantAtPosition(
    GardenPlant plant,
    int index,
    double width,
    double height,
  ) {
    final position = _potPositions[index];

    return Positioned(
      left: width * position.dx - width * 0.105,
      top: height * position.dy - height * 0.055,
      width: width * 0.21,
      height: height * 0.15,
      child: _buildPlant(plant, width),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/garden-wall.png',
              fit: BoxFit.fill,
              errorBuilder: (_, _, _) => Container(
                color: const Color(0xFF58351F),
                alignment: Alignment.center,
                child: const Text(
                  'Garden background not found',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),

            Positioned(
              top: height * 0.035,
              left: 0,
              right: 0,
              child: const Text(
                'My Garden',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Georgia',
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFE9C8),
                  shadows: [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 7,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),

            if (!_loading && _error == null && _plants.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Your garden is waiting to grow. Complete a breathing '
                    'technique to collect your first plant!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFFFE9C8),
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
                ),
              ),

            // Display only the plants returned as collected by the API.
            // The background has nine pot positions; additional plants are
            // currently limited to the first nine.
            for (int i = 0; i < _plants.length && i < _potPositions.length; i++)
              _buildPlantAtPosition(_plants[i], i, width, height),

            if (_loading)
              const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFF8FE3A5),
                ),
              ),

            if (_error != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Could not load your garden.',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFFD7C2),
                          fontSize: 11,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loadCollectedPlants,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
