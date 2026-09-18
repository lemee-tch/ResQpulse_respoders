import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'api_service.dart';

const Color _navy = Color(0xFF0D1B4C);
const Color _gradientTop = Color(0xFF00308F);

/// MSWD-only — the "bird's eye" view of every evacuee logged across every
/// center, not just one center at a time (that's what tapping "Log
/// Evacuee" on a specific center in evacuation_centers.dart leads to
/// instead). Reached from the home screen's "Resident Logs" quick-access
/// tile.
///
/// Read-only — logging a new evacuee still happens from a specific
/// center's card, not here. This screen is for reviewing what's already
/// been recorded.
class ResidentLogsScreen extends StatefulWidget {
  const ResidentLogsScreen({super.key});

  @override
  State<ResidentLogsScreen> createState() => _ResidentLogsScreenState();
}

class _ResidentLogsScreenState extends State<ResidentLogsScreen> {
  List<Map<String, dynamic>> _evacuees = [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _selectedBarangay;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final result = await ApiService.getEvacueeLogs();

    if (!mounted) return;

    if (result.success) {
      final list = (result.data as List)
          .map((e) => e as Map<String, dynamic>)
          .toList();
      setState(() {
        _evacuees = list;
        _isLoading = false;
      });
    } else {
      setState(() {
        _errorMessage = result.error;
        _isLoading = false;
      });
    }
  }

  String _fullName(Map<String, dynamic> e) {
    final parts = [
      e['first_name'],
      e['middle_name'],
      e['last_name'],
      e['suffix'],
    ].where((p) => p != null && p.toString().trim().isNotEmpty);
    return parts.join(' ');
  }

  List<String> get _barangaysInData {
    final set = _evacuees.map((e) => e['barangay']?.toString() ?? '').toSet();
    set.removeWhere((b) => b.isEmpty);
    final list = set.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> get _filteredEvacuees {
    if (_selectedBarangay == null) return _evacuees;
    return _evacuees
        .where((e) => e['barangay']?.toString() == _selectedBarangay)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _navy, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Resident Logs',
          style: TextStyle(
            color: Color(0xFF1A1A2E),
            fontWeight: FontWeight.bold,
            fontSize: 17,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadLogs,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _navy))
            : _errorMessage != null
            ? ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const SizedBox(height: 60),
                  Icon(Icons.error_outline, color: Colors.red[300], size: 48),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _loadLogs,
                      child: const Text('Try Again'),
                    ),
                  ),
                ],
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                value: _selectedBarangay,
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
                                  ..._barangaysInData.map(
                                    (b) => DropdownMenuItem<String?>(
                                      value: b,
                                      child: Text(b),
                                    ),
                                  ),
                                ],
                                onChanged: (v) =>
                                    setState(() => _selectedBarangay = v),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_filteredEvacuees.length} of ${_evacuees.length} logged',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Expanded(
                    child: _filteredEvacuees.isEmpty
                        ? ListView(
                            children: [
                              const SizedBox(height: 80),
                              Icon(
                                Icons.how_to_reg_outlined,
                                color: Colors.grey[350],
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Center(
                                child: Text(
                                  'No evacuees logged yet.',
                                  style: TextStyle(color: Colors.grey[500]),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            itemCount: _filteredEvacuees.length,
                            itemBuilder: (context, index) {
                              final e = _filteredEvacuees[index];
                              final center = e['evacuation_center'];
                              final centerName = center is Map
                                  ? center['name']
                                  : null;
                              final isMale = e['gender'] == 'Male';

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundColor: isMale
                                          ? const Color(0xFFDBEAFE)
                                          : const Color(0xFFFCE7F3),
                                      child: Icon(
                                        isMale ? Icons.male : Icons.female,
                                        color: isMale
                                            ? const Color(0xFF1E40AF)
                                            : const Color(0xFF9D174D),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _fullName(e),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                              color: Color(0xFF1A1A2E),
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${e['age']} yrs · Brgy. ${e['barangay'] ?? '—'}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          if (centerName != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              centerName.toString(),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: _gradientTop,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
