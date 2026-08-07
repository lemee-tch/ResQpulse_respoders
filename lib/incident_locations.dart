import 'dart:math' show pi, cos, sin;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

// Kept in sync with the palette used across the rest of the responder app
// (see responder_home.dart) — duplicated here (rather than imported) since
// those are library-private consts and this screen lives in its own file.
const Color _gradientTop = Color(0xFF00308F);

const Map<String, Color> _statusColors = {
  'pending': Color(0xFFF59E0B),
  'responding': Color(0xFF3B82F6),
  'acknowledged': Color(0xFF3B82F6),
  'resolved': Color(0xFF10B981),
};

String _statusLabel(String? status) {
  if (status == null || status.isEmpty) return 'Pending';
  return status[0].toUpperCase() + status.substring(1);
}

// ══════════════════════════════════════════════════════════════════
// Incident Locations — real map (flutter_map + OSM, same free stack
// used elsewhere in this app), showing every non-resolved incident
// assigned to this responder's agency as a colored pin — including SOS
// Emergency alerts — synced with a list below.
//
// `onOpenDetail` is a callback rather than a direct Navigator.push to an
// IncidentDetailScreen so this file has zero dependency on whatever
// detail-screen implementation responder_home.dart is currently using —
// the caller decides what "open detail" means.
// ══════════════════════════════════════════════════════════════════

class IncidentLocationsScreen extends StatefulWidget {
  final List<dynamic> incidents;
  final bool isLoading;
  final String? errorMessage;
  final Future<void> Function() onRetry;
  final void Function(Map<String, dynamic> incident) onOpenDetail;

  const IncidentLocationsScreen({
    super.key,
    required this.incidents,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.onOpenDetail,
  });

  @override
  State<IncidentLocationsScreen> createState() =>
      _IncidentLocationsScreenState();
}

class _IncidentLocationsScreenState extends State<IncidentLocationsScreen> {
  final MapController _mapController = MapController();
  final LatLng _rosalesCenter = const LatLng(15.8952, 120.6263);

  int? _selectedIndex;
  LatLng? _myLocation;
  bool _isLocating = false;

  static const Map<String, String> _typeEmoji = {
    'Fire': '🔥',
    'Flood': '🌊',
    'Earthquake': '🏚️',
    'Accident': '🚗',
    'Medical Emergency': '🚑',
    'Landslide': '⛰️',
    'SOS Emergency': '🆘',
  };

  static const Map<String, Color> _statusPinColors = {
    'pending': Color(0xFFB45309),
    'acknowledged': Color(0xFF1E40AF),
    'responding': Color(0xFF1E40AF),
    'resolved': Color(0xFF065F46),
  };

  List<dynamic> get _plotted => widget.incidents
      .where((i) => i['latitude'] != null && i['longitude'] != null)
      .toList();

  LatLng _rawPointOf(dynamic incident) => LatLng(
    double.parse('${incident['latitude']}'),
    double.parse('${incident['longitude']}'),
  );

  /// Multiple citizen reports from the same barangay all resolve to the
  /// SAME fixed centroid coordinate (see _barangayCoordinates in
  /// report_incident.dart — it pins by barangay, not exact GPS), so
  /// without this they'd stack perfectly on top of each other and look
  /// like a single incident on the map. This nudges duplicates into a
  /// small visible ring around the shared point — display-only, doesn't
  /// touch the real lat/lng used for anything else (fly-to, list, etc.
  /// all still reference the true point via [_pointOf]).
  List<LatLng> get _displayPoints {
    final raw = _plotted.map(_rawPointOf).toList();
    final result = List<LatLng>.from(raw);

    final Map<String, List<int>> groups = {};
    for (var i = 0; i < raw.length; i++) {
      final key =
          '${raw[i].latitude.toStringAsFixed(5)},${raw[i].longitude.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => []).add(i);
    }

    const spreadRadius = 0.00035; // ~35m — enough to separate pins visually
    for (final indices in groups.values) {
      if (indices.length <= 1) continue;
      for (var j = 0; j < indices.length; j++) {
        final angle = (2 * pi * j) / indices.length;
        final base = raw[indices[j]];
        result[indices[j]] = LatLng(
          base.latitude + spreadRadius * cos(angle),
          base.longitude + spreadRadius * sin(angle),
        );
      }
    }

    return result;
  }

  /// The point actually used for a marker/fly-to — spread if it shares a
  /// coordinate with another incident, otherwise its real position.
  LatLng _pointOf(dynamic incident) {
    final index = _plotted.indexOf(incident);
    return index == -1 ? _rawPointOf(incident) : _displayPoints[index];
  }

  String _emojiFor(String? type) => _typeEmoji[type] ?? '⚠️';

  Color _pinColorFor(String status) =>
      _statusPinColors[status] ?? const Color(0xFFB45309);

  @override
  void initState() {
    super.initState();
    _locateMe();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitAll());
  }

  Future<void> _locateMe() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(
        () => _myLocation = LatLng(position.latitude, position.longitude),
      );
    } catch (_) {
      // Silent — the map still works fine without a "you are here" dot.
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _fitAll() {
    final points = _displayPoints;
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    final bounds = LatLngBounds.fromPoints(points);
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(56)),
    );
  }

  void _flyTo(int index) {
    setState(() => _selectedIndex = index);
    _mapController.move(_displayPoints[index], 16);
  }

  @override
  Widget build(BuildContext context) {
    final incidents = _plotted;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Color(0xFF1A1A2E),
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Incident Locations',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await widget.onRetry();
          _fitAll();
        },
        color: _gradientTop,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            // ── Map ──
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              height: 300,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: widget.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _rosalesCenter,
                            initialZoom: 13,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.resqpulse.responder',
                            ),

                            if (_myLocation != null)
                              CircleLayer(
                                circles: [
                                  CircleMarker(
                                    point: _myLocation!,
                                    radius: 50,
                                    useRadiusInMeter: true,
                                    color: _gradientTop.withOpacity(0.12),
                                    borderColor: _gradientTop.withOpacity(0.3),
                                    borderStrokeWidth: 1,
                                  ),
                                ],
                              ),

                            MarkerLayer(
                              markers: [
                                ...incidents.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final incident = entry.value;
                                  final status =
                                      (incident['status'] ?? 'pending')
                                          .toString();
                                  final isSelected = _selectedIndex == index;
                                  final size = isSelected ? 46.0 : 38.0;

                                  return Marker(
                                    point: _pointOf(incident),
                                    width: size,
                                    height: size,
                                    child: GestureDetector(
                                      onTap: () => _flyTo(index),
                                      child: _IncidentPin(
                                        emoji: _emojiFor(
                                          incident['emergency_type'],
                                        ),
                                        color: _pinColorFor(status),
                                        size: size,
                                        selected: isSelected,
                                      ),
                                    ),
                                  );
                                }),

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
                                            color: Colors.black.withOpacity(
                                              0.3,
                                            ),
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

                        // Legend
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _LegendDot(
                                  color: _statusPinColors['pending']!,
                                  label: 'Pending',
                                ),
                                const SizedBox(height: 3),
                                _LegendDot(
                                  color: _statusPinColors['responding']!,
                                  label: 'Responding',
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Recenter button
                        Positioned(
                          right: 10,
                          bottom: 10,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _selectedIndex = null);
                              _fitAll();
                            },
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.center_focus_strong,
                                color: _gradientTop,
                                size: 20,
                              ),
                            ),
                          ),
                        ),

                        // My-location button
                        if (!_isLocating)
                          Positioned(
                            right: 10,
                            bottom: 56,
                            child: GestureDetector(
                              onTap: _locateMe,
                              child: Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.my_location,
                                  color: _gradientTop,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'All open incidents assigned to your agency, including SOS '
                'alerts. Tap a pin or a card to preview it, tap the arrow to '
                'open full details.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: widget.isLoading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : widget.errorMessage != null
                  ? _LocalEmptyStateCard(
                      icon: Icons.error_outline,
                      message: widget.errorMessage!,
                    )
                  : incidents.isEmpty
                  ? const _LocalEmptyStateCard(
                      icon: Icons.map_outlined,
                      message: 'No incident locations to show yet.',
                    )
                  : Column(
                      children: incidents.asMap().entries.map((entry) {
                        final index = entry.key;
                        final incident = entry.value;
                        final String type =
                            incident['emergency_type'] ?? 'Unknown';
                        final String location = incident['location'] ?? '—';
                        final String status = (incident['status'] ?? 'pending')
                            .toString();
                        final bool isSelected = _selectedIndex == index;

                        return GestureDetector(
                          onTap: () => _flyTo(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? _gradientTop
                                    : Colors.grey[200]!,
                                width: isSelected ? 2 : 1.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: _pinColorFor(
                                      status,
                                    ).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(
                                      _emojiFor(incident['emergency_type']),
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        type,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13.5,
                                          color: isSelected
                                              ? _gradientTop
                                              : const Color(0xFF1A1A2E),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        location,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (_statusColors[status] ?? Colors.grey)
                                            .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    _statusLabel(status),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          _statusColors[status] ?? Colors.grey,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    Icons.chevron_right,
                                    color: Colors.grey[400],
                                    size: 20,
                                  ),
                                  onPressed: () => widget.onOpenDetail(
                                    incident as Map<String, dynamic>,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round emoji-badge marker used for every incident pin on the map —
/// color reflects status (pending/responding), a white ring + shadow
/// keeps it legible over both map and satellite-style tiles, and it
/// grows slightly when selected from the list below.
class _IncidentPin extends StatelessWidget {
  final String emoji;
  final Color color;
  final double size;
  final bool selected;

  const _IncidentPin({
    required this.emoji,
    required this.color,
    required this.size,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: selected ? 3 : 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: selected ? 8 : 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(emoji, style: TextStyle(fontSize: size * 0.46)),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }
}

class _LocalEmptyStateCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _LocalEmptyStateCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }
}
