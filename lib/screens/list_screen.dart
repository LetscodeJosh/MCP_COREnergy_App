import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../app_config.dart';
import '../models/engagement.dart';
import '../models/lookup_models.dart';
import '../services/api_service.dart';
import 'detail_screen.dart';
import 'login_screen.dart';
import '../models/corenergy_engage.dart';
import 'corenergy_engage_detail_screen.dart';

class ListScreen extends StatefulWidget {
  const ListScreen({Key? key}) : super(key: key);

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  bool? _lastKnownOfflineState;
  int _currentTabIndex = 0; // 0: List, 1: Map
  List<Engagement> _allEngagements = [];
  List<Institution> _allInstitutions = [];
  List<Engagement> _filteredEngagements = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedSalesRep;
  String? _selectedStatus;
  String? _selectedCompany;

  // Sub tab for COREnergy: 0: Engagements, 1: COREnergy Engage
  int _corenergySubTab = 1;
  List<COREnergyEngage> _allEngageLogs = [];
  List<COREnergyEngage> _filteredEngageLogs = [];

  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // COREnergy Engage filters
  String? _selectedRegion;
  String? _selectedProvince;
  String? _selectedCity;
  String? _selectedInstitution; // Institution filter for COREnergy Engage tab

  List<String> _salesReps = [];
  List<PsgcLocation> _allPsgcLocations = [];

  // Sorting state variables
  String _selectedSortOption = 'Last Updated On';
  bool _sortAscending = false;

  // Pagination state variables
  int _currentPage = 1;
  static const int _pageSize = 20;

  final MapController _mapController = MapController();
  LatLng? _myLocation;
  bool _isLocatingMap = false;
  bool _areFiltersExpanded = false;

  Future<void> _moveToCurrentLocation() async {
    setState(() {
      _isLocatingMap = true;
    });
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever || permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission is denied in iPad Settings.'),
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
          _isLocatingMap = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final target = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _myLocation = target;
      });
      _mapController.move(target, 14.0);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to determine location: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLocatingMap = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final apiService = Provider.of<ApiService>(context, listen: false);
    _selectedSalesRep = apiService.loggedInEmail;
    _loadData();
  }
  
  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      await apiService.checkOnlineStatus();
      if (!apiService.isOffline) {
        await apiService.syncOfflineData();
      }
      final results = await Future.wait([
        apiService.fetchEngagements(),
        apiService.fetchInstitutions(),
        apiService.fetchCOREnergyEngages(),
        apiService.fetchPsgcLocations(),
      ]);
      final engagements = results[0] as List<Engagement>;
      final institutions = results[1] as List<Institution>;
      final COREnergyEngages = results[2] as List<COREnergyEngage>;
      final psgcLocations = results[3] as List<PsgcLocation>;
      
      setState(() {
        _allEngagements = engagements;
        _allInstitutions = institutions;
        _allEngageLogs = COREnergyEngages;
        _allPsgcLocations = psgcLocations;
        
        // Extract unique sales reps
        final reps = engagements
            .map((e) => e.salesRep)
            .where((rep) => rep != null && rep.isNotEmpty)
            .map((rep) => rep!)
            .toSet()
            .toList();
        
        // Ensure default logins are in the filter list
        for (var defaultRep in [
          'jptan@profinsights.biz',
          'mmperalta@pims-marketing.com',
          'kmtaotao@pims-marketing.com'
        ]) {
          if (!reps.contains(defaultRep)) {
            reps.add(defaultRep);
          }
        }
        _salesReps = reps;
        
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading ERPNext data: $e')),
      );
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredEngagements = _allEngagements.where((item) {
        final nameMatches = item.name?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false;
        final companyMatches = item.company?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false;
        final contactMatches = item.contact?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false;
        final lastNameMatches = item.lastName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false;
        
        final matchesSearch = nameMatches || companyMatches || contactMatches || lastNameMatches;
        
        final matchesRep = _selectedSalesRep == null || item.salesRep == _selectedSalesRep;
        
        final isUnsuccessful = item.unsuccessfulCall;
        final matchesStatus = _selectedStatus == null ||
            (_selectedStatus == 'unsuccessful' && isUnsuccessful) ||
            (_selectedStatus == 'successful' && !isUnsuccessful);

        final matchesCompanyFilter = _selectedCompany == null || item.company == _selectedCompany;

        return matchesSearch && matchesRep && matchesStatus && matchesCompanyFilter;
      }).toList();

      _filteredEngageLogs = _allEngageLogs.where((item) {
        // Search matches ID, hospital/clinic name, AND resolved institution name
        final query = _searchQuery.toLowerCase();
        final resolvedInstName = _resolveInstitutionName(item).toLowerCase();
        final resolvedRegion = _resolveLocationLabel(item.region).toLowerCase();
        final matchesSearch = query.isEmpty ||
            item.name.toLowerCase().contains(query) ||
            (item.hospitalClinic?.toLowerCase().contains(query) ?? false) ||
            resolvedInstName.contains(query) ||
            resolvedRegion.contains(query);

        // Institution filter matches by institution_name field (the ID code)
        final matchesInstitution = _selectedInstitution == null || item.institutionName == _selectedInstitution;
            
        final matchesRegion = _selectedRegion == null || item.region == _selectedRegion;
        final matchesProvince = _selectedProvince == null || item.province == _selectedProvince;
        final matchesCity = _selectedCity == null || item.cityMunicipality == _selectedCity;

        return matchesSearch && matchesInstitution && matchesRegion && matchesProvince && matchesCity;
      }).toList();

      _currentPage = 1;
      _sortCollections();
    });
  }

  /// Resolve a PSGC code (e.g. "REG-01") to a display label like "REG-01 - NCR"
  String _resolveLocationLabel(String? code) {
    if (code == null || code.isEmpty) return '-';
    final match = _allPsgcLocations.firstWhere(
      (loc) => loc.name == code,
      orElse: () => PsgcLocation(name: code, locationLabel: '', locationType: ''),
    );
    if (match.locationLabel.isNotEmpty) {
      return '${match.name} - ${match.locationLabel}';
    }
    final fallbackName = _resolveHardcodedLocationName(code);
    if (fallbackName.isNotEmpty) {
      return '$code - $fallbackName';
    }
    return code;
  }

  /// Resolve a PSGC code to just the location label (no code prefix)
  String _resolveLocationLabelOnly(String? code) {
    if (code == null || code.isEmpty) return '';
    final match = _allPsgcLocations.firstWhere(
      (loc) => loc.name == code,
      orElse: () => PsgcLocation(name: code, locationLabel: '', locationType: ''),
    );
    if (match.locationLabel.isNotEmpty) {
      return match.locationLabel;
    }
    final fallbackName = _resolveHardcodedLocationName(code);
    if (fallbackName.isNotEmpty) {
      return fallbackName;
    }
    return code;
  }

  String _resolveHardcodedLocationName(String code) {
    final r = _regionsList.firstWhere((e) => e.code == code || e.name == code, orElse: () => GeographicUnit('', ''));
    if (r.name.isNotEmpty) return r.name;
    final p = _provincesList.firstWhere((e) => e.code == code || e.name == code, orElse: () => GeographicUnit('', ''));
    if (p.name.isNotEmpty) return p.name;
    final c = _citiesList.firstWhere((e) => e.code == code || e.name == code, orElse: () => GeographicUnit('', ''));
    if (c.name.isNotEmpty) return c.name;
    return '';
  }

  String _resolveInstitutionName(COREnergyEngage item) {
    final match = _allInstitutions.firstWhere(
      (i) => i.name == item.institutionName || i.name == item.name,
      orElse: () => Institution(name: item.name, institutionName: item.hospitalClinic ?? item.institutionName ?? ''),
    );
    return match.institutionName;
  }

  void _sortCollections() {
    // Sort COREnergyEngages (_filteredEngageLogs)
    _filteredEngageLogs.sort((a, b) {
      int cmp = 0;
      switch (_selectedSortOption) {
        case 'Last Updated On':
          final modifiedA = a.modified ?? a.creation ?? '';
          final modifiedB = b.modified ?? b.creation ?? '';
          cmp = modifiedA.compareTo(modifiedB);
          break;
        case 'Institution Name':
          final nameA = _resolveInstitutionName(a);
          final nameB = _resolveInstitutionName(b);
          cmp = nameA.compareTo(nameB);
          break;
        case 'ID':
          cmp = a.name.compareTo(b.name);
          break;
        case 'Created On':
          final creationA = a.creation ?? '';
          final creationB = b.creation ?? '';
          cmp = creationA.compareTo(creationB);
          break;
        case 'Most Used':
          cmp = a.visits.length.compareTo(b.visits.length);
          break;
        case 'Region':
          final regA = _resolveLocationLabelOnly(a.region);
          final regB = _resolveLocationLabelOnly(b.region);
          cmp = regA.compareTo(regB);
          break;
        case 'Province':
          final provA = _resolveLocationLabelOnly(a.province);
          final provB = _resolveLocationLabelOnly(b.province);
          cmp = provA.compareTo(provB);
          break;
        case 'City/Municipality':
          final cityA = _resolveLocationLabelOnly(a.cityMunicipality);
          final cityB = _resolveLocationLabelOnly(b.cityMunicipality);
          cmp = cityA.compareTo(cityB);
          break;
      }
      if (cmp == 0) {
        // Fallback secondary sort: ID (name) in ascending order to match database clustered index scan
        return a.name.compareTo(b.name);
      }
      return _sortAscending ? cmp : -cmp;
    });

    // Sort Engagements (_filteredEngagements)
    _filteredEngagements.sort((a, b) {
      int cmp = 0;
      switch (_selectedSortOption) {
        case 'Last Updated On':
          final modifiedA = a.modified ?? a.creation ?? '';
          final modifiedB = b.modified ?? b.creation ?? '';
          cmp = modifiedA.compareTo(modifiedB);
          break;
        case 'Institution Name':
          final matchA = _allInstitutions.firstWhere((i) => i.name == a.company, orElse: () => Institution(name: '', institutionName: ''));
          final matchB = _allInstitutions.firstWhere((i) => i.name == b.company, orElse: () => Institution(name: '', institutionName: ''));
          cmp = matchA.institutionName.compareTo(matchB.institutionName);
          break;
        case 'ID':
          cmp = (a.name ?? '').compareTo(b.name ?? '');
          break;
        case 'Created On':
          final creationA = a.creation ?? '';
          final creationB = b.creation ?? '';
          cmp = creationA.compareTo(creationB);
          break;
        case 'Most Used':
          cmp = 0;
          break;
        case 'Region':
          final matchA = _allInstitutions.firstWhere((i) => i.name == a.company, orElse: () => Institution(name: '', institutionName: ''));
          final matchB = _allInstitutions.firstWhere((i) => i.name == b.company, orElse: () => Institution(name: '', institutionName: ''));
          cmp = (matchA.regionName ?? '').compareTo(matchB.regionName ?? '');
          break;
        case 'Province':
          final matchA = _allInstitutions.firstWhere((i) => i.name == a.company, orElse: () => Institution(name: '', institutionName: ''));
          final matchB = _allInstitutions.firstWhere((i) => i.name == b.company, orElse: () => Institution(name: '', institutionName: ''));
          cmp = (matchA.provinceName ?? '').compareTo(matchB.provinceName ?? '');
          break;
        case 'City/Municipality':
          final matchA = _allInstitutions.firstWhere((i) => i.name == a.company, orElse: () => Institution(name: '', institutionName: ''));
          final matchB = _allInstitutions.firstWhere((i) => i.name == b.company, orElse: () => Institution(name: '', institutionName: ''));
          cmp = (matchA.cityMunicipality ?? '').compareTo(matchB.cityMunicipality ?? '');
          break;
      }
      if (cmp == 0) {
        return (a.name ?? '').compareTo(b.name ?? '');
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  Widget _buildSortButton() {
    return PopupMenuButton<String>(
      tooltip: 'Sort Options',
      color: Colors.white,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: const Color(0xFF0056B3),
            ),
            const SizedBox(width: 4),
            Text(
              _selectedSortOption,
              style: const TextStyle(
                color: Color(0xFF1C1C1E),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      onSelected: (String option) {
        if (option == 'TOGGLE_DIRECTION') {
          setState(() {
            _sortAscending = !_sortAscending;
            _applyFilters();
          });
        } else {
          setState(() {
            _selectedSortOption = option;
            _applyFilters();
          });
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          value: 'TOGGLE_DIRECTION',
          child: Row(
            children: [
              Icon(
                _sortAscending ? Icons.arrow_downward : Icons.arrow_upward,
                size: 16,
                color: const Color(0xFF8E8E93),
              ),
              const SizedBox(width: 8),
              Text(
                _sortAscending ? 'Sort Descending' : 'Sort Ascending',
                style: const TextStyle(color: Color(0xFF1C1C1E)),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...[
          'Last Updated On',
          'Institution Name',
          'ID',
          'Created On',
          'Most Used',
          'Region',
          'Province',
          'City/Municipality',
        ].map((String option) {
          final isSelected = option == _selectedSortOption;
          return PopupMenuItem<String>(
            value: option,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  option,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF0056B3) : const Color(0xFF1C1C1E),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check, size: 16, color: Color(0xFF0056B3)),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  void _clearFilters() {
    setState(() {
      if (_corenergySubTab == 0) {
        _selectedCompany = null;
        _selectedSalesRep = null;
        _selectedStatus = null;
      } else {
        _selectedInstitution = null;
        _selectedRegion = null;
        _selectedProvince = null;
        _selectedCity = null;
      }
      _applyFilters();
    });
  }

  Widget _buildFilterToggleButton() {
    final bool hasActiveFilters = _corenergySubTab == 0
        ? (_selectedCompany != null || _selectedSalesRep != null || _selectedStatus != null)
        : (_selectedInstitution != null || _selectedRegion != null || _selectedProvince != null || _selectedCity != null);

    return InkWell(
      onTap: () {
        setState(() {
          _areFiltersExpanded = !_areFiltersExpanded;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F6F9),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _areFiltersExpanded ? const Color(0xFF0056B3) : const Color(0xFFE5E5EA)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _areFiltersExpanded ? Icons.tune : Icons.filter_alt_outlined,
                  size: 14,
                  color: _areFiltersExpanded || hasActiveFilters ? const Color(0xFF0056B3) : const Color(0xFF8E8E93),
                ),
                const SizedBox(width: 4),
                Text(
                  _areFiltersExpanded ? 'Hide' : 'Filter',
                  style: TextStyle(
                    color: _areFiltersExpanded || hasActiveFilters ? const Color(0xFF0056B3) : const Color(0xFF1C1C1E),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (hasActiveFilters)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _getCompanyLabel(String? companyId) {
    if (companyId == null) return 'No Company';
    final match = _allInstitutions.firstWhere(
      (inst) => inst.name == companyId,
      orElse: () => Institution(name: companyId, institutionName: ''),
    );
    return match.institutionName.isNotEmpty 
        ? match.institutionName 
        : companyId;
  }

  @override
  Widget build(BuildContext context) {
    final apiService = Provider.of<ApiService>(context);

    // Auto connection change notification snacker
    if (_lastKnownOfflineState != null && _lastKnownOfflineState != apiService.isOffline) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Current Mode: ${apiService.isOffline ? "Offline Mode" : "Online Mode"}'),
              backgroundColor: apiService.isOffline ? const Color(0xFFFF9500) : const Color(0xFF34C759),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
    _lastKnownOfflineState = apiService.isOffline;

    // Automatic sync notification snacker
    if (apiService.syncMessage != null) {
      final msg = apiService.syncMessage!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: msg.toLowerCase().contains('failed')
                  ? const Color(0xFFFF3B30)
                  : const Color(0xFF30D158),
              duration: const Duration(seconds: 4),
            ),
          );
          apiService.clearSyncMessage();
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      drawer: AppConfig.mode == AppMode.corenergy ? _buildDrawer(context) : null,
      appBar: AppBar(
        title: Row(
          children: [
            Text(_currentTabIndex == 0 ? 'COREnergy Engage Copy' : 'Coverage Map'),
            if (apiService.isOffline) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9500),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'OFFLINE',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ],
        ),
        backgroundColor: const Color(0xFF0056B3),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0056B3)),
                  ),
                )
              : _currentTabIndex == 0
                  ? _buildListView()
                  : _buildMapView(),
          if (apiService.isSyncing)
            Container(
              color: Colors.black45,
              child: Center(
                child: Card(
                  color: Colors.white,
                  margin: const EdgeInsets.symmetric(horizontal: 32),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0056B3)),
                        ),
                        SizedBox(width: 16),
                        Text(
                          'Syncing offline data...',
                          style: TextStyle(
                            color: Color(0xFF1C1C1E),
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _currentTabIndex == 0
          ? FloatingActionButton(
              backgroundColor: const Color(0xFF0056B3),
              child: const Icon(Icons.add, color: Colors.white),
              onPressed: () async {
                if (_corenergySubTab == 1) {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => COREnergyEngageDetailScreen(
                        institutions: _allInstitutions,
                        salesReps: _salesReps,
                        psgcLocations: _allPsgcLocations,
                      ),
                    ),
                  );
                  if (result == true) {
                    _loadData();
                  }
                } else {
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DetailScreen(
                        institutions: _allInstitutions,
                        salesReps: _salesReps,
                      ),
                    ),
                  );
                  if (result == true) {
                    _loadData();
                  }
                }
              },
            )
          : null,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTabIndex,
        onTap: (index) {
          setState(() {
            _currentTabIndex = index;
          });
        },
        backgroundColor: Colors.white,
        selectedItemColor: const Color(0xFF0056B3),
        unselectedItemColor: const Color(0xFF8E8E93),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'List',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            label: 'Map',
          ),
        ],
      ),
    );
  }

  Widget _buildListView() {
    return Column(
      children: [
        // Sub-Tab Switcher
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: Colors.white,
          child: Container(
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _corenergySubTab = 0;
                        _applyFilters();
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _corenergySubTab == 0 ? const Color(0xFF0056B3) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Engagements',
                        style: TextStyle(
                          color: _corenergySubTab == 0 ? Colors.white : const Color(0xFF8E8E93),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _corenergySubTab = 1;
                        _applyFilters();
                      });
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _corenergySubTab == 1 ? const Color(0xFF0056B3) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'COREnergy Engage Copy',
                        style: TextStyle(
                          color: _corenergySubTab == 1 ? Colors.white : const Color(0xFF8E8E93),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Search & Filters Header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Color(0xFFE5E5EA))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) {
                        _searchQuery = val;
                        _debounce?.cancel();
                        _debounce = Timer(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            _applyFilters();
                          }
                        });
                      },
                      style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search by ID or Location...',
                        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Color(0xFF8E8E93), size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchQuery = '';
                                    _applyFilters();
                                  });
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: const Color(0xFFF4F6F9),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildSortButton(),
                  const SizedBox(width: 8),
                  _buildFilterToggleButton(),
                ],
              ),
              if (_areFiltersExpanded) ...[
                const SizedBox(height: 10),
                if (_corenergySubTab == 0) ...[
                  // Show clear filters button if there are active filters on Tab 0
                  if (_selectedCompany != null || _selectedSalesRep != null || _selectedStatus != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear_all, size: 16, color: Color(0xFFFF3B30)),
                          label: const Text('Clear All Filters', style: TextStyle(color: Color(0xFFFF3B30), fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Row 1: Company Search Selector
                  GestureDetector(
                    onTap: _showCompanyFilterPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedCompany == null
                                  ? 'All Companies'
                                  : (() {
                                      final match = _allInstitutions.firstWhere(
                                        (i) => i.name == _selectedCompany,
                                        orElse: () => Institution(name: _selectedCompany!, institutionName: _selectedCompany!),
                                      );
                                      return '${match.name} - ${match.institutionName}';
                                    })(),
                              style: TextStyle(
                                color: _selectedCompany == null ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedCompany != null)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCompany = null;
                                  _applyFilters();
                                });
                              },
                              child: const Icon(Icons.clear, size: 16, color: Color(0xFF8E8E93)),
                            )
                          else
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93), size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Row 2: Sales Rep & Status
                  Row(
                    children: [
                      // Sales Rep Dropdown
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedSalesRep,
                              hint: const Text('All Reps', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 13),
                              onChanged: (val) {
                                setState(() {
                                  _selectedSalesRep = val;
                                  _applyFilters();
                                });
                              },
                              items: [
                                const DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Reps', style: TextStyle(color: Color(0xFF1C1C1E))),
                                ),
                                ..._salesReps.map((rep) {
                                  return DropdownMenuItem<String>(
                                    value: rep,
                                    child: Text(
                                      rep,
                                      style: const TextStyle(color: Color(0xFF1C1C1E)),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Status Dropdown
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F6F9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedStatus,
                              hint: const Text('All Status', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                              dropdownColor: Colors.white,
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 13),
                              onChanged: (val) {
                                setState(() {
                                  _selectedStatus = val;
                                  _applyFilters();
                                });
                              },
                              items: const [
                                DropdownMenuItem<String>(
                                  value: null,
                                  child: Text('All Status', style: TextStyle(color: Color(0xFF1C1C1E))),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'successful',
                                  child: Text('Successful', style: TextStyle(color: Color(0xFF1C1C1E))),
                                ),
                                DropdownMenuItem<String>(
                                  value: 'unsuccessful',
                                  child: Text('Unsuccessful', style: TextStyle(color: Color(0xFF1C1C1E))),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  // Show clear filters button if there are active filters on Tab 1
                  if (_selectedInstitution != null || _selectedRegion != null || _selectedProvince != null || _selectedCity != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: _clearFilters,
                          icon: const Icon(Icons.clear_all, size: 16, color: Color(0xFFFF3B30)),
                          label: const Text('Clear All Filters', style: TextStyle(color: Color(0xFFFF3B30), fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Row 0: Institution Filter (searchable bottom sheet)
                  GestureDetector(
                    onTap: _showInstitutionFilterPicker,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedInstitution == null
                                  ? 'All Institutions'
                                  : (() {
                                      final match = _allInstitutions.firstWhere(
                                        (i) => i.name == _selectedInstitution,
                                        orElse: () => Institution(name: _selectedInstitution!, institutionName: _selectedInstitution!),
                                      );
                                      return '${match.institutionName} (${match.name})';
                                    })(),
                              style: TextStyle(
                                color: _selectedInstitution == null ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedInstitution != null)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedInstitution = null;
                                  _applyFilters();
                                });
                              },
                              child: const Icon(Icons.clear, size: 16, color: Color(0xFF8E8E93)),
                            )
                          else
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93), size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Row 1: Region & Province (searchable tappable pickers)
                  Row(
                    children: [
                      // Region Picker
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showSearchableLocationPicker(
                            title: 'Filter by Region',
                            locationType: 'Region',
                            selectedValue: _selectedRegion,
                            onSelected: (code) {
                              setState(() {
                                _selectedRegion = code;
                                _applyFilters();
                              });
                            },
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F6F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedRegion == null ? 'All Regions' : _resolveLocationLabel(_selectedRegion),
                                    style: TextStyle(
                                      color: _selectedRegion == null ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_selectedRegion != null)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedRegion = null;
                                        _applyFilters();
                                      });
                                    },
                                    child: const Icon(Icons.clear, size: 14, color: Color(0xFF8E8E93)),
                                  )
                                else
                                  const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93), size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Province Picker
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showSearchableLocationPicker(
                            title: 'Filter by Province',
                            locationType: 'Province',
                            selectedValue: _selectedProvince,
                            onSelected: (code) {
                              setState(() {
                                _selectedProvince = code;
                                _applyFilters();
                              });
                            },
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F6F9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedProvince == null ? 'All Provinces' : _resolveLocationLabel(_selectedProvince),
                                    style: TextStyle(
                                      color: _selectedProvince == null ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                                      fontSize: 12,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (_selectedProvince != null)
                                  GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _selectedProvince = null;
                                        _applyFilters();
                                      });
                                    },
                                    child: const Icon(Icons.clear, size: 14, color: Color(0xFF8E8E93)),
                                  )
                                else
                                  const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93), size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Row 2: City/Municipality Picker
                  GestureDetector(
                    onTap: () => _showSearchableLocationPicker(
                      title: 'Filter by City/Municipality',
                      locationType: 'City',
                      selectedValue: _selectedCity,
                      onSelected: (code) {
                        setState(() {
                          _selectedCity = code;
                          _applyFilters();
                        });
                      },
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F6F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedCity == null ? 'All Cities' : _resolveLocationLabel(_selectedCity),
                              style: TextStyle(
                                color: _selectedCity == null ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_selectedCity != null)
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCity = null;
                                  _applyFilters();
                                });
                              },
                              child: const Icon(Icons.clear, size: 14, color: Color(0xFF8E8E93)),
                            )
                          else
                            const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        // Listing Cards Area
        Expanded(
          child: _corenergySubTab == 0
              ? (_filteredEngagements.isEmpty
                  ? const Center(
                      child: Text('No profiling logs found.', style: TextStyle(color: Color(0xFF8E8E93))),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: _paginatedEngagements.length,
                              itemBuilder: (context, index) {
                                final item = _paginatedEngagements[index];
                                final companyName = _getCompanyLabel(item.company);
                                final isUnsuccessful = item.unsuccessfulCall;

                                return Card(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: const BorderSide(color: Color(0xFFE5E5EA)),
                                  ),
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () async {
                                      final result = await Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => DetailScreen(
                                              engagement: item,
                                              institutions: _allInstitutions,
                                              salesReps: _salesReps,
                                            ),
                                          ),
                                      );
                                      if (result == true) {
                                        _loadData();
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.name ?? 'NEW',
                                                  style: const TextStyle(
                                                    color: Color(0xFF1C1C1E),
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isUnsuccessful
                                                      ? const Color(0xFFFF453A).withOpacity(0.15)
                                                      : const Color(0xFF30D158).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  isUnsuccessful ? 'Unsuccessful' : 'Successful',
                                                  style: TextStyle(
                                                    color: isUnsuccessful 
                                                        ? const Color(0xFFFF453A) 
                                                        : const Color(0xFF30D158),
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              const Icon(Icons.business, color: Color(0xFF8E8E93), size: 16),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  companyName,
                                                  style: const TextStyle(color: Color(0xFF636366), fontSize: 13),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Icon(Icons.person, color: Color(0xFF8E8E93), size: 16),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  item.salesRep ?? 'No Sales Rep',
                                                  style: const TextStyle(color: Color(0xFF636366), fontSize: 13),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        _buildPaginationControls(_totalEngagements),
                      ],
                    ))
              : (_filteredEngageLogs.isEmpty
                  ? const Center(
                      child: Text('No COREnergy Engage Copy logs found.', style: TextStyle(color: Color(0xFF8E8E93))),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _loadData,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(12),
                              itemCount: _paginatedEngageLogs.length,
                              itemBuilder: (context, index) {
                                final item = _paginatedEngageLogs[index];

                                return Card(
                                  color: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: const BorderSide(color: Color(0xFFE5E5EA)),
                                  ),
                                  elevation: 0,
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () async {
                                      final result = await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => COREnergyEngageDetailScreen(
                                            engage: item,
                                            institutions: _allInstitutions,
                                            salesReps: _salesReps,
                                            psgcLocations: _allPsgcLocations,
                                          ),
                                        ),
                                      );
                                      if (result == true) {
                                        _loadData();
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(16.0),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Resolved Institution Name
                                           Text(
                                             (() {
                                               final match = _allInstitutions.firstWhere(
                                                 (i) => i.name == item.institutionName || i.name == item.name,
                                                 orElse: () => Institution(
                                                   name: item.name,
                                                   institutionName: item.hospitalClinic ?? item.institutionName ?? 'Unknown Institution',
                                                 ),
                                               );
                                               final instName = (match.institutionName.isNotEmpty && match.institutionName != match.name)
                                                   ? match.institutionName
                                                   : (item.hospitalClinic ?? item.institutionName ?? match.name);
                                               final instCode = (match.name.isNotEmpty && match.name.startsWith('INST-'))
                                                   ? match.name
                                                   : (item.name.startsWith('INST-') ? item.name : '');

                                               if (instName.isNotEmpty && instCode.isNotEmpty && instName != instCode) {
                                                 if (instName.contains(instCode)) {
                                                   return instName;
                                                 } else {
                                                   return '$instName - $instCode';
                                                 }
                                               }
                                               return instName.isNotEmpty ? instName : match.name;
                                             })(),
                                            style: const TextStyle(
                                              color: Color(0xFF1C1C1E),
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(height: 1, color: Color(0xFFE5E5EA)),
                                          const SizedBox(height: 12),
                                          
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('REGION', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      (item.region == null || item.region!.trim().isEmpty) ? '-' : _resolveLocationLabelOnly(item.region),
                                                      style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 12),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('PROVINCE', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      (item.province == null || item.province!.trim().isEmpty) ? '-' : _resolveLocationLabelOnly(item.province),
                                                      style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 12),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    const Text('CITY/MUNICIPALITY', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      (item.cityMunicipality == null || item.cityMunicipality!.trim().isEmpty) ? '-' : _resolveLocationLabelOnly(item.cityMunicipality),
                                                      style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 12),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  const Text('ID', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 10, fontWeight: FontWeight.bold)),
                                                  const SizedBox(height: 4),
                                                  Text(item.name, style: const TextStyle(color: Color(0xFF0056B3), fontSize: 12, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              const Icon(Icons.person, color: Color(0xFF8E8E93), size: 14),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Sales Rep: ${item.salesRep ?? "No Sales Rep"}',
                                                style: const TextStyle(color: Color(0xFF636366), fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        _buildPaginationControls(_totalEngageLogs),
                      ],
                    )),
        ),
      ],
    );
  }

  Widget _buildMapView() {
    // Collect coordinates from engagements
    final points = <Marker>[];
    double latSum = 0;
    double lngSum = 0;
    int count = 0;

    for (var item in _filteredEngagements) {
      if (item.latitude != null && item.longitude != null) {
        final lat = double.tryParse(item.latitude!);
        final lng = double.tryParse(item.longitude!);
        if (lat != null && lng != null) {
          latSum += lat;
          lngSum += lng;
          count++;

          final isUnsuccessful = item.unsuccessfulCall;

          points.add(
            Marker(
              width: 40.0,
              height: 40.0,
              point: LatLng(lat, lng),
              child: GestureDetector(
                onTap: () {
                  _showMapPinDetails(item);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: isUnsuccessful ? const Color(0xFFFF453A) : const Color(0xFF0056B3),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }
      }
    }

    final center = count > 0 
        ? LatLng(latSum / count, lngSum / count) 
        : LatLng(14.3129, 121.1009); // Default to Canossa

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: 11.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
            ),
            MarkerLayer(
              markers: [
                ...points,
                if (_myLocation != null)
                  Marker(
                    width: 50.0,
                    height: 50.0,
                    point: _myLocation!,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        // Zoom controls on the right side
        Positioned(
          right: 16,
          bottom: 100,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'zoom_in',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0056B3),
                child: const Icon(Icons.add),
                onPressed: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1);
                },
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'zoom_out',
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF0056B3),
                child: const Icon(Icons.remove),
                onPressed: () {
                  _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1);
                },
              ),
            ],
          ),
        ),
        // Go to current location FAB
        Positioned(
          right: 16,
          bottom: 30,
          child: FloatingActionButton(
            heroTag: 'my_location',
            backgroundColor: const Color(0xFF0056B3),
            foregroundColor: Colors.white,
            onPressed: _moveToCurrentLocation,
            child: _isLocatingMap
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }

  void _showMapPinDetails(Engagement item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final companyName = _getCompanyLabel(item.company);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.name ?? '',
                      style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: item.unsuccessfulCall
                            ? const Color(0xFFFF453A).withOpacity(0.15)
                            : const Color(0xFF30D158).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.unsuccessfulCall ? 'Unsuccessful' : 'Successful',
                        style: TextStyle(
                          color: item.unsuccessfulCall 
                              ? const Color(0xFFFF453A) 
                              : const Color(0xFF30D158),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Institution: $companyName', style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14)),
                const SizedBox(height: 6),
                Text('Sales Rep: ${item.salesRep ?? ''}', style: const TextStyle(color: Color(0xFF636366), fontSize: 14)),
                if (item.latitude != null && item.longitude != null) ...[
                  const SizedBox(height: 6),
                  Text('Coords: ${item.latitude}, ${item.longitude}', style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 12)),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop(); // dismiss sheet
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DetailScreen(
                          engagement: item,
                          institutions: _allInstitutions,
                          salesReps: _salesReps,
                        ),
                      ),
                    ).then((value) {
                      if (value == true) {
                        _loadData();
                      }
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0056B3),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('View Profiling Details', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header with medical background and Caduceus motif
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
                    'PIMS MCP (COREnergy)',
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

            // Navigation Items
            ListTile(
              leading: const Icon(Icons.assignment, color: Color(0xFF0056B3)),
              title: const Text('Engagements List', style: TextStyle(color: Color(0xFF0056B3), fontWeight: FontWeight.bold)),
              selected: true,
              selectedTileColor: const Color(0xFF0056B3).withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onTap: () => Navigator.pop(context),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Text(
                'MCP Version 1.5',
                style: TextStyle(
                  color: const Color(0xFF8E8E93),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
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
    );
  }

  void _showCompanyFilterPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return _SearchableCompanyFilterPicker(
          institutions: _allInstitutions,
          onSelected: (inst) {
            setState(() {
              _selectedCompany = inst.name;
              _applyFilters();
            });
          },
        );
      },
    );
  }

  int get _totalEngagements => _filteredEngagements.length;
  List<Engagement> get _paginatedEngagements {
    final start = (_currentPage - 1) * _pageSize;
    if (start >= _totalEngagements) return [];
    final end = (start + _pageSize) > _totalEngagements ? _totalEngagements : (start + _pageSize);
    return _filteredEngagements.sublist(start, end);
  }

  int get _totalEngageLogs => _filteredEngageLogs.length;
  List<COREnergyEngage> get _paginatedEngageLogs {
    final start = (_currentPage - 1) * _pageSize;
    if (start >= _totalEngageLogs) return [];
    final end = (start + _pageSize) > _totalEngageLogs ? _totalEngageLogs : (start + _pageSize);
    return _filteredEngageLogs.sublist(start, end);
  }

  Widget _buildPaginationControls(int totalItems) {
    if (totalItems == 0) return const SizedBox.shrink();
    
    final totalPages = (totalItems / _pageSize).ceil();
    final startItem = (_currentPage - 1) * _pageSize + 1;
    final endItem = (_currentPage * _pageSize) > totalItems ? totalItems : (_currentPage * _pageSize);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E5EA))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF0056B3)),
            onPressed: _currentPage > 1
                ? () {
                    setState(() {
                      _currentPage--;
                    });
                  }
                : null,
          ),
          const SizedBox(width: 8),
          Text(
            '$startItem - $endItem of $totalItems',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1C1C1E),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF0056B3)),
            onPressed: _currentPage < totalPages
                ? () {
                    setState(() {
                      _currentPage++;
                    });
                  }
                : null,
          ),
        ],
      ),
    );
  }



  void _showInstitutionFilterPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return _SearchableCompanyFilterPicker(
          institutions: _allInstitutions,
          onSelected: (inst) {
            setState(() {
              _selectedInstitution = inst.name;
              _applyFilters();
            });
          },
        );
      },
    );
  }

  void _showSearchableLocationPicker({
    required String title,
    required String locationType,
    required String? selectedValue,
    required Function(String?) onSelected,
  }) {
    List<MapEntry<String, String>> entries = [];

    // Filter master list of PSGC locations by type and selected parent
    if (_allPsgcLocations.isNotEmpty) {
      final filteredLocs = _allPsgcLocations.where((loc) {
        if (locationType == 'Region') {
          return loc.locationType == 'Region';
        } else if (locationType == 'Province') {
          final matchesType = loc.locationType == 'Province';
          final matchesParent = _selectedRegion == null || 
              loc.parentPsgcLocation == _selectedRegion ||
              (loc.parentPsgcLocation != null && _selectedRegion != null && 
               loc.parentPsgcLocation!.substring(0, 2) == _selectedRegion!.substring(0, 2));
          return matchesType && matchesParent;
        } else {
          // City/Municipality
          final matchesType = loc.locationType == 'City' || loc.locationType == 'City/Municipality';
          final matchesParent = _selectedProvince == null || 
              loc.parentPsgcLocation == _selectedProvince ||
              (loc.parentPsgcLocation != null && _selectedProvince != null && 
               loc.parentPsgcLocation!.substring(0, 4) == _selectedProvince!.substring(0, 4));
          return matchesType && matchesParent;
        }
      });
      entries = filteredLocs.map((loc) => MapEntry(loc.name, '${loc.name} - ${loc.locationLabel}')).toList();
    }

    // Add fallback list items if not already present in the entries
    if (locationType == 'Region') {
      for (final r in _regionsList) {
        if (!entries.any((e) => e.key == r.code)) {
          entries.add(MapEntry(r.code, '${r.code} - ${r.name}'));
        }
      }
    } else if (locationType == 'Province') {
      for (final p in _provincesList) {
        if (_selectedRegion != null) {
          final regPrefix = _selectedRegion!.substring(0, 2);
          final provPrefix = p.code.substring(0, 2);
          if (provPrefix != regPrefix) continue;
        }
        if (!entries.any((e) => e.key == p.code)) {
          entries.add(MapEntry(p.code, '${p.code} - ${p.name}'));
        }
      }
    } else {
      for (final c in _citiesList) {
        if (_selectedProvince != null) {
          final provPrefix = _selectedProvince!.substring(0, 4);
          final cityPrefix = c.code.substring(0, 4);
          if (cityPrefix != provPrefix) continue;
        }
        if (!entries.any((e) => e.key == c.code)) {
          entries.add(MapEntry(c.code, '${c.code} - ${c.name}'));
        }
      }
    }

    entries.sort((a, b) => a.value.compareTo(b.value));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return _SearchableLocationPicker(
          title: title,
          entries: entries,
          selectedValue: selectedValue,
          onSelected: (code) {
            onSelected(code);
          },
        );
      },
    );
  }
}

class _SearchableCompanyFilterPicker extends StatefulWidget {
  final List<Institution> institutions;
  final Function(Institution) onSelected;

  const _SearchableCompanyFilterPicker({
    Key? key,
    required this.institutions,
    required this.onSelected,
  }) : super(key: key);

  @override
  State<_SearchableCompanyFilterPicker> createState() => _SearchableCompanyFilterPickerState();
}

class _SearchableCompanyFilterPickerState extends State<_SearchableCompanyFilterPicker> {
  List<Institution> _filteredList = [];

  @override
  void initState() {
    super.initState();
    _filteredList = widget.institutions;
  }

  void _filter(String query) {
    setState(() {
      _filteredList = widget.institutions.where((inst) {
        final matchesName = inst.institutionName.toLowerCase().contains(query.toLowerCase());
        final matchesId = inst.name.toLowerCase().contains(query.toLowerCase());
        final matchesRegion = (inst.regionName ?? '').toLowerCase().contains(query.toLowerCase());
        return matchesName || matchesId || matchesRegion;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Filter by Institution',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: _filter,
            style: const TextStyle(color: Color(0xFF1C1C1E)),
            decoration: InputDecoration(
              hintText: 'Search by ID or Name...',
              hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
              filled: true,
              fillColor: const Color(0xFFF4F6F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filteredList.isEmpty
                ? const Center(child: Text('No matching institutions found.', style: TextStyle(color: Color(0xFF8E8E93))))
                : ListView.builder(
                    itemCount: _filteredList.length,
                    itemBuilder: (context, idx) {
                      final item = _filteredList[idx];
                      return ListTile(
                        title: Text(item.institutionName, style: const TextStyle(color: Color(0xFF1C1C1E), fontWeight: FontWeight.w600)),
                        subtitle: Text(item.name, style: const TextStyle(color: Color(0xFF8E8E93), fontFamily: 'monospace')),
                        onTap: () {
                          widget.onSelected(item);
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

class _SearchableLocationPicker extends StatefulWidget {
  final String title;
  final List<MapEntry<String, String>> entries; // code -> displayLabel
  final String? selectedValue;
  final Function(String?) onSelected;

  const _SearchableLocationPicker({
    Key? key,
    required this.title,
    required this.entries,
    required this.selectedValue,
    required this.onSelected,
  }) : super(key: key);

  @override
  State<_SearchableLocationPicker> createState() => _SearchableLocationPickerState();
}

class _SearchableLocationPickerState extends State<_SearchableLocationPicker> {
  List<MapEntry<String, String>> _filteredList = [];

  @override
  void initState() {
    super.initState();
    _filteredList = widget.entries;
  }

  void _filter(String query) {
    setState(() {
      _filteredList = widget.entries.where((entry) {
        return entry.key.toLowerCase().contains(query.toLowerCase()) ||
            entry.value.toLowerCase().contains(query.toLowerCase());
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          Text(
            widget.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: _filter,
            style: const TextStyle(color: Color(0xFF1C1C1E)),
            decoration: InputDecoration(
              hintText: 'Search by code or name...',
              hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF8E8E93)),
              filled: true,
              fillColor: const Color(0xFFF4F6F9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _filteredList.isEmpty
                ? const Center(child: Text('No matching locations found.', style: TextStyle(color: Color(0xFF8E8E93))))
                : ListView.builder(
                    itemCount: _filteredList.length,
                    itemBuilder: (context, idx) {
                      final entry = _filteredList[idx];
                      final isSelected = entry.key == widget.selectedValue;
                      return ListTile(
                        title: Text(
                          entry.value,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF0056B3) : const Color(0xFF1C1C1E),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check, color: Color(0xFF0056B3), size: 20)
                            : null,
                        onTap: () {
                          widget.onSelected(entry.key);
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
