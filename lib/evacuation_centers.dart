import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'api_service.dart';
import 'add_evacuation.dart';
import 'log_evacuee_screen.dart';

const Color _gradientTop = Color(0xFF00308F);
const Color _navy = Color(0xFF0D1B4C);

/// Evacuation Centers — read-only for most responders (view where centers
/// are, their capacity/status, and distance from current position).
///
/// If [isMswd] is true, a floating "+" button is shown that jumps straight
/// to AddEvacuationCenterScreen, AND the status pill on each card becomes
/// tappable — MSWD is the only agency allowed to add or update centers
/// (enforced server-side too), everyone else just gets the read-only list.
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
  String? _selectedBarangayFilter;

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

  /// Every distinct barangay actually present among loaded centers —
  /// populates the filter dropdown with only options that would ever
  /// return a result, instead of the full 37-barangay municipal list
  /// where most entries might have zero centers.
  List<String> get _barangaysInCenters {
    final set = _centers
        .map((c) => c.barangay)
        .where((b) => b.isNotEmpty)
        .toSet();
    final list = set.toList()..sort();
    return list;
  }

  List<_EvacCenter> get _filteredCenters {
    if (_selectedBarangayFilter == null) return _centers;
    return _centers
        .where((c) => c.barangay == _selectedBarangayFilter)
        .toList();
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

  /// MSWD-only — matches the admin panel's inline status dropdown
  /// (evacuation_blade.php). Everyone else's badge stays a plain
  /// read-only pill; server-side re-checks this gate regardless (see
  /// Api\EvacuationCenterController::updateStatus).
  Future<void> _changeStatus(_EvacCenter center) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text(
              center.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              'Update status',
              style: TextStyle(color: Colors.grey[600], fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            for (final s in const ['open', 'full', 'closed'])
              ListTile(
                leading: Icon(Icons.circle, size: 12, color: _statusColor(s)),
                title: Text(_statusLabel(s)),
                trailing: center.status == s
                    ? const Icon(Icons.check, color: _navy)
                    : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selected == null || selected == center.status || !mounted) return;

    final result = await ApiService.updateEvacuationCenterStatus(
      center.id,
      selected,
    );

    if (!mounted) return;

    if (result.success) {
      _loadCenters();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Could not update status.'),
          backgroundColor: Colors.redAccent,
        ),
      );
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
                        ..._filteredCenters.asMap().entries.map((entry) {
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
          if (!_isLoadingCenters &&
              _centersError == null &&
              _centers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedBarangayFilter,
                    isExpanded: true,
                    hint: const Text(
                      'All Barangays',
                      style: TextStyle(fontSize: 13.5),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('All Barangays'),
                      ),
                      ..._barangaysInCenters.map(
                        (b) =>
                            DropdownMenuItem<String?>(value: b, child: Text(b)),
                      ),
                    ],
                    onChanged: (v) =>
                        setState(() => _selectedBarangayFilter = v),
                  ),
                ),
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
                : _filteredCenters.isEmpty
                ? Center(
                    child: Text(
                      _selectedBarangayFilter == null
                          ? 'No evacuation centers available yet.'
                          : 'No centers in $_selectedBarangayFilter.',
                      style: TextStyle(color: Colors.grey[500], fontSize: 15),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () =>
                        Future.wait([_loadCenters(), _determineUserLocation()]),
                    color: _gradientTop,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                      itemCount: _filteredCenters.length,
                      itemBuilder: (context, index) {
                        final center = _filteredCenters[index];
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
                                          GestureDetector(
                                            onTap: widget.isMswd
                                                ? () => _changeStatus(center)
                                                : null,
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    _statusLabel(center.status),
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: _statusColor(
                                                        center.status,
                                                      ),
                                                    ),
                                                  ),
                                                  if (widget.isMswd) ...[
                                                    const SizedBox(width: 3),
                                                    Icon(
                                                      Icons.edit,
                                                      size: 10,
                                                      color: _statusColor(
                                                        center.status,
                                                      ),
                                                    ),
                                                  ],
                                                ],
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
                                        _distanceTo(center),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _gradientTop,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.how_to_reg,
                                            size: 13,
                                            color: Colors.grey[500],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${center.evacueesCount} residents logged',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (widget.isMswd) ...[
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: SizedBox(
                                                height: 34,
                                                child: OutlinedButton.icon(
                                                  onPressed: () =>
                                                      _changeStatus(center),
                                                  icon: Icon(
                                                    Icons.edit_outlined,
                                                    size: 15,
                                                    color: _gradientTop,
                                                  ),
                                                  label: Text(
                                                    'Status',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: _gradientTop,
                                                    ),
                                                  ),
                                                  style: OutlinedButton.styleFrom(
                                                    side: BorderSide(
                                                      color: _gradientTop,
                                                    ),
                                                    padding: EdgeInsets.zero,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: SizedBox(
                                                height: 34,
                                                child: ElevatedButton.icon(
                                                  onPressed: () =>
                                                      Navigator.push(
                                                        context,
                                                        MaterialPageRoute(
                                                          builder: (_) =>
                                                              LogEvacueeScreen(
                                                                centerId:
                                                                    center.id,
                                                                centerName:
                                                                    center.name,
                                                              ),
                                                        ),
                                                      ),
                                                  icon: const Icon(
                                                    Icons.how_to_reg,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    'Log Evacuee',
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        _gradientTop,
                                                    foregroundColor:
                                                        Colors.white,
                                                    elevation: 0,
                                                    padding: EdgeInsets.zero,
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
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
  final int evacueesCount;

  const _EvacCenter({
    required this.id,
    required this.name,
    required this.barangay,
    required this.latitude,
    required this.longitude,
    required this.capacity,
    required this.occupancy,
    required this.status,
    this.evacueesCount = 0,
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
      // withCount('evacuees') on the backend names this evacuees_count —
      // absent entirely on older cached responses, so default to 0
      // rather than crash.
      evacueesCount: json['evacuees_count'] is int
          ? json['evacuees_count']
          : int.tryParse('${json['evacuees_count']}') ?? 0,
    );
  }
}
