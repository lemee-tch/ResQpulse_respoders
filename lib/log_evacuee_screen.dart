import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _green = Color(0xFF2E9E3F);

/// MSWD-only screen — logs one evacuee (one row per person, not per
/// household) at a specific evacuation center, reached from the "Log
/// Evacuee" tap target on each center card in evacuation_centers.dart.
///
/// Arrival only, by design — there's no matching "check out" flow, since
/// this is meant as a simple field sign-in sheet, not full-blown shelter
/// occupancy management. See Evacuee model on the backend for the same
/// reasoning documented server-side.
///
/// Only responders whose `agency` is 'MSWD' should ever reach this screen
/// (the entry point on the centers list is already gated the same way
/// add_evacuation.dart's is). The backend double-checks this too — a
/// non-MSWD token gets a 403 from the endpoint regardless.
///
/// [centerStatus] is passed in from the centers list so this screen knows
/// right away whether the center can still take evacuees — the list
/// already hides/disables the "Log Evacuee" button once a center is
/// full/closed, but status can change in the moment between loading that
/// list and a responder tapping through, so this screen re-checks it too
/// and shows a blocking message instead of the form when it's not 'open'.
/// The backend is the actual authority either way (see
/// Api\EvacuationCenterController::storeEvacuee) — this is just so a
/// responder finds out immediately instead of after filling out the form.
class LogEvacueeScreen extends StatefulWidget {
  final int centerId;
  final String centerName;
  final String centerStatus;

  const LogEvacueeScreen({
    super.key,
    required this.centerId,
    required this.centerName,
    required this.centerStatus,
  });

  @override
  State<LogEvacueeScreen> createState() => _LogEvacueeScreenState();
}

class _LogEvacueeScreenState extends State<LogEvacueeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _suffixController = TextEditingController();
  final _contactController = TextEditingController();
  final _ageController = TextEditingController();

  String? _selectedGender;
  String? _selectedBarangay;

  bool _isSaving = false;
  String? _errorMessage;

  bool get _isOpen => widget.centerStatus == 'open';

  // Same barangay list used across the app (register.dart,
  // report_incident.dart, add_evacuation.dart, evacuation.blade.php) so
  // this stays consistent with every other barangay picker in ResQPulse.
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

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _suffixController.dispose();
    _contactController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    // Shouldn't be reachable — the form below isn't shown at all when the
    // center isn't open — but guard anyway, same belt-and-suspenders
    // pattern as the MSWD-only checks elsewhere in this app.
    if (!_isOpen) return;

    if (!_formKey.currentState!.validate()) return;
    if (_selectedGender == null) {
      setState(() => _errorMessage = 'Please select a gender.');
      return;
    }
    if (_selectedBarangay == null) {
      setState(() => _errorMessage = 'Please select a barangay.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    final result = await ApiService.logEvacuee(
      centerId: widget.centerId,
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim().isEmpty
          ? null
          : _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      suffix: _suffixController.text.trim().isEmpty
          ? null
          : _suffixController.text.trim(),
      contactNumber: _contactController.text.trim().isEmpty
          ? null
          : _contactController.text.trim(),
      barangay: _selectedBarangay!,
      gender: _selectedGender!,
      age: int.parse(_ageController.text.trim()),
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_firstNameController.text.trim()} logged at ${widget.centerName}.',
          ),
          backgroundColor: _green,
        ),
      );
      // Clear the form instead of popping — during an actual evacuation,
      // MSWD staff are logging many people in a row at the same center,
      // not just one, so staying on this screen saves a re-navigate per
      // person.
      _formKey.currentState!.reset();
      _firstNameController.clear();
      _middleNameController.clear();
      _lastNameController.clear();
      _suffixController.clear();
      _contactController.clear();
      _ageController.clear();
      setState(() {
        _selectedGender = null;
        _selectedBarangay = null;
      });
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
        title: Text(
          'Log Evacuee',
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
      body: SafeArea(child: !_isOpen ? _buildBlockedState() : _buildForm()),
    );
  }

  /// Shown instead of the form when the center is full or closed —
  /// there's nothing to fill out if logging isn't possible here, so this
  /// explains why and sends the responder back to pick another center
  /// (or update this one's status first) rather than leaving them staring
  /// at a form that will just fail on submit.
  Widget _buildBlockedState() {
    final isClosed = widget.centerStatus == 'closed';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.red[50],
                shape: BoxShape.circle,
              ),
              child: Icon(
                isClosed ? Icons.lock_outline : Icons.people_outline,
                color: Colors.red[400],
                size: 34,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isClosed
                  ? '${widget.centerName} is closed'
                  : '${widget.centerName} is full',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isClosed
                  ? 'New evacuees can\'t be logged here while this center is marked closed. Pick a different center, or update its status first if it should be open.'
                  : 'New evacuees can\'t be logged here while this center is marked full. Pick a different center, or update its status once space frees up.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _navy),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
                child: const Text(
                  'Back to Centers',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _navy),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _green.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: _green, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Logging at ${widget.centerName}. One entry per person — arrival only, no check-out needed.',
                      style: const TextStyle(
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
                        style: const TextStyle(color: Colors.red, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('First Name'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _firstNameController,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1A1A2E),
                        ),
                        decoration: _decoration(
                          'First name',
                          Icons.person_outline,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Middle Name'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _middleNameController,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1A1A2E),
                        ),
                        decoration: _decoration(
                          'Optional',
                          Icons.person_outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Last Name'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _lastNameController,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1A1A2E),
                        ),
                        decoration: _decoration(
                          'Last name',
                          Icons.person_outline,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Suffix'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _suffixController,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1A1A2E),
                        ),
                        decoration: _decoration(
                          'Jr., Sr., III',
                          Icons.badge_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Gender'),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedGender,
                        isExpanded: true,
                        decoration: _decoration('Select', Icons.wc_outlined),
                        items: const [
                          DropdownMenuItem(value: 'Male', child: Text('Male')),
                          DropdownMenuItem(
                            value: 'Female',
                            child: Text('Female'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _selectedGender = v),
                        validator: (v) => v == null ? 'Required' : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Age'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _ageController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF1A1A2E),
                        ),
                        decoration: _decoration('Age', Icons.cake_outlined),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          final n = int.tryParse(v.trim());
                          if (n == null || n < 0 || n > 120)
                            return 'Invalid age';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _label('Barangay Address'),
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
              onChanged: (v) => setState(() => _selectedBarangay = v),
              validator: (v) => v == null ? 'Please select a barangay' : null,
            ),
            const SizedBox(height: 16),

            _label('Contact Number'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _contactController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 15, color: Color(0xFF1A1A2E)),
              decoration: _decoration('Optional', Icons.phone_outlined),
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
                        'LOG EVACUEE',
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
