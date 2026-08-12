import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'add_evacuation.dart';

const Color _gradientTop = Color(0xFF00308F);
const Color _navy = Color(0xFF0D1B4C);

/// Evacuation Centers — read-only for every responder (view where centers
/// are, their capacity/status, and distance from current position).
///
/// If [isMswd] is true, a floating "+" button is shown that jumps straight
/// to AddEvacuationCenterScreen — MSWD is the only agency allowed to add
/// centers (enforced server-side too), everyone else just gets the list.
class ResponderEvacuationCentersScreen extends StatefulWidget {
  final bool isMswd;
  const ResponderEvacuationCentersScreen({super.key, this.isMswd = false});

  @override
  State<ResponderEvacuationCentersScreen> createState() =>
      _ResponderEvacuationCentersScreenState();
}

class _ResponderEvacuationCentersScreenState
    extends State<ResponderEvacuationCentersScreen> {
  final MapController _mapController = MapController();
  final LatLng _mapCenter = const LatLng(15.8957, 120.6278);

  List<_EvacCenter> _centers = [];
  bool _isLoadingCenters = true;
  String? _centersError;

  int? _selectedIndex;
  LatLng? _userLocation;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _loadCenters();
    _determineUserLocation();
  }

  Future<void> _loadCenters() async {
    setState(() {
      _isLoadingCenters = true;
      _centersError = null;
    });

    final result = await ApiService.getEvacuationCenters();
    if (!mounted) return;

    if (result.success && result.data is List) {
      setState(() {
        _centers = (result.data as List)
            .map((e) => _EvacCenter.fromJson(e as Map<String, dynamic>))
            .toList();
        _isLoadingCenters = false;
      });
    } else {
      setState(() {
        _centersError = result.error ?? 'Could not load evacuation centers.';
        _isLoadingCenters = false;
      });
    }
  }

  Future<void> _determineUserLocation() async {
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
        () => _userLocation = LatLng(position.latitude, position.longitude),
      );
      _mapController.move(_userLocation!, 15);
    } catch (_) {
      // Silent — map still works without a "you are here" dot.
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _flyTo(LatLng location, int index) {
    setState(() => _selectedIndex = index);
    _mapController.move(location, 15.5);
  }

  String _distanceTo(_EvacCenter center) {
    if (_userLocation == null) return '—';
    final meters = Geolocator.distanceBetween(
      _userLocation!.latitude,
      _userLocation!.longitude,
      center.latitude,
      center.longitude,
    );
    return meters < 1000
        ? '${meters.round()} m'
        : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'full':
        return const Color(0xFFD32F2F);
      case 'closed':
        return Colors.grey;
      default:
        return const Color(0xFF2E7D32);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'full':
        return 'Full';
      case 'closed':
        return 'Closed';
      default:
        return 'Open';
    }
  }

  Future<void> _openAddScreen() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddEvacuationCenterScreen()),
    );
    if (added == true) _loadCenters();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

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
          'Evacuation Centers',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      floatingActionButton: widget.isMswd
          ? FloatingActionButton.extended(
              onPressed: _openAddScreen,
              backgroundColor: _navy,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Add Center',
                style: TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            height: 220,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _mapCenter,
                    initialZoom: 14.5,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.resqpulse.responder',
                    ),
                    if (_userLocation != null)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _userLocation!,
                            radius: 60,
                            useRadiusInMeter: true,
                            color: _gradientTop.withOpacity(0.12),
                            borderColor: _gradientTop.withOpacity(0.3),
                            borderStrokeWidth: 1,
                          ),
                        ],
                      ),
                    MarkerLayer(
                      markers: [
                        ..._centers.asMap().entries.map((entry) {
                          final i = entry.key;
                          final center = entry.value;
                          final isSelected = _selectedIndex == i;
                          return Marker(
                            point: center.location,
                            width: 40,
                            height: 40,
                            child: GestureDetector(
                              onTap: () => _flyTo(center.location, i),
                              child: Icon(
                                Icons.location_pin,
                                color: isSelected
                                    ? _gradientTop
                                    : _statusColor(center.status),
                                size: isSelected ? 40 : 32,
                              ),
                            ),
                          );
                        }),
                        if (_userLocation != null)
                          Marker(
                            point: _userLocation!,
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
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: GestureDetector(
                    onTap: _determineUserLocation,
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
                      child: _isLocating
                          ? const Padding(
                              padding: EdgeInsets.all(9),
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: _gradientTop,
                              ),
                            )
                          : const Icon(
                              Icons.my_location,
                              color: _gradientTop,
                              size: 20,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoadingCenters
                ? const Center(child: CircularProgressIndicator())
                : _centersError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _centersError!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: _loadCenters,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                : _centers.isEmpty
                ? Center(
                    child: Text(
                      'No evacuation centers available yet.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 15),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        Future.wait([_loadCenters(), _determineUserLocation()]),
                    color: _gradientTop,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      itemCount: _centers.length,
                      itemBuilder: (context, index) {
                        final center = _centers[index];
                        final isSelected = _selectedIndex == index;
                        return GestureDetector(
                          onTap: () => _flyTo(center.location, index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
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
                                  color: Colors.black.withOpacity(0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? _gradientTop.withOpacity(0.1)
                                        : Colors.grey[100],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.home_work_outlined,
                                    color: isSelected
                                        ? _gradientTop
                                        : Colors.grey[600],
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              center.name,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
                                                color: isSelected
                                                    ? _gradientTop
                                                    : const Color(0xFF1A1A2E),
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _statusColor(
                                                center.status,
                                              ).withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              _statusLabel(center.status),
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: _statusColor(
                                                  center.status,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Brgy. ${center.barangay}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${_distanceTo(center)} · Cap. ${center.occupancy}/${center.capacity}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _gradientTop,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EvacCenter {
  final int id;
  final String name;
  final String barangay;
  final double latitude;
  final double longitude;
  final int capacity;
  final int occupancy;
  final String status;

  const _EvacCenter({
    required this.id,
    required this.name,
    required this.barangay,
    required this.latitude,
    required this.longitude,
    required this.capacity,
    required this.occupancy,
    required this.status,
  });

  LatLng get location => LatLng(latitude, longitude);

  factory _EvacCenter.fromJson(Map<String, dynamic> json) {
    return _EvacCenter(
      id: json['id'] is int ? json['id'] : int.tryParse('${json['id']}') ?? 0,
      name: json['name']?.toString() ?? '',
      barangay: json['barangay']?.toString() ?? '',
      latitude: double.tryParse('${json['latitude']}') ?? 0,
      longitude: double.tryParse('${json['longitude']}') ?? 0,
      capacity: json['capacity'] is int
          ? json['capacity']
          : int.tryParse('${json['capacity']}') ?? 0,
      occupancy: json['occupancy'] is int
          ? json['occupancy']
          : int.tryParse('${json['occupancy']}') ?? 0,
      status: json['status']?.toString() ?? 'open',
    );
  }
}
