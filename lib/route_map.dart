import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Shows the SPECIFIC incident location only (single marker — no other
/// incidents, no evac centers) plus a route line from the responder's
/// current GPS position to that incident, using OSRM (free, no API key).
///
/// Drop this in wherever the gray map placeholder currently sits on the
/// Incident Details screen, e.g.:
///
///   IncidentRouteMap(
///     incidentLat: incident.latitude,
///     incidentLng: incident.longitude,
///     incidentLabel: incident.location,
///   )
class IncidentRouteMap extends StatefulWidget {
  final double incidentLat;
  final double incidentLng;
  final String? incidentLabel;
  final double height;

  const IncidentRouteMap({
    super.key,
    required this.incidentLat,
    required this.incidentLng,
    this.incidentLabel,
    this.height = 220,
  });

  @override
  State<IncidentRouteMap> createState() => _IncidentRouteMapState();
}

class _IncidentRouteMapState extends State<IncidentRouteMap> {
  final MapController _mapController = MapController();

  LatLng? _myLocation;
  List<LatLng> _routePoints = [];
  double? _distanceKm;
  int? _durationMinutes;

  bool _isLoading = true;
  String? _errorMessage;

  late final LatLng _incidentPoint = LatLng(
    widget.incidentLat,
    widget.incidentLng,
  );

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
      setState(() => _myLocation = origin);

      await _fetchRoute(origin, _incidentPoint);

      if (!mounted) return;
      _fitBoundsToRoute(origin, _incidentPoint);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Route couldn't be resolved (no GPS, etc.) — still show the
        // incident marker on its own, just without a route line.
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Position> _getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are off.';
    }

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

  /// OSRM public demo routing server — free, no API key. Same "free
  /// public OSM-backed service, no key required" pattern already used
  /// for Nominatim geocoding elsewhere in this app.
  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 12));

    if (response.statusCode != 200) {
      throw 'Could not calculate route.';
    }

    final data = jsonDecode(response.body);
    final routes = data['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw 'No route found.';
    }

    final route = routes.first;
    final coords = route['geometry']['coordinates'] as List;
    final points = coords
        .map<LatLng>(
          (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
        )
        .toList();

    final distanceMeters = (route['distance'] as num).toDouble();
    final durationSeconds = (route['duration'] as num).toDouble();

    if (!mounted) return;
    setState(() {
      _routePoints = points;
      _distanceKm = distanceMeters / 1000;
      _durationMinutes = (durationSeconds / 60).round();
    });
  }

  void _fitBoundsToRoute(LatLng a, LatLng b) {
    final bounds = LatLngBounds.fromPoints([a, b]);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _incidentPoint,
                    initialZoom: 15,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.resqpulse.responder',
                    ),

                    // Route line (only drawn once resolved)
                    if (_routePoints.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: _routePoints,
                            strokeWidth: 4,
                            color: const Color(0xFF1857C4),
                          ),
                        ],
                      ),

                    MarkerLayer(
                      markers: [
                        // The incident — the ONLY incident marker shown.
                        Marker(
                          point: _incidentPoint,
                          width: 40,
                          height: 40,
                          child: const Icon(
                            Icons.location_pin,
                            color: Color(0xFFDC2626),
                            size: 40,
                          ),
                        ),

                        // Responder's current position, if resolved.
                        if (_myLocation != null)
                          Marker(
                            point: _myLocation!,
                            width: 22,
                            height: 22,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF1A73E8),
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
                      color: Colors.white.withOpacity(0.6),
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        if (_distanceKm != null && _durationMinutes != null)
          Row(
            children: [
              Icon(
                Icons.directions_car_outlined,
                size: 15,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 5),
              Text(
                '${_distanceKm!.toStringAsFixed(1)} km · $_durationMinutes min drive',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          )
        else if (_errorMessage != null && !_isLoading)
          Row(
            children: [
              Icon(Icons.info_outline, size: 15, color: Colors.grey[400]),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  'Route unavailable — showing incident location only.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
