import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'api_service.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _green = Color(0xFF2E9E4F);
const Color _ink = Color(0xFF1A1A2E);

/// One casualty row of the MDRRMC Incident Report (Dead / Injured / Missing).
class _Casualty {
  final name = TextEditingController();
  final age = TextEditingController();
  final address = TextEditingController();
  final cause = TextEditingController();
  final remarks = TextEditingController();
  String? sex;

  void dispose() {
    name.dispose();
    age.dispose();
    address.dispose();
    cause.dispose();
    remarks.dispose();
  }

  Map<String, String> toJson() => {
    'name': name.text.trim(),
    'age': age.text.trim(),
    'sex': sex ?? '',
    'address': address.text.trim(),
    'cause': cause.text.trim(),
    'remarks': remarks.text.trim(),
  };

  bool get isEmpty =>
      name.text.trim().isEmpty &&
      age.text.trim().isEmpty &&
      address.text.trim().isEmpty &&
      cause.text.trim().isEmpty &&
      remarks.text.trim().isEmpty;
}

/// Shown after a responder taps "Mark as Resolved" on the Navigation
/// screen. The responder fills in the MDRRMC Incident Report (same format
/// as the official paper form); the server turns it into a PDF that is
/// attached to the resolution and shown to the admin on the incident's
/// detail page. Submits to POST /api/responder/incidents/{id}/resolve
/// (see Api\IncidentController::resolve()).
///
/// Incident type, location, date, day and time are filled in by the server
/// from the incident itself, so the responder doesn't retype them.
class IncidentResolutionScreen extends StatefulWidget {
  final int? incidentId;
  final String? incidentLabel;

  const IncidentResolutionScreen({
    super.key,
    this.incidentId,
    this.incidentLabel,
  });

  @override
  State<IncidentResolutionScreen> createState() =>
      _IncidentResolutionScreenState();
}

class _IncidentResolutionScreenState extends State<IncidentResolutionScreen> {
  static const int _maxNarrative = 2000;

  String _reportType = 'final'; // initial | final
  final _narrative = TextEditingController();
  final _effects = TextEditingController();
  final _actions = TextEditingController();
  final _releasedBy = TextEditingController();

  final List<_Casualty> _dead = [];
  final List<_Casualty> _injured = [];
  final List<_Casualty> _missing = [];

  File? _photo;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _narrative.addListener(() => setState(() {}));
    _prefillReleasedBy();
  }

  /// "Report Released by" = who is filing it — pre-filled from the logged-in
  /// responder's profile, still editable.
  Future<void> _prefillReleasedBy() async {
    final r = await ApiService.getResponder();
    if (r == null || !mounted) return;
    final parts = <String>[
      (r['full_name'] ?? '').toString().toUpperCase(),
      (r['unit_station'] ?? '').toString(),
      (r['agency'] ?? '').toString(),
    ].where((p) => p.trim().isNotEmpty).toList();
    if (_releasedBy.text.isEmpty) {
      _releasedBy.text = parts.join(', ');
    }
  }

  @override
  void dispose() {
    _narrative.dispose();
    _effects.dispose();
    _actions.dispose();
    _releasedBy.dispose();
    for (final c in [..._dead, ..._injured, ..._missing]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Photo ────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 80,
      );
      if (picked != null) setState(() => _photo = File(picked.path));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not open ${source == ImageSource.camera ? 'camera' : 'gallery'}: $e',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Upload Photo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 16),
              _sheetTile(
                Icons.camera_alt_outlined,
                'Take a Photo',
                'Open camera',
                () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              _sheetTile(
                Icons.photo_library_outlined,
                'Choose from Gallery',
                'Pick from your photos',
                () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: _navy.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _navy),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }

  // ── Submit ───────────────────────────────────────────────────────

  void _snack(String msg, {Color color = Colors.redAccent}) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Map<String, dynamic> _buildReport() {
    List<Map<String, String>> rows(List<_Casualty> l) =>
        l.where((c) => !c.isEmpty).map((c) => c.toJson()).toList();

    return {
      'report_type': _reportType,
      'narrative': _narrative.text.trim(),
      'casualties': {
        'dead': rows(_dead),
        'injured': rows(_injured),
        'missing': rows(_missing),
      },
      'effects': _effects.text.trim(),
      'actions_taken': _actions.text.trim(),
      'released_by': _releasedBy.text.trim(),
    };
  }

  Future<void> _submit() async {
    final incidentId = widget.incidentId;

    if (incidentId == null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }

    if (_narrative.text.trim().isEmpty) {
      _snack('Please describe what happened in the narrative.');
      return;
    }

    setState(() => _isSubmitting = true);

    final result = await ApiService.resolveIncident(
      incidentId,
      photo: _photo,
      report: _buildReport(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (!result.success) {
      _snack(result.error ?? 'Could not submit the report.');
      return;
    }

    _snack('Incident resolved. Report filed.', color: _green);

    // Pop everything back to Home (past Navigation + Incident Detail).
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── UI helpers ───────────────────────────────────────────────────

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.all(12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey[300]!),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _navy, width: 1.6),
    ),
  );

  Widget _label(String text, {String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Flexible(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: _ink,
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 6),
          Text(hint, style: TextStyle(fontSize: 12.5, color: Colors.grey[500])),
        ],
      ],
    ),
  );

  Widget _textBox(
    TextEditingController c,
    String hint, {
    int lines = 3,
    int max = 1000,
  }) {
    return TextField(
      controller: c,
      maxLines: lines,
      maxLength: max,
      textCapitalization: TextCapitalization.sentences,
      buildCounter:
          (context, {required currentLength, required isFocused, maxLength}) =>
              null,
      style: const TextStyle(fontSize: 14, color: _ink),
      decoration: _decoration(hint),
    );
  }

  Widget _typeChip(String value, String label) {
    final selected = _reportType == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      selectedColor: _navy,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? _navy : Colors.grey[300]!),
      labelStyle: TextStyle(
        color: selected ? Colors.white : _ink,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      onSelected: (_) => setState(() => _reportType = value),
    );
  }

  Widget _casualtySection(String title, List<_Casualty> list) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: _ink,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => list.add(_Casualty())),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                style: TextButton.styleFrom(foregroundColor: _navy),
              ),
            ],
          ),
          if (list.isEmpty)
            Text(
              'None',
              style: TextStyle(fontSize: 13, color: Colors.grey[500]),
            ),
          for (int i = 0; i < list.length; i++) _casualtyCard(list, i),
        ],
      ),
    );
  }

  Widget _casualtyCard(List<_Casualty> list, int i) {
    final c = list[i];
    Widget small(TextEditingController ctl, String hint, {TextInputType? kb}) =>
        TextField(
          controller: ctl,
          keyboardType: kb,
          style: const TextStyle(fontSize: 13.5, color: _ink),
          decoration: _decoration(hint),
        );

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                '#${i + 1}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => setState(() {
                  list.removeAt(i).dispose();
                }),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          small(c.name, 'Full name'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: c.age,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  style: const TextStyle(fontSize: 13.5, color: _ink),
                  decoration: _decoration('Age'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: c.sex,
                  isDense: true,
                  decoration: _decoration('Sex'),
                  items: const [
                    DropdownMenuItem(value: 'M', child: Text('M')),
                    DropdownMenuItem(value: 'F', child: Text('F')),
                  ],
                  onChanged: (v) => setState(() => c.sex = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          small(c.address, 'Address'),
          const SizedBox(height: 8),
          small(c.cause, 'Cause (e.g. side sweep, drowning)'),
          const SizedBox(height: 8),
          small(c.remarks, 'Remarks (disposition of casualty)'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrativeLength = _narrative.text.length;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Incident Report',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Heading ──
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 68,
                      height: 68,
                      decoration: const BoxDecoration(
                        color: _green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MDRRMC Incident Report',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fill this in to close the incident. A PDF copy is sent to the MDRRMO admin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    if (widget.incidentLabel != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.incidentLabel!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Report type ──
              _label('Report Type'),
              Wrap(
                spacing: 8,
                children: [
                  _typeChip('initial', 'Initial'),
                  _typeChip('final', 'Final'),
                ],
              ),

              const SizedBox(height: 20),

              // ── Narrative ──
              _label('Details / Narrative / Cause', hint: '(required)'),
              _textBox(
                _narrative,
                'What happened, who responded, and when (e.g. times dispatched / arrived)...',
                lines: 6,
                max: _maxNarrative,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '$narrativeLength/$_maxNarrative',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Casualties ──
              _label('Casualties', hint: '(leave empty if none)'),
              _casualtySection('A. Dead / Drowned', _dead),
              _casualtySection('B. Injured', _injured),
              _casualtySection('C. Missing', _missing),

              const SizedBox(height: 8),

              // ── Effects / Actions ──
              _label('Effects', hint: '(optional)'),
              _textBox(
                _effects,
                'e.g. Minor abrasion, road blocked...',
                lines: 3,
              ),

              const SizedBox(height: 16),

              _label("Action/s Taken", hint: '(optional)'),
              _textBox(
                _actions,
                'What the team did on scene...',
                lines: 4,
                max: 1500,
              ),

              const SizedBox(height: 16),

              _label('Report Released by'),
              TextField(
                controller: _releasedBy,
                textCapitalization: TextCapitalization.words,
                style: const TextStyle(fontSize: 14, color: _ink),
                decoration: _decoration('Name, designation, office/agency'),
              ),

              const SizedBox(height: 20),

              // ── Photo ──
              Row(
                children: [
                  const Text(
                    'Upload Photo ',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: _ink,
                    ),
                  ),
                  Text(
                    '(Optional – added to the PDF)',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _photo == null ? _showImageSourceSheet : null,
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: _photo == null
                      ? Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 34,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Add Image',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(_photo!, fit: BoxFit.cover),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: GestureDetector(
                                onTap: () => setState(() => _photo = null),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 32),

              // ── Submit ──
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    elevation: 2,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'SUBMIT REPORT',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
