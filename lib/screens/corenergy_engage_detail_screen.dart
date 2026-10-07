import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import '../models/corenergy_engage.dart';
import '../models/lookup_models.dart';
import '../services/api_service.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'detail_screen.dart'; // Import searchable institution picker if reusable

class COREnergyEngageDetailScreen extends StatefulWidget {
  final COREnergyEngage? engage; // Optional parameter for editing mode
  final List<Institution> institutions;
  final List<String> salesReps;
  final List<PsgcLocation> psgcLocations;

  const COREnergyEngageDetailScreen({
    Key? key,
    this.engage,
    required this.institutions,
    required this.salesReps,
    required this.psgcLocations,
  }) : super(key: key);

  @override
  State<COREnergyEngageDetailScreen> createState() => _COREnergyEngageDetailScreenState();
}

class _COREnergyEngageDetailScreenState extends State<COREnergyEngageDetailScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  
  late TabController _tabController;
  bool _isLocationVerified = false;
  String? _locationAccuracy;
  DateTime? _locationTimestamp;
  
  String? _selectedCompany; // Holds Institution Link ID (e.g. INST-00001)
  String? _selectedSalesRep;
  String? _selectedOwnershipNationality;

  // Ownership Nationality options matching ERPNext selector field
  final List<String> _ownershipNationalityOptions = [
    'Filipino',
    'Foreign',
    'Other',
  ];
  
  final _hospitalClinicController = TextEditingController();
  final _regionController = TextEditingController();
  final _provinceController = TextEditingController();
  final _cityMunicipalityController = TextEditingController();
  final _streetAddressController = TextEditingController();
  
  // Stored Codes for submission to ERPNext Link fields
  String? _regionCode;
  String? _provinceCode;
  String? _cityMunicipalityCode;

  // Dynamic lists from psgcLocations
  List<GeographicUnit> _dynamicRegions = [];
  List<GeographicUnit> _dynamicProvinces = [];
  List<GeographicUnit> _dynamicCities = [];

  // Child Tables state
  final List<COREnergyEngageContact> _contactsList = [];
  final List<COREnergyEngageVisit> _visitsList = [];
  final List<COREnergyEngageActionItem> _actionItemsList = [];

  bool _isSaving = false;
  bool _isLocating = false;
  bool _isLoadingDetails = false;
  String? _latitude;
  String? _longitude;
  final MapController _mapController = MapController();

  // Unsuccessful call dropdown options
  final List<String> _unsuccessfulCallReasons = [
    'Prior appointment or letter needed',
    'Contact not available',
    'Company no longer operational',
    'Company moved to different address',
    'Call - Invalid or Cannot be reached',
    'Call - Wrong number',
    'Call - 3 Attempt, no answer',
    'Call - Declined or Rejected',
  ];

  String _resolveLocationName(String? code, String type) {
    if (code == null || code.isEmpty) return '';
    
    // 1. Try to find in widget.psgcLocations
    if (widget.psgcLocations.isNotEmpty) {
      final match = widget.psgcLocations.firstWhere(
        (loc) => loc.name == code,
        orElse: () => PsgcLocation(name: '', locationLabel: '', locationType: ''),
      );
      if (match.locationLabel.isNotEmpty) {
        return match.locationLabel;
      }
    }
    
    // 2. Try to find in hardcoded lists
    if (type == 'Region') {
      final unit = _regionsList.firstWhere(
        (u) => u.code == code || u.name == code,
        orElse: () => GeographicUnit('', ''),
      );
      if (unit.name.isNotEmpty) return unit.name;
    } else if (type == 'Province') {
      final unit = _provincesList.firstWhere(
        (u) => u.code == code || u.name == code,
        orElse: () => GeographicUnit('', ''),
      );
      if (unit.name.isNotEmpty) return unit.name;
    } else if (type == 'City') {
      final unit = _citiesList.firstWhere(
        (u) => u.code == code || u.name == code,
        orElse: () => GeographicUnit('', ''),
      );
      if (unit.name.isNotEmpty) return unit.name;
    }
    
    return code;
  }

  @override
  void initState() {
    super.initState();
    final apiService = Provider.of<ApiService>(context, listen: false);

    // Initialize dynamic location lists from psgcLocations if available
    if (widget.psgcLocations.isNotEmpty) {
      _dynamicRegions = widget.psgcLocations
          .where((l) => l.locationType == 'Region')
          .map((l) => GeographicUnit(l.locationLabel, l.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _dynamicProvinces = widget.psgcLocations
          .where((l) => l.locationType == 'Province')
          .map((l) => GeographicUnit(l.locationLabel, l.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _dynamicCities = widget.psgcLocations
          .where((l) => l.locationType == 'City')
          .map((l) => GeographicUnit(l.locationLabel, l.name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } else {
      _dynamicRegions = _regionsList;
      _dynamicProvinces = _provincesList;
      _dynamicCities = _citiesList;
    }
    
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabSelection);

    if (widget.engage != null) {
      // Editing Mode
      _selectedCompany = widget.engage!.institutionName ?? widget.engage!.name;
      _hospitalClinicController.text = widget.engage!.hospitalClinic ?? '';
      
      _regionCode = widget.engage!.region;
      _provinceCode = widget.engage!.province;
      _cityMunicipalityCode = widget.engage!.cityMunicipality;

      _regionController.text = _resolveLocationName(widget.engage!.region, 'Region');
      _provinceController.text = _resolveLocationName(widget.engage!.province, 'Province');
      _cityMunicipalityController.text = _resolveLocationName(widget.engage!.cityMunicipality, 'City');

      _streetAddressController.text = widget.engage!.streetAddress ?? '';
      _selectedSalesRep = widget.engage!.salesRep ?? apiService.loggedInEmail;
      _selectedOwnershipNationality = widget.engage!.ownershipNationality;
      
      if (widget.engage!.latitude != null &&
          widget.engage!.longitude != null &&
          widget.engage!.latitude!.isNotEmpty &&
          widget.engage!.longitude!.isNotEmpty &&
          widget.engage!.latitude != '0.0' &&
          widget.engage!.longitude != '0.0') {
        _latitude = widget.engage!.latitude;
        _longitude = widget.engage!.longitude;
        _locationAccuracy = widget.engage!.locationAccuracy;
      }

      // Load initial flat details from widget.engage
      _contactsList.addAll(widget.engage!.contacts);
      _visitsList.addAll(widget.engage!.visits);
      _actionItemsList.addAll(widget.engage!.actionItems);

      // Asynchronously fetch complete document (with child tables) from server
      _loadFullDetails();
    } else {
      // Creation Mode
      _selectedSalesRep = apiService.loggedInEmail ?? 'jptan@profinsights.biz';
    }
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging && _tabController.index > 0 && !_isLocationVerified) {
      final targetIndex = _tabController.index;
      _tabController.animateTo(0);
      _showLocationRequiredDialog(targetIndex);
    }
  }

  void _showLocationRequiredDialog([int? targetTab]) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.location_on, color: Color(0xFF0056B3), size: 26),
            SizedBox(width: 8),
            Text('Location Required', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To ensure that you are covering this institution accurately on-site, you must get your current GPS location first before proceeding to Contacts, Engagements, or Action Items.',
              style: TextStyle(fontSize: 14, height: 1.4, color: Color(0xFF3A3A3C)),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0056B3).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.verified, size: 16, color: Color(0xFF0056B3)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Physical geotag verification ensures high coverage accuracy.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF0056B3), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0056B3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.my_location, size: 16, color: Colors.white),
            label: const Text('Get Current Location', style: TextStyle(color: Colors.white)),
            onPressed: () async {
              Navigator.pop(ctx);
              await _fetchGPS();
              if (_isLocationVerified && targetTab != null && mounted) {
                _tabController.animateTo(targetTab);
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _loadFullDetails() async {
    setState(() {
      _isLoadingDetails = true;
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final fullEngage = await apiService.fetchCOREnergyEngageByName(widget.engage!.name);
      setState(() {
        _contactsList.clear();
        _visitsList.clear();
        _actionItemsList.clear();
        
        _contactsList.addAll(fullEngage.contacts);
        _visitsList.addAll(fullEngage.visits);
        _actionItemsList.addAll(fullEngage.actionItems);
        // Update ownership nationality from full details if available
        if (fullEngage.ownershipNationality != null && fullEngage.ownershipNationality!.isNotEmpty) {
          _selectedOwnershipNationality = fullEngage.ownershipNationality;
        }
        if (fullEngage.latitude != null &&
            fullEngage.longitude != null &&
            fullEngage.latitude!.isNotEmpty &&
            fullEngage.longitude!.isNotEmpty &&
            fullEngage.latitude != '0.0' &&
            fullEngage.longitude != '0.0') {
          _latitude = fullEngage.latitude;
          _longitude = fullEngage.longitude;
          _locationAccuracy = fullEngage.locationAccuracy;
        }
        _isLoadingDetails = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingDetails = false;
      });
      print('Fetch full details error: $e');
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _hospitalClinicController.dispose();
    _regionController.dispose();
    _provinceController.dispose();
    _cityMunicipalityController.dispose();
    _streetAddressController.dispose();
    super.dispose();
  }

  void _onInstitutionSelected(Institution inst) {
    setState(() {
      _selectedCompany = inst.name;
      _hospitalClinicController.text = inst.institutionName;
      
      _regionCode = inst.regionName;
      _provinceCode = inst.provinceName;
      _cityMunicipalityCode = inst.cityMunicipality;

      _regionController.text = _resolveLocationName(inst.regionName, 'Region');
      _provinceController.text = _resolveLocationName(inst.provinceName, 'Province');
      _cityMunicipalityController.text = _resolveLocationName(inst.cityMunicipality, 'City');

      _streetAddressController.text = inst.streetAddress ?? '';
    });
  }

  Future<void> _fetchGPS() async {
    setState(() {
      _isLocating = true;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Location Services Disabled'),
              content: const Text('Please enable GPS / Location Services on your device to verify coverage.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Geolocator.openLocationSettings();
                  },
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );
        }
        setState(() {
          _isLocating = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission is required to verify institution coverage.'),
              backgroundColor: const Color(0xFFFF3B30),
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () {
                  Geolocator.openAppSettings();
                },
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
        setState(() {
          _isLocating = false;
        });
        return;
      }

      // 1. High-precision attempt
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 12),
        );
      } catch (_) {
        // Fallback to LocationAccuracy.high
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 8),
          );
        } catch (_) {
          position = await Geolocator.getLastKnownPosition();
        }
      }

      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not acquire GPS fix. Please ensure you are outdoors or near a window and try again.'),
              backgroundColor: Color(0xFFFF3B30),
              duration: Duration(seconds: 5),
            ),
          );
        }
        setState(() {
          _isLocating = false;
        });
        return;
      }

      final latStr = position.latitude.toStringAsFixed(6);
      final lngStr = position.longitude.toStringAsFixed(6);
      final accuracyStr = '±${position.accuracy.toStringAsFixed(1)}m';

      setState(() {
        _latitude = latStr;
        _longitude = lngStr;
        _locationAccuracy = accuracyStr;
        _locationTimestamp = DateTime.now();
        _isLocationVerified = true;
        _isLocating = false;
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        try {
          final lat = double.tryParse(_latitude ?? '');
          final lng = double.tryParse(_longitude ?? '');
          if (lat != null && lng != null) {
            _mapController.move(LatLng(lat, lng), 16.0);
          }
        } catch (_) {}
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Current location verified ($accuracyStr). All tabs unlocked!'),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF34C759),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isLocating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS error: $e. Please verify GPS is enabled.'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCompany == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a company / institution')),
      );
      return;
    }

    // Ensure each visit has either successful or unsuccessful checked
    for (int i = 0; i < _visitsList.length; i++) {
      final v = _visitsList[i];
      if (!v.successfulCall && !v.unsuccessfulCall) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please mark Visit #${i + 1} as either Successful or Unsuccessful'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
        return;
      }
    }

    setState(() {
      _isSaving = true;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);

    final resolvedInstitutionName = (() {
      final match = widget.institutions.firstWhere(
        (i) => i.name == _selectedCompany,
        orElse: () => Institution(
          name: _selectedCompany!,
          institutionName: _hospitalClinicController.text.trim().isNotEmpty
              ? _hospitalClinicController.text.trim()
              : _selectedCompany!,
        ),
      );
      return match.institutionName.isNotEmpty ? match.institutionName : _selectedCompany!;
    })();

    final payload = COREnergyEngage(
      name: _selectedCompany!,
      institutionName: resolvedInstitutionName,
      hospitalClinic: _hospitalClinicController.text.trim().isEmpty ? resolvedInstitutionName : _hospitalClinicController.text.trim(),
      region: _regionCode,
      province: _provinceCode,
      cityMunicipality: _cityMunicipalityCode,
      streetAddress: _streetAddressController.text.trim().isEmpty ? null : _streetAddressController.text.trim(),
      salesRep: _selectedSalesRep,
      ownershipNationality: _selectedOwnershipNationality,
      latitude: _latitude,
      longitude: _longitude,
      locationAccuracy: _locationAccuracy,
      contacts: _contactsList,
      visits: _visitsList,
      actionItems: _actionItemsList,
    );

    try {
      if (widget.engage != null) {
        // Update existing record
        await apiService.updateCOREnergyEngage(widget.engage!.name, payload);
      } else {
        // Create new record
        await apiService.createCOREnergyEngage(payload);
      }
      
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.engage != null 
                ? 'COREnergy Engage Copy updated successfully' 
                : 'COREnergy Engage Copy submitted successfully'),
            backgroundColor: const Color(0xFF30D158),
          ),
        );
        Navigator.of(context).pop(true); // Return success to reload list
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  void _showSearchableInstitutionPicker() {
    // Only allow selecting institution if in creation mode
    if (widget.engage != null) return;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SearchableInstitutionPicker(
          institutions: widget.institutions,
          onSelected: _onInstitutionSelected,
        );
      },
    );
  }

  void _showGeographicUnitPicker(String title, List<GeographicUnit> units, Function(GeographicUnit) onSelected) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return GeographicUnitPicker(
          title: title,
          units: units,
          onSelected: onSelected,
        );
      },
    );
  }

  // Child table row adders
  void _addContactRow() {
    setState(() {
      _contactsList.add(COREnergyEngageContact());
    });
  }

  void _addVisitRow() {
    setState(() {
      _visitsList.add(COREnergyEngageVisit());
    });
  }

  void _addActionItemRow() {
    setState(() {
      _actionItemsList.add(COREnergyEngageActionItem(
        targetDate: DateTime.now().toString().substring(0, 10),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(widget.engage != null ? 'Edit COREnergy Engage Copy' : 'New COREnergy Engage Copy'),
        backgroundColor: const Color(0xFF0056B3),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          _isSaving
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                  ),
                )
              : TextButton(
                  onPressed: _saveForm,
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
        ],
        bottom: TabBar(
          controller: _tabController,
          onTap: (index) {
            if (index > 0 && !_isLocationVerified) {
              _tabController.animateTo(0);
              _showLocationRequiredDialog(index);
            }
          },
          isScrollable: false,
          indicatorColor: Colors.white,
          indicatorWeight: 3.5,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          tabs: [
            const Tab(
              icon: Icon(Icons.info_outline, size: 18),
              text: 'Details',
            ),
            Tab(
              icon: Icon(_isLocationVerified ? Icons.contacts_outlined : Icons.lock_outline, size: 18),
              text: 'Contacts',
            ),
            Tab(
              icon: Icon(_isLocationVerified ? Icons.handshake_outlined : Icons.lock_outline, size: 18),
              text: 'Engagements',
            ),
            Tab(
              icon: Icon(_isLocationVerified ? Icons.assignment_outlined : Icons.lock_outline, size: 18),
              text: 'Action Items',
            ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          physics: _isLocationVerified ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
          children: [
            _buildDetailsTab(),
            _buildContactsTab(),
            _buildEngagementsTab(),
            _buildActionItemsTab(),
          ],
        ),
      ),
    );
  }

  // --- TAB BUILDERS ---

  Widget _buildDetailsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Location verification warning or verified badge banner
        if (!_isLocationVerified)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9E6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFFCC00), width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9500), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Coverage Verification Required',
                        style: TextStyle(color: Color(0xFF8A5300), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'You must get current location first before proceeding in the other 3 tabs (Contacts, Engagements, Action Items) to verify accurate coverage.',
                        style: TextStyle(color: Color(0xFF8A5300), fontSize: 12, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F9ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF34C759), width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, color: Color(0xFF34C759), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'On-Site Coverage Verified ($_locationAccuracy)',
                        style: const TextStyle(color: Color(0xFF1B6A2E), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'GPS: $_latitude, $_longitude • All tabs unlocked for reporting',
                        style: const TextStyle(color: Color(0xFF28793C), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Header card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF0056B3).withOpacity(0.08), const Color(0xFF0056B3).withOpacity(0.02)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD1D1D6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'COREnergy Engage Copy Log',
                style: TextStyle(color: Color(0xFF636366), fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                _selectedCompany != null ? 'ID: $_selectedCompany' : 'Select Institution to start',
                style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Company selector input
        const Text('INSTITUTION NAME *', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: widget.engage != null ? null : _showSearchableInstitutionPicker, // Disable link changes in edit mode
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: widget.engage != null ? const Color(0xFFE5E5EA).withOpacity(0.5) : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D1D6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedCompany == null
                        ? 'Tap to select Company...'
                        : (() {
                            final match = widget.institutions.firstWhere(
                              (i) => i.name == _selectedCompany,
                              orElse: () => Institution(
                                name: _selectedCompany!,
                                institutionName: _hospitalClinicController.text.trim().isNotEmpty
                                    ? _hospitalClinicController.text.trim()
                                    : _selectedCompany!,
                              ),
                            );
                            final instName = (match.institutionName.isNotEmpty && match.institutionName != match.name)
                                ? match.institutionName
                                : (_hospitalClinicController.text.trim().isNotEmpty
                                    ? _hospitalClinicController.text.trim()
                                    : match.institutionName);

                            if (instName.isNotEmpty && instName != match.name && match.name.isNotEmpty) {
                              return '$instName - ${match.name}';
                            }
                            return instName;
                          })(),
                    style: TextStyle(
                      color: _selectedCompany == null ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.engage == null)
                  const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        _buildInputField(
          controller: _hospitalClinicController,
          label: 'Name of hospital or clinic',
          hint: 'Auto-filled upon selecting institution',
          readOnly: true,
        ),
        const SizedBox(height: 16),

        // Region Selector
        const Text('REGION', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _showGeographicUnitPicker('Region', _dynamicRegions, (unit) {
            setState(() {
              _regionController.text = unit.name;
              _regionCode = unit.code;
              // Reset dependent province and city filters
              _provinceController.clear();
              _provinceCode = null;
              _cityMunicipalityController.clear();
              _cityMunicipalityCode = null;
            });
          }),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D1D6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _regionController.text.isEmpty ? 'Tap to select Region...' : _regionController.text,
                    style: TextStyle(
                      color: _regionController.text.isEmpty ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Province Selector
        const Text('PROVINCE', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            // Get provinces filtered by selected region if online
            List<GeographicUnit> filteredProvinces = _dynamicProvinces;
            if (_regionCode != null && widget.psgcLocations.isNotEmpty) {
              final list = widget.psgcLocations
                  .where((l) => l.locationType == 'Province' && l.parentPsgcLocation == _regionCode)
                  .map((l) => GeographicUnit(l.locationLabel, l.name))
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              if (list.isNotEmpty) filteredProvinces = list;
            }
            _showGeographicUnitPicker('Province', filteredProvinces, (unit) {
              setState(() {
                _provinceController.text = unit.name;
                _provinceCode = unit.code;
                // Reset city
                _cityMunicipalityController.clear();
                _cityMunicipalityCode = null;
              });
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D1D6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _provinceController.text.isEmpty ? 'Tap to select Province...' : _provinceController.text,
                    style: TextStyle(
                      color: _provinceController.text.isEmpty ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // City/Municipality Selector
        const Text('CITY/MUNICIPALITY', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {
            List<GeographicUnit> filteredCities = _dynamicCities;
            if (_provinceCode != null && widget.psgcLocations.isNotEmpty) {
              final list = widget.psgcLocations
                  .where((l) => l.locationType == 'City' && l.parentPsgcLocation == _provinceCode)
                  .map((l) => GeographicUnit(l.locationLabel, l.name))
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              if (list.isNotEmpty) filteredCities = list;
            }
            _showGeographicUnitPicker('City/Municipality', filteredCities, (unit) {
              setState(() {
                _cityMunicipalityController.text = unit.name;
                _cityMunicipalityCode = unit.code;
              });
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D1D6)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _cityMunicipalityController.text.isEmpty ? 'Tap to select City/Municipality...' : _cityMunicipalityController.text,
                    style: TextStyle(
                      color: _cityMunicipalityController.text.isEmpty ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        _buildInputField(
          controller: _streetAddressController,
          label: 'Street Address',
          hint: 'Street details',
        ),
        const SizedBox(height: 16),

        const Text('SALES REP *', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildDropdownField<String>(
          value: _selectedSalesRep,
          hint: 'Select Rep...',
          items: widget.salesReps,
          onChanged: (val) {
            setState(() {
              _selectedSalesRep = val;
            });
          },
          validator: (val) => val == null ? 'Please select a Sales Rep' : null,
        ),
        const SizedBox(height: 16),

        const Text('OWNERSHIP NATIONALITY', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _buildDropdownField<String>(
          value: _selectedOwnershipNationality,
          hint: 'Select Nationality...',
          items: _ownershipNationalityOptions,
          onChanged: (val) {
            setState(() {
              _selectedOwnershipNationality = val;
            });
          },
        ),
        const SizedBox(height: 24),

        ElevatedButton.icon(
          onPressed: _isLocating ? null : _fetchGPS,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isLocationVerified ? const Color(0xFF34C759) : const Color(0xFF0056B3),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 1,
          ),
          icon: _isLocating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(_isLocationVerified ? Icons.check_circle : Icons.my_location, size: 20),
          label: Text(
            _isLocating
                ? 'Acquiring High-Precision GPS...'
                : (_isLocationVerified ? 'Re-verify Current Location ($_locationAccuracy)' : 'Get Current Location (Required to unlock tabs)'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        if (_latitude != null && _longitude != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFD1D1D6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('Lat: $_latitude', style: const TextStyle(color: Color(0xFF1C1C1E), fontFamily: 'monospace', fontSize: 13))),
                    Expanded(child: Text('Lng: $_longitude', style: const TextStyle(color: Color(0xFF1C1C1E), fontFamily: 'monospace', fontSize: 13))),
                  ],
                ),
                if (_locationAccuracy != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.gps_fixed, size: 14, color: Color(0xFF34C759)),
                      const SizedBox(width: 4),
                      Text(
                        'Accuracy: $_locationAccuracy',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF34C759)),
                      ),
                      if (_locationTimestamp != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '• Verified at ${_locationTimestamp!.hour.toString().padLeft(2, '0')}:${_locationTimestamp!.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93)),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1D1D6)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(
                    double.tryParse(_latitude!) ?? 14.3129,
                    double.tryParse(_longitude!) ?? 121.1009,
                  ),
                  initialZoom: 15.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.pims.mcp_corenergy',
                    maxZoom: 19,
                    fallbackUrl: 'https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        width: 40.0,
                        height: 40.0,
                        point: LatLng(
                          double.tryParse(_latitude!) ?? 14.3129,
                          double.tryParse(_longitude!) ?? 121.1009,
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFFFF3B30),
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildLocationLockedView(String tabName) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9500).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.location_off_rounded, size: 52, color: Color(0xFFFF9500)),
            ),
            const SizedBox(height: 20),
            const Text(
              'On-Site Verification Required',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
            ),
            const SizedBox(height: 10),
            Text(
              'To ensure that you are covering this institution accurately, you must get your current GPS location before managing $tabName.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF636366), height: 1.4),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isLocating ? null : () async {
                await _fetchGPS();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0056B3),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              icon: _isLocating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.my_location, size: 20),
              label: Text(
                _isLocating ? 'Acquiring High-Precision GPS...' : 'Get Current Location Now',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () {
                _tabController.animateTo(0);
              },
              child: const Text('Back to Institution Details', style: TextStyle(color: Color(0xFF0056B3))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactsTab() {
    if (!_isLocationVerified) {
      return _buildLocationLockedView('Contacts');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CONTACTS TABLE',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF636366), fontSize: 13),
              ),
              ElevatedButton.icon(
                onPressed: _addContactRow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0056B3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Add Row', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _contactsList.isEmpty
              ? const Center(
                  child: Text('No contacts added yet. Tap Add Row to start.', style: TextStyle(color: Color(0xFF8E8E93))),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _contactsList.length,
                  itemBuilder: (context, index) {
                    final row = _contactsList[index];
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFD1D1D6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('CONTACT #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0056B3), fontSize: 12)),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30), size: 20),
                                  onPressed: () {
                                    setState(() {
                                      _contactsList.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: row.contactName,
                              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                              decoration: const InputDecoration(labelText: 'Contact Name *', hintText: 'Full Name'),
                              onChanged: (val) => row.contactName = val,
                              validator: (val) => val == null || val.trim().isEmpty ? 'Contact Name is required' : null,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: row.position,
                              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                              decoration: const InputDecoration(labelText: 'Position', hintText: 'e.g. Doctor, Purchasing'),
                              onChanged: (val) => row.position = val,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: row.email,
                              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                              decoration: const InputDecoration(labelText: 'Email', hintText: 'email@domain.com'),
                              onChanged: (val) => row.email = val,
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              initialValue: row.phoneMobile,
                              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                              decoration: const InputDecoration(labelText: 'Phone / Mobile', hintText: 'Mobile number'),
                              onChanged: (val) => row.phoneMobile = val,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEngagementsTab() {
    if (!_isLocationVerified) {
      return _buildLocationLockedView('Engagements / Visits');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'VISITS / CALLS TABLE',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF636366), fontSize: 13),
              ),
              ElevatedButton.icon(
                onPressed: _addVisitRow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0056B3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Add Row', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _visitsList.isEmpty
              ? const Center(
                  child: Text('No visits/calls added yet. Tap Add Row to start.', style: TextStyle(color: Color(0xFF8E8E93))),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _visitsList.length,
                  itemBuilder: (context, index) {
                    final row = _visitsList[index];
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFD1D1D6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('VISIT #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0056B3), fontSize: 12)),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30), size: 20),
                                  onPressed: () {
                                    setState(() {
                                      _visitsList.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            
                             // Checkbox: Successful Call
                             CheckboxListTile(
                               title: const Text('Successful Call', style: TextStyle(fontSize: 14)),
                               value: row.successfulCall,
                               activeColor: const Color(0xFF0056B3),
                               onChanged: (val) {
                                 setState(() {
                                   row.successfulCall = val ?? false;
                                   if (row.successfulCall) {
                                     row.unsuccessfulCall = false;
                                     row.reasonForUnsuccessfulCall = null;
                                   } else {
                                     row.decisionMakerNotAvailable = false;
                                   }
                                 });
                               },
                             ),

                             // Checkbox: Unsuccessful Call
                             CheckboxListTile(
                               title: const Text('Unsuccessful Call', style: TextStyle(fontSize: 14)),
                               value: row.unsuccessfulCall,
                               activeColor: const Color(0xFF0056B3),
                               onChanged: (val) {
                                 setState(() {
                                   row.unsuccessfulCall = val ?? false;
                                   if (row.unsuccessfulCall) {
                                     row.successfulCall = false;
                                     row.decisionMakerNotAvailable = false;
                                   }
                                 });
                               },
                             ),

                             // Reason dropdown if Unsuccessful
                             if (row.unsuccessfulCall) ...[
                               const SizedBox(height: 8),
                               const Text('Reason for Unsuccessful Call', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
                               const SizedBox(height: 6),
                               _buildDropdownField<String>(
                                 value: row.reasonForUnsuccessfulCall,
                                 hint: 'Select reason...',
                                 items: _unsuccessfulCallReasons,
                                 onChanged: (val) {
                                   setState(() {
                                     row.reasonForUnsuccessfulCall = val;
                                   });
                                 },
                               ),
                             ],

                             const SizedBox(height: 8),

                             // Checkbox: Decision maker not available (Only visible if Successful Call is checked)
                             if (row.successfulCall) ...[
                               CheckboxListTile(
                                 title: const Text('Decision Maker / Responsible Person Not Available', style: TextStyle(fontSize: 14)),
                                 value: row.decisionMakerNotAvailable,
                                 activeColor: const Color(0xFF0056B3),
                                 onChanged: (val) {
                                   setState(() {
                                     row.decisionMakerNotAvailable = val ?? false;
                                   });
                                 },
                               ),
                               const SizedBox(height: 8),
                             ],
                            
                            TextFormField(
                              initialValue: row.notes,
                              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                              decoration: const InputDecoration(labelText: 'Notes / Remarks', hintText: 'Call remarks'),
                              onChanged: (val) => row.notes = val,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildActionItemsTab() {
    if (!_isLocationVerified) {
      return _buildLocationLockedView('Action Items');
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ACTION ITEMS / NEXT STEPS',
                style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF636366), fontSize: 13),
              ),
              ElevatedButton.icon(
                onPressed: _addActionItemRow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0056B3),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text('Add Row', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _actionItemsList.isEmpty
              ? const Center(
                  child: Text('No action items added yet. Tap Add Row to start.', style: TextStyle(color: Color(0xFF8E8E93))),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _actionItemsList.length,
                  itemBuilder: (context, index) {
                    final row = _actionItemsList[index];
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: Color(0xFFD1D1D6)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('ACTION ITEM #${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0056B3), fontSize: 12)),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFFF3B30), size: 20),
                                  onPressed: () {
                                    setState(() {
                                      _actionItemsList.removeAt(index);
                                    });
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text('Next Step *', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            _buildDropdownField<String>(
                              value: (row.nextStep != null && const ['Completed', 'Call or Send email', 'Revisit'].contains(row.nextStep)) ? row.nextStep : null,
                              hint: 'Select next step...',
                              items: const ['Completed', 'Call or Send email', 'Revisit'],
                              onChanged: (val) {
                                setState(() {
                                  row.nextStep = val;
                                });
                              },
                              validator: (val) => val == null || val.trim().isEmpty ? 'Next Step is required' : null,
                            ),
                            const SizedBox(height: 8),

                            // Target Date selection
                            Row(
                              children: [
                                Expanded(
                                  child: Text('Target Date: ${row.targetDate ?? "Not selected"}', style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E))),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2025),
                                      lastDate: DateTime(2035),
                                    );
                                    if (picked != null) {
                                      setState(() {
                                        row.targetDate = picked.toString().substring(0, 10);
                                      });
                                    }
                                  },
                                  child: const Text('Change Date', style: TextStyle(color: Color(0xFF0056B3), fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Status selection
                            const Text('Next Step Status', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            _buildDropdownField<String>(
                              value: (row.nextStepStatus == 'Complete' || row.nextStepStatus == 'Completed') ? 'Completed' : 'Incomplete',
                              hint: 'Select status...',
                              items: const ['Incomplete', 'Completed'],
                              onChanged: (val) {
                                setState(() {
                                  row.nextStepStatus = val;
                                  if (row.nextStepStatus == 'Completed') {
                                    row.dateCompleted = DateTime.now().toString().substring(0, 10);
                                  } else {
                                    row.dateCompleted = null;
                                  }
                                });
                              },
                            ),

                            if (row.nextStepStatus == 'Complete' || row.nextStepStatus == 'Completed') ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('Date Completed: ${row.dateCompleted ?? "Not selected"}', style: const TextStyle(fontSize: 14, color: Color(0xFF1C1C1E))),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2025),
                                        lastDate: DateTime(2035),
                                      );
                                      if (picked != null) {
                                        setState(() {
                                          row.dateCompleted = picked.toString().substring(0, 10);
                                        });
                                      }
                                    },
                                    child: const Text('Change Date', style: TextStyle(color: Color(0xFF0056B3), fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          style: TextStyle(color: readOnly ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E), fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: readOnly ? const Color(0xFFE5E5EA).withOpacity(0.5) : Colors.white,
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF0056B3), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdownField<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required ValueChanged<T?> onChanged,
    FormFieldValidator<T>? validator,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1D1D6)),
      ),
      child: DropdownButtonFormField<T>(
        value: value,
        hint: Text(hint, style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
        dropdownColor: Colors.white,
        icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
        style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
        onChanged: onChanged,
        validator: validator,
        decoration: const InputDecoration(border: InputBorder.none),
        items: items.map((item) {
          return DropdownMenuItem<T>(
            value: item,
            child: Text(
              item.toString(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF1C1C1E)),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class GeographicUnit {
  final String name;
  final String code;
  GeographicUnit(this.name, this.code);
}

final List<GeographicUnit> _regionsList = [
  GeographicUnit('Region I (Ilocos Region)', '0100000000'),
  GeographicUnit('Region II (Cagayan Valley)', '0200000000'),
  GeographicUnit('Region III (Central Luzon)', '0300000000'),
  GeographicUnit('CALABARZON', '0400000000'),
  GeographicUnit('MIMAROPA Region', '1700000000'),
  GeographicUnit('Region V (Bicol Region)', '0500000000'),
  GeographicUnit('Region VI (Western Visayas)', '0600000000'),
  GeographicUnit('Region VII (Central Visayas)', '0700000000'),
  GeographicUnit('Region VIII (Eastern Visayas)', '0800000000'),
  GeographicUnit('Region IX (Zamboanga Peninsula)', '0900000000'),
  GeographicUnit('Region X (Northern Mindanao)', '1000000000'),
  GeographicUnit('Region XI (Davao Region)', '1100000000'),
  GeographicUnit('Region XII (SOCCSKSARGEN)', '1200000000'),
  GeographicUnit('Region XIII (Caraga)', '1600000000'),
  GeographicUnit('BARMM', '1900000000'),
  GeographicUnit('CAR', '1400000000'),
  GeographicUnit('NCR', '1300000000'),
];

final List<GeographicUnit> _provincesList = [
  GeographicUnit('Ilocos Norte', '0102800000'),
  GeographicUnit('Ilocos Sur', '0102900000'),
  GeographicUnit('Pangasinan', '0105500000'),
  GeographicUnit('La Union', '0103300000'),
  GeographicUnit('Cavite', '0402100000'),
  GeographicUnit('Laguna', '0403400000'),
  GeographicUnit('Batangas', '0401000000'),
  GeographicUnit('Rizal', '0405800000'),
  GeographicUnit('Quezon', '0405600000'),
  GeographicUnit('Metro Manila-Manila', '1376000000'),
  GeographicUnit('Metro Manila-Pasig', '1376030000'),
  GeographicUnit('Metro Manila-Makati', '1376020000'),
  GeographicUnit('Bataan', '0300800000'),
  GeographicUnit('Bulacan', '0301400000'),
  GeographicUnit('Pampanga', '0305400000'),
  GeographicUnit('Cebu', '0702200000'),
  GeographicUnit('Davao del Sur', '1102400000'),
];

final List<GeographicUnit> _citiesList = [
  GeographicUnit('Adams', '0102801000'),
  GeographicUnit('Laoag City', '0102812000'),
  GeographicUnit('Vigan City', '0102921000'),
  GeographicUnit('Cavite City', '0402105000'),
  GeographicUnit('Gen. Mariano Alvarez', '0402123000'),
  GeographicUnit('Bacoor', '0402102000'),
  GeographicUnit('Imus', '0402111000'),
  GeographicUnit('Dasmariñas', '0402106000'),
  GeographicUnit('Ermita', '137601000'),
  GeographicUnit('Malate', '137602000'),
  GeographicUnit('Intramuros', '137603000'),
  GeographicUnit('Makati City', '137602000'),
  GeographicUnit('Quezon City', '137404000'),
  GeographicUnit('Pasig City', '137603000'),
  GeographicUnit('Cebu City', '0702217000'),
  GeographicUnit('Davao City', '1102404000'),
];

class GeographicUnitPicker extends StatefulWidget {
  final String title;
  final List<GeographicUnit> units;
  final Function(GeographicUnit) onSelected;

  const GeographicUnitPicker({
    Key? key,
    required this.title,
    required this.units,
    required this.onSelected,
  }) : super(key: key);

  @override
  State<GeographicUnitPicker> createState() => _GeographicUnitPickerState();
}

class _GeographicUnitPickerState extends State<GeographicUnitPicker> {
  List<GeographicUnit> _filteredList = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredList = widget.units;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.only(top: 10, left: 20, right: 20, bottom: 20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFD1D1D6), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Select ${widget.title}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
          ),
          const SizedBox(height: 14),
          TextField(
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
                _filteredList = widget.units
                    .where((u) => u.name.toLowerCase().contains(val.toLowerCase()) || u.code.contains(val))
                    .toList();
              });
            },
            decoration: InputDecoration(
              hintText: 'Search...',
              prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
              filled: true,
              fillColor: const Color(0xFFF2F2F7),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredList.length,
              itemBuilder: (context, index) {
                final unit = _filteredList[index];
                return ListTile(
                  title: Text(unit.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E))),
                  subtitle: Text(unit.code, style: const TextStyle(color: Color(0xFF8E8E93))),
                  onTap: () {
                    widget.onSelected(unit);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

