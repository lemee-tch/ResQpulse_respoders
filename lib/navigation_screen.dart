import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'incident_resolution.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _green = Color(0xFF2E9E3F);

/// Pre-navigation preview screen shown right after a responder accepts a
/// mission — matches the "Navigation" screenshot: a turn-instruction
/// banner, a route map (green = current position, red = destination),
/// and a bottom card with distance / ETA / estimated arrival plus a
/// "Start Navigation" button that hands off to the device's Maps app
/// for live turn-by-turn guidance.
///
/// Also offers "Mark as Resolved" once the responder is done on scene —
/// opens IncidentResolutionScreen to collect closing notes + an optional
/// photo. [incidentId] is passed through so that screen can eventually
/// call a real resolve endpoint (see IncidentResolutionScreen doc
/// comment for the current TODO(backend) status).
class NavigationScreen extends StatefulWidget {
  final double destinationLat;
  final double destinationLng;
  final String destinationLabel;
  final int? incidentId;

  const NavigationScreen({
    super.key,
    required this.destinationLat,
    required this.destinationLng,
    required this.destinationLabel,
    this.incidentId,
  });

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final MapController _mapController = MapController();

  late final LatLng _destination = LatLng(
    widget.destinationLat,
    widget.destinationLng,
  );

  LatLng? _origin;
  List<LatLng> _routePoints = [];

  double? _distanceKm;
  int? _durationMinutes;
  DateTime? _estimatedArrival;

  String _nextStepName = '';
  double _nextStepDistanceM = 0;
  IconData _nextStepIcon = Icons.straight;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final position = await _getCurrentLocation();
      final origin = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() => _origin = origin);

      await _fetchRoute(origin, _destination);

      if (!mounted) return;
      final bounds = LatLngBounds.fromPoints([origin, _destination]);
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.only(
            top: 40,
            bottom: 220,
            left: 40,
            right: 40,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw 'Location services are off.';

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permission denied.';
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw 'Location permission permanently denied.';
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 12));
  }

  /// OSRM public routing server — free, no API key, same pattern already
  /// used elsewhere in this app for OSM-backed geocoding. `steps=true`
  /// gives per-maneuver turn data for the banner at the top.
  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 12));
    if (response.statusCode != 200) throw 'Could not calculate route.';

    final data = jsonDecode(response.body);
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) throw 'No route found.';

    final route = routes.first;
    final coords = route['geometry']['coordinates'] as List;
    final points = coords
        .map<LatLng>(
          (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        )
        .toList();

    final distanceMeters = (route['distance'] as num).toDouble();
    final durationSeconds = (route['duration'] as num).toDouble();
    final durationMinutes = (durationSeconds / 60).round();

    // Pull the first real turn (skip 'depart') for the top banner.
    String stepName = widget.destinationLabel;
    double stepDistance = distanceMeters;
    IconData stepIcon = Icons.straight;

    final legs = route['legs'] as List?;
    if (legs != null && legs.isNotEmpty) {
      final steps = legs.first['steps'] as List?;
      if (steps != null && steps.isNotEmpty) {
        final firstStep = steps.first;
        final name = (firstStep['name'] as String?)?.trim();
        stepName = (name != null && name.isNotEmpty)
            ? name
            : widget.destinationLabel;
        stepDistance =
            (firstStep['distance'] as num?)?.toDouble() ?? distanceMeters;

        final maneuver = firstStep['maneuver'] as Map<String, dynamic>?;
        stepIcon = _iconForModifier(maneuver?['modifier'] as String?);
      }
    }

    if (!mounted) return;
    setState(() {
      _routePoints = points;
      _distanceKm = distanceMeters / 1000;
      _durationMinutes = durationMinutes;
      _estimatedArrival = DateTime.now().add(
        Duration(minutes: durationMinutes),
      );
      _nextStepName = stepName;
      _nextStepDistanceM = stepDistance;
      _nextStepIcon = stepIcon;
    });
  }

  IconData _iconForModifier(String? modifier) {
    switch (modifier) {
      case 'left':
        return Icons.turn_left;
      case 'right':
        return Icons.turn_right;
      case 'slight left':
        return Icons.turn_slight_left;
      case 'slight right':
        return Icons.turn_slight_right;
      case 'sharp left':
        return Icons.turn_sharp_left;
      case 'sharp right':
        return Icons.turn_sharp_right;
      case 'uturn':
        return Icons.u_turn_left;
      default:
        return Icons.straight;
    }
  }

  String _formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String _formatTime(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour12:$minute $period';
  }

  /// Hands off to the device's Maps app for live turn-by-turn guidance —
  /// same "launch an external app via url_launcher" pattern already used
  /// for phone calls elsewhere in this app (sos.dart, hotlines.dart).
  Future<void> _startNavigation() async {
    final lat = widget.destinationLat;
    final lng = widget.destinationLng;

    // Android: opens Google Maps directly in turn-by-turn driving mode.
    final androidNavUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
    // Universal fallback (iOS / no Maps app / web): Google Maps directions.
    final webNavUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );

    try {
      if (await canLaunchUrl(androidNavUri)) {
        await launchUrl(androidNavUri);
        return;
      }
      if (await canLaunchUrl(webNavUri)) {
        await launchUrl(webNavUri, mode: LaunchMode.externalApplication);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No maps app available on this device.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not start navigation: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Opens the closing-notes / optional-photo screen. Reachable any time
  /// once a route has resolved — a responder may mark resolved without
  /// ever tapping "Start Navigation" (e.g. they drove there manually).
  void _handleMarkResolved() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => IncidentResolutionScreen(
          incidentId: widget.incidentId,
          incidentLabel: widget.destinationLabel,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF1A1A2E),
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      'Navigation',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48), // balances the back button
                ],
              ),
            ),

            // ── Turn instruction banner ──
            Container(
              width: double.infinity,
              color: _green,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(_nextStepIcon, color: Colors.white, size: 34),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isLoading ? 'Calculating route...' : _nextStepName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (!_isLoading)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              _formatDistance(_nextStepDistanceM),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Map + bottom card ──
            Expanded(
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _destination,
                      initialZoom: 14,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.resqpulse.responder',
                      ),
                      if (_routePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _routePoints,
                              strokeWidth: 5,
                              color: _navy,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _destination,
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.location_pin,
                              color: Color(0xFFDC2626),
                              size: 36,
                            ),
                          ),
                          if (_origin != null)
                            Marker(
                              point: _origin!,
                              width: 20,
                              height: 20,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _green,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),

                  if (_isLoading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withOpacity(0.5),
                        child: const Center(
                          child: CircularProgressIndicator(color: _navy),
                        ),
                      ),
                    ),

                  if (_errorMessage != null && !_isLoading)
                    Positioned(
                      top: 12,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),

                  // ── Bottom info card ──
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black12,
                            blurRadius: 16,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      _distanceKm != null
                                          ? '${_distanceKm!.toStringAsFixed(1)} km'
                                          : '—',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Distance',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Text(
                                      _durationMinutes != null
                                          ? '$_durationMinutes min'
                                          : '—',
                                      style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF1A1A2E),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'ETA',
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Divider(color: Colors.grey[200], height: 1),
                          const SizedBox(height: 16),
                          Text(
                            _estimatedArrival != null
                                ? _formatTime(_estimatedArrival!)
                                : '—',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A1A2E),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Estimated Arrival',
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: (_isLoading || _distanceKm == null)
                                  ? null
                                  : _startNavigation,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _navy,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: const Text(
                                'START NAVIGATION',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton(
                              onPressed: _handleMarkResolved,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: _green,
                                  width: 1.6,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28),
                                ),
                              ),
                              child: const Text(
                                'MARK AS RESOLVED',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: _green,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
