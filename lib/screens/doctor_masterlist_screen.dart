import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/hcp.dart';
import '../models/lookup_models.dart';
import '../models/hcp_account.dart';
import '../services/api_service.dart';
import 'doctor_profile_screen.dart';
import 'hcp_wizard_screen.dart';
import 'self_service_qr_screen.dart';
import 'list_screen.dart';
import 'submission_history_screen.dart';
import 'login_screen.dart';

class DoctorMasterlistScreen extends StatefulWidget {
  const DoctorMasterlistScreen({Key? key}) : super(key: key);

  @override
  State<DoctorMasterlistScreen> createState() => _DoctorMasterlistScreenState();
}

class _DoctorMasterlistScreenState extends State<DoctorMasterlistScreen> {
  List<Hcp> _allDoctors = [];
  List<Hcp> _filteredDoctors = [];
  List<Institution> _institutions = [];
  List<Specialization> _specializations = [];
  List<PsgcLocation> _psgcLocations = [];
  List<HcpType> _hcpTypes = [];

  bool _isLoading = true;
  String _searchQuery = '';
  
  // Selected filter values
  String? _selectedSpecialty;
  String? _selectedInstitution;
  String? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final doctors = await apiService.fetchDoctors();
      final institutions = await apiService.fetchInstitutions();
      final specializations = await apiService.fetchSpecializations();
      final psgc = await apiService.fetchPsgcLocations();
      final types = await apiService.fetchHcpTypes();

      final hcpAccounts = await apiService.hcpAccounts.list(
        filters: [['account_or_program', '=', apiService.selectedProgram]],
        fields: ['hcp'],
        limit: 1000,
      );
      final allowedHcpIds = hcpAccounts.map((a) => a.hcp).whereType<String>().toSet();

      setState(() {
        _allDoctors = doctors.where((d) => allowedHcpIds.contains(d.name)).toList();
        _institutions = institutions;
        _specializations = specializations.where((s) => !s.isGroup).toList();
        _psgcLocations = psgc;
        _hcpTypes = types;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading doctor list: $e')),
      );
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredDoctors = _allDoctors.where((doctor) {
        final fullName = '${doctor.firstName} ${doctor.lastName}'.toLowerCase();
        final matchesSearch = fullName.contains(_searchQuery.toLowerCase()) ||
            (doctor.name?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

        final matchesSpecialty = _selectedSpecialty == null ||
            doctor.specialties.any((s) => s.hcpSpecialty == _selectedSpecialty);

        final matchesInstitution = _selectedInstitution == null ||
            doctor.workplaces.any((w) => w.workplace == _selectedInstitution);

        final matchesLocation = _selectedLocation == null ||
            doctor.regionName == _selectedLocation ||
            doctor.provinceName == _selectedLocation ||
            doctor.cityMunicipality == _selectedLocation ||
            doctor.barangayName == _selectedLocation;

        return matchesSearch && matchesSpecialty && matchesInstitution && matchesLocation;
      }).toList();
    });
  }

  void _openDoctorProfile(Hcp doctor) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoctorProfileScreen(doctor: doctor),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  void _showAddDoctorDialog() {
    final formKey = GlobalKey<FormState>();
    String firstName = '';
    String lastName = '';
    // Use the first available HCP Type name from the server, or empty
    String? selectedType = _hcpTypes.isNotEmpty ? _hcpTypes.first.name : null;
    String selectedPractice = 'Both';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Register New Doctor', style: TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  style: const TextStyle(color: Color(0xFF1C1C1E)),
                  decoration: const InputDecoration(
                    labelText: 'First Name',
                    labelStyle: TextStyle(color: Color(0xFF636366)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD1D1D6))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0056B3), width: 2)),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                  onSaved: (val) => firstName = val!,
                ),
                TextFormField(
                  style: const TextStyle(color: Color(0xFF1C1C1E)),
                  decoration: const InputDecoration(
                    labelText: 'Last Name',
                    labelStyle: TextStyle(color: Color(0xFF636366)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD1D1D6))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0056B3), width: 2)),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Required' : null,
                  onSaved: (val) => lastName = val!,
                ),
                // HCP Type — fetched dynamically from HCP Type DocType
                DropdownButtonFormField<String>(
                  value: selectedType,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Color(0xFF1C1C1E)),
                  decoration: const InputDecoration(
                    labelText: 'HCP Type',
                    labelStyle: TextStyle(color: Color(0xFF636366)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD1D1D6))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0056B3), width: 2)),
                  ),
                  validator: (val) => val == null || val.isEmpty ? 'Please select an HCP Type' : null,
                  items: _hcpTypes.map((t) => DropdownMenuItem(
                    value: t.name,
                    child: Text(t.typeName, style: const TextStyle(color: Color(0xFF1C1C1E))),
                  )).toList(),
                  onChanged: (val) => selectedType = val,
                ),
                // HCP Practice — static dropdown (not a DocType)
                DropdownButtonFormField<String>(
                  value: selectedPractice,
                  dropdownColor: Colors.white,
                  style: const TextStyle(color: Color(0xFF1C1C1E)),
                  decoration: const InputDecoration(
                    labelText: 'Practice Mode',
                    labelStyle: TextStyle(color: Color(0xFF636366)),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFD1D1D6))),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF0056B3), width: 2)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Dispensing', child: Text('Dispensing', style: TextStyle(color: Color(0xFF1C1C1E)))),
                    DropdownMenuItem(value: 'Prescribing', child: Text('Prescribing', style: TextStyle(color: Color(0xFF1C1C1E)))),
                    DropdownMenuItem(value: 'Both', child: Text('Both', style: TextStyle(color: Color(0xFF1C1C1E)))),
                  ],
                  onChanged: (val) => selectedPractice = val!,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF636366))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0056B3)),
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                formKey.currentState!.save();
                Navigator.pop(ctx);
                setState(() => _isLoading = true);

                final apiService = Provider.of<ApiService>(context, listen: false);
                try {
                  final newDoctor = Hcp(
                    firstName: firstName,
                    lastName: lastName,
                    hcpType: selectedType!,  // Now sends the name ID (e.g. HCP-TYPE-01)
                    hcpPractice: selectedPractice,
                  );
                  final savedDoctor = await apiService.createDoctor(newDoctor);
                  
                  // Reconcile and link the newly registered doctor to the active program using HCP Account
                  final newHcpAccount = HcpAccount(
                    accountName: apiService.selectedProgram,
                    hcp: savedDoctor.name,
                  );
                  await apiService.hcpAccounts.create(newHcpAccount);

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Doctor registered and linked to active program successfully!')),
                    );
                  }
                  _loadData();
                } catch (e) {
                  setState(() => _isLoading = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to save: $e')),
                    );
                  }
                }
              }
            },
            child: const Text('Register', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Doctor Masterlist'),
        backgroundColor: const Color(0xFF0056B3),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage('assets/medical_bg.jpg'),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.4)),
                      ),
                      child: const Icon(Icons.donut_large, color: Colors.white, size: 26),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'PIMS HCP',
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      Provider.of<ApiService>(context, listen: false).loggedInEmail ?? '',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                    ),
                  ],
                ),
              ),
              // Dynamic Program Selector Dropdown
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Consumer<ApiService>(
                  builder: (context, api, child) {
                    return DropdownButtonFormField<String>(
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: Color(0xFF1C1C1E)),
                      value: api.selectedProgram,
                      decoration: const InputDecoration(
                        labelText: 'Active Program',
                        labelStyle: TextStyle(color: Color(0xFF0056B3), fontWeight: FontWeight.bold),
                        prefixIcon: Icon(Icons.business_center, color: Color(0xFF0056B3)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFFD1D1D6)),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF0056B3), width: 2),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ),
                      items: api.availablePrograms.map((prog) {
                        return DropdownMenuItem<String>(
                          value: prog,
                          child: Text(prog),
                        );
                      }).toList(),
                      onChanged: (newProg) {
                        if (newProg != null) {
                          api.setProgram(newProg);
                          _loadData();
                        }
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              // Navigation Items
              ListTile(
                leading: const Icon(Icons.people_alt, color: Color(0xFF0056B3)),
                title: const Text('Doctor Masterlist', style: TextStyle(color: Color(0xFF0056B3), fontWeight: FontWeight.bold)),
                selected: true,
                selectedTileColor: const Color(0xFF0056B3).withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.assignment, color: Color(0xFF34C759)),
                title: const Text('Engagements', style: TextStyle(color: Color(0xFF1C1C1E))),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const ListScreen()));
                },
              ),
              ListTile(
                leading: const Icon(Icons.history, color: Color(0xFFFF9500)),
                title: const Text('Submission History', style: TextStyle(color: Color(0xFF1C1C1E))),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SubmissionHistoryScreen()));
                },
              ),
              const Spacer(),
              const Divider(color: Color(0xFFD1D1D6)),
              ListTile(
                leading: const Icon(Icons.logout, color: Color(0xFFFF3B30)),
                title: const Text('Logout', style: TextStyle(color: Color(0xFFFF3B30))),
                onTap: () {
                  Provider.of<ApiService>(context, listen: false).logout();
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0056B3)),
              ),
            )
          : Column(
              children: [
                // Filter Header
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Color(0xFFE5E5EA))),
                  ),
                  child: Column(
                    children: [
                      // Search Doctor
                      TextField(
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                            _applyFilters();
                          });
                        },
                        style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Search doctors by name or ID...',
                          hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                          prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
                          filled: true,
                          fillColor: const Color(0xFFF4F6F9),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Dropdown Filters
                      Row(
                        children: [
                          // Specialty Filter
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFD1D1D6)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedSpecialty,
                                  dropdownColor: Colors.white,
                                  hint: const Text('Specialty', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                                  style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 12),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedSpecialty = val;
                                      _applyFilters();
                                    });
                                  },
                                  items: [
                                    const DropdownMenuItem<String>(value: null, child: Text('All Specialties')),
                                    ..._specializations.map((spec) => DropdownMenuItem(
                                          value: spec.specialty,
                                          child: Text(spec.specialty, style: const TextStyle(color: Color(0xFF1C1C1E))),
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Hospital Filter
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFD1D1D6)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedInstitution,
                                  dropdownColor: Colors.white,
                                  hint: const Text('Hospital', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                                  style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 12),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedInstitution = val;
                                      _applyFilters();
                                    });
                                  },
                                  items: [
                                    const DropdownMenuItem<String>(value: null, child: Text('All Hospitals')),
                                    ..._institutions.map((inst) => DropdownMenuItem(
                                          value: inst.name,
                                          child: Text(inst.institutionName, style: const TextStyle(color: Color(0xFF1C1C1E))),
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Area / Location Filter
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFD1D1D6)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedLocation,
                                  dropdownColor: Colors.white,
                                  hint: const Text('Area / Location', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                                  style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 12),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedLocation = val;
                                      _applyFilters();
                                    });
                                  },
                                  items: [
                                    const DropdownMenuItem<String>(value: null, child: Text('All Areas')),
                                    ..._psgcLocations.map((loc) => DropdownMenuItem(
                                          value: loc.name,
                                          child: Text('${loc.locationLabel} (${loc.locationType})', style: const TextStyle(color: Color(0xFF1C1C1E))),
                                        )),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Doctor List View
                Expanded(
                  child: _filteredDoctors.isEmpty
                      ? const Center(
                          child: Text('No doctors match your criteria.', style: TextStyle(color: Color(0xFF8E8E93))),
                        )
                      : ListView.builder(
                          itemCount: _filteredDoctors.length,
                          itemBuilder: (ctx, index) {
                            final doctor = _filteredDoctors[index];
                            final primarySpecialty = doctor.specialties.isNotEmpty
                                ? doctor.specialties.first.hcpSpecialty
                                : 'No Specialty Declared';
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(color: const Color(0xFFE5E5EA)),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 5,
                                          color: const Color(0xFF0056B3),
                                        ),
                                        Expanded(
                                          child: ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            leading: CircleAvatar(
                                              backgroundColor: const Color(0xFF0056B3).withOpacity(0.08),
                                              child: const Icon(Icons.person, color: Color(0xFF0056B3)),
                                            ),
                                            title: Text(
                                              'Dr. ${doctor.firstName} ${doctor.lastName}',
                                              style: const TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.bold),
                                            ),
                                            subtitle: Padding(
                                              padding: const EdgeInsets.only(top: 4.0),
                                              child: Text(
                                                '$primarySpecialty • ${doctor.hcpType}',
                                                style: const TextStyle(color: Color(0xFF636366), fontSize: 13),
                                              ),
                                            ),
                                            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF8E8E93)),
                                            onTap: () => _openDoctorProfile(doctor),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF0056B3),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: _showAddDoctorDialog,
      ),
    );
  }
}
