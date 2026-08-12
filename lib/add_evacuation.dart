import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _green = Color(0xFF2E9E3F);

/// MSWD-only screen — lets an MSWD responder add a new evacuation center
/// straight from the mobile app.
///
/// This writes to the SAME `evacuation_centers` table the admin panel's
/// "Evacuation Centers" page reads from (see
/// Admin\EvacuationCenterController + evacuation.blade.php) and that the
/// citizen app's Evacuation Centers screen reads from (see centers.dart /
/// ApiService.getEvacuationCenters()). There's no separate sync step —
/// the moment this POST succeeds, the new center is live everywhere.
///
/// Only responders whose `agency` is 'MSWD' should ever reach this screen
/// (gate the entry point — e.g. the home screen quick-tile — on
/// `responder['agency'] == 'MSWD'`). The backend double-checks this too
/// (403 if a non-MSWD token calls the endpoint), so this screen is safe
/// even if it's ever reachable by mistake.
class AddEvacuationCenterScreen extends StatefulWidget {
  const AddEvacuationCenterScreen({super.key});

  @override
  State<AddEvacuationCenterScreen> createState() =>
      _AddEvacuationCenterScreenState();
}

class _AddEvacuationCenterScreenState extends State<AddEvacuationCenterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _capacityController = TextEditingController();

  String? _selectedBarangay;
  String _status = 'open';

  double? _latitude;
  double? _longitude;
  bool _isGeocoding = false;
  String? _geocodeStatus;
  bool _geocodeResolved = false;

  bool _isSaving = false;
  String? _errorMessage;

  // Same barangay list used across the app (register.dart,
  // report_incident.dart, evacuation.blade.php) so this stays consistent
  // with every other barangay picker in ResQPulse.
  static const List<String> _barangays = [
    'Acop',
    'Bakitbakit',
    'Balingcanaway',
    'Cabalaoangan Norte',
    'Cabalaoangan Sur',
    'Calanutan',
    'Camangaan',
    'Capitan Tomas',
    'Carmay East',
    'Carmay West',
    'Carmen East',
    'Carmen West',
    'Casanicolasan',
    'Coliling',
    'Don Antonio Village',
    'Guiling',
    'Palakipak',
    'Pangaoan',
    'Rabago',
    'Rizal',
    'Salvacion',
    'San Angel',
    'San Antonio',
    'San Bartolome',
    'San Isidro',
    'San Luis',
    'San Pedro East',
    'San Pedro West',
    'San Vicente',
    'Station District',
    'Tomana East',
    'Tomana West',
    'Zone I (Poblacion)',
    'Zone II (Poblacion)',
    'Zone III (Poblacion)',
    'Zone IV (Poblacion)',
    'Zone V (Poblacion)',
  ];

  static const double _rosalesFallbackLat = 15.8952;
  static const double _rosalesFallbackLng = 120.6263;

  @override
  void dispose() {
    _nameController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  /// Same "free public Nominatim search, no API key" pattern already used
  /// on the admin Evacuation Centers page (see evacuation.blade.php's
  /// geocodeBarangay JS) — kept consistent so a barangay resolves to the
  /// same point whether it's added from the admin panel or from here.
  Future<void> _geocodeBarangay(String barangay) async {
    setState(() {
      _isGeocoding = true;
      _geocodeResolved = false;
      _geocodeStatus = 'Locating $barangay...';
    });

    try {
      final query = Uri.encodeComponent(
        '$barangay, Rosales, Pangasinan, Philippines',
      );
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1',
      );

      final response = await http
          .get(uri, headers: {'User-Agent': 'ResQPulse-MDRRMO-Rosales/1.0'})
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List;
        if (data.isNotEmpty) {
          final lat = double.tryParse(data.first['lat'].toString());
          final lng = double.tryParse(data.first['lon'].toString());
          if (lat != null && lng != null) {
            if (!mounted) return;
            setState(() {
              _latitude = lat;
              _longitude = lng;
              _geocodeResolved = true;
              _geocodeStatus =
                  'Located at ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
              _isGeocoding = false;
            });
            return;
          }
        }
      }
      throw 'No results';
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _latitude = _rosalesFallbackLat;
        _longitude = _rosalesFallbackLng;
        _geocodeResolved = false;
        _geocodeStatus =
            "Couldn't pinpoint $barangay — using Rosales town center. "
            'An admin can fine-tune this later.';
        _isGeocoding = false;
      });
    }
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBarangay == null) {
      setState(() => _errorMessage = 'Please select a barangay.');
      return;
    }
    if (_latitude == null || _longitude == null) {
      setState(
        () => _errorMessage =
            'Still locating the barangay — please wait a moment.',
      );
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await ApiService.createEvacuationCenter(
      name: _nameController.text.trim(),
      barangay: _selectedBarangay!,
      latitude: _latitude!,
      longitude: _longitude!,
      capacity: int.parse(_capacityController.text.trim()),
      status: _status,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_nameController.text.trim()} added — now visible to admins and residents.',
          ),
          backgroundColor: _green,
        ),
      );
      Navigator.pop(context, true);
    } else {
      setState(() => _errorMessage = result.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Evacuation Center',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _green.withOpacity(0.4)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: _green, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This center will immediately appear on the MDRRMO admin '
                          'panel and in the citizen app\'s Evacuation Centers list.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                if (_errorMessage != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red[200]!),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                _label('Center Name'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1A1A2E),
                  ),
                  decoration: _decoration(
                    'e.g. Rosales Central School',
                    Icons.home_work_outlined,
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Center name is required'
                      : null,
                ),
                const SizedBox(height: 16),

                _label('Barangay'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _selectedBarangay,
                  isExpanded: true,
                  decoration: _decoration(
                    'Select barangay',
                    Icons.location_on_outlined,
                  ),
                  items: _barangays
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedBarangay = v);
                    if (v != null) _geocodeBarangay(v);
                  },
                  validator: (v) =>
                      v == null ? 'Please select a barangay' : null,
                ),
                if (_geocodeStatus != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_isGeocoding)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(
                          _geocodeResolved
                              ? Icons.check_circle
                              : Icons.info_outline,
                          size: 15,
                          color: _geocodeResolved ? _green : Colors.orange[700],
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _geocodeStatus!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _geocodeResolved ? _green : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 16),

                _label('Capacity'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _capacityController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1A1A2E),
                  ),
                  decoration: _decoration('e.g. 300', Icons.groups_outlined),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Capacity is required';
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 1) return 'Enter a valid capacity';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                _label('Status'),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _status,
                  isExpanded: true,
                  decoration: _decoration('Status', Icons.toggle_on_outlined),
                  items: const [
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'full', child: Text('Full')),
                    DropdownMenuItem(value: 'closed', child: Text('Closed')),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'open'),
                ),

                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 3,
                      shadowColor: _navy.withOpacity(0.4),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'SAVE EVACUATION CENTER',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.6,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: Color(0xFF444466),
    ),
  );

  InputDecoration _decoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
      prefixIcon: Icon(icon, color: Colors.grey[500], size: 20),
      filled: true,
      fillColor: const Color(0xFFF8F9FF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _navy, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 2),
      ),
    );
  }
}
