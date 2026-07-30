import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/engagement.dart';
import '../models/hcp.dart';
import '../models/submission.dart';
import '../models/lookup_models.dart';
import '../models/hcp_account.dart';
import '../models/corenergy_engage.dart';
import 'db_helper.dart';

class ApiService extends ChangeNotifier {
  ApiService() {
    checkOnlineStatus();
    _startAutoSyncTimer();
  }

  String selectedProgram = 'COREnergy';
  List<String> availablePrograms = ['COREnergy'];

  // Offline Mode variables
  bool _isOffline = false;
  bool get isOffline => _isOffline;
  bool _isSyncing = false;
  bool get isSyncing => _isSyncing;

  Timer? _autoSyncTimer;
  String? _syncMessage;
  String? get syncMessage => _syncMessage;

  void clearSyncMessage() {
    _syncMessage = null;
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        // Always check online status to keep the UI Mode indicator accurate
        final isOnline = await checkOnlineStatus();
        if (isOnline) {
          final pending = await DbHelper.getPendingEngagements();
          if (pending.isNotEmpty) {
            await syncOfflineData();
          }
        }
      } catch (e) {
        print('Auto-sync timer error: $e');
      }
    });
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }

  Future<bool> checkOnlineStatus() async {
    try {
      final url = Uri.parse('$baseUrl/api/method/ping');
      final response = await http.get(url).timeout(const Duration(seconds: 3));
      final online = response.statusCode == 200;
      _isOffline = !online;
      notifyListeners();
      return online;
    } catch (_) {
      _isOffline = true;
      notifyListeners();
      return false;
    }
  }

  // File cache helpers
  Future<File> _getCacheFile(String filename) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$filename');
  }

  Future<void> _writeToCache(String filename, String content) async {
    try {
      final file = await _getCacheFile(filename);
      await file.writeAsString(content);
    } catch (e) {
      print('Error writing to cache $filename: $e');
    }
  }

  Future<String?> _readFromCache(String filename) async {
    try {
      final file = await _getCacheFile(filename);
      if (await file.exists()) {
        return await file.readAsString();
      }
    } catch (e) {
      print('Error reading from cache $filename: $e');
    }
    return null;
  }

  // Pending offline edits helpers (using SQLite)
  Future<List<COREnergyEngage>> _readPendingCreates() async {
    try {
      final rows = await DbHelper.getPendingEngagements();
      return rows
          .where((row) => row['action_type'] == 'CREATE')
          .map((row) => COREnergyEngage.fromJson(jsonDecode(row['data'])))
          .toList();
    } catch (e) {
      print('Error reading pending creates from SQLite: $e');
      return [];
    }
  }

  Future<void> _addPendingCreate(COREnergyEngage engage) async {
    try {
      await DbHelper.insertPendingEngagement(engage, 'CREATE');
    } catch (e) {
      print('Error saving pending create to SQLite: $e');
    }
  }

  Future<List<COREnergyEngage>> _readPendingUpdates() async {
    try {
      final rows = await DbHelper.getPendingEngagements();
      return rows
          .where((row) => row['action_type'] == 'UPDATE')
          .map((row) => COREnergyEngage.fromJson(jsonDecode(row['data'])))
          .toList();
    } catch (e) {
      print('Error reading pending updates from SQLite: $e');
      return [];
    }
  }

  Future<void> _addPendingUpdate(String name, COREnergyEngage engage) async {
    try {
      final offlineKey = engage.institutionName ?? name;
      if (offlineKey.startsWith('OFFLINE-')) {
        await DbHelper.insertPendingEngagement(engage, 'CREATE');
      } else {
        final pending = await DbHelper.getPendingEngagements();
        final match = pending.where((r) => r['temp_id'] == offlineKey && r['action_type'] == 'CREATE');
        if (match.isNotEmpty) {
          await DbHelper.insertPendingEngagement(engage, 'CREATE');
        } else {
          await DbHelper.insertPendingEngagement(engage, 'UPDATE');
        }
      }
    } catch (e) {
      print('Error saving pending update to SQLite: $e');
    }
  }

  Future<void> _saveDetailToCache(String name, COREnergyEngage engage) async {
    final cache = await _readFromCache('engage_details_cache.json');
    Map<String, dynamic> cacheMap = {};
    if (cache != null) {
      try {
        cacheMap = Map<String, dynamic>.from(jsonDecode(cache));
      } catch (_) {}
    }
    cacheMap[name] = engage.toJson();
    await _writeToCache('engage_details_cache.json', jsonEncode(cacheMap));
  }

  Future<void> syncOfflineData() async {
    if (_isSyncing) return;
    _isSyncing = true;
    notifyListeners();
    bool somethingSynced = false;
    try {
      // Clean up legacy pending institution rows without posting to Institution DocType (reserved for HCP App)
      final pendingInstRows = await DbHelper.getPendingInstitutions();
      for (var instRow in pendingInstRows) {
        await DbHelper.deletePendingInstitution(instRow['temp_id']);
      }

      final pendingRows = await DbHelper.getPendingEngagements();
      if (pendingRows.isEmpty) return;

      for (var row in pendingRows) {
        final String tempId = row['temp_id'];
        final String actionType = row['action_type'];
        final COREnergyEngage engage = COREnergyEngage.fromJson(jsonDecode(row['data']));

        try {
          if (actionType == 'CREATE') {
            final url = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy');
            final syncEngage = COREnergyEngage(
              name: engage.name,
              institutionName: engage.institutionName,
              hospitalClinic: engage.hospitalClinic,
              region: engage.region,
              province: engage.province,
              cityMunicipality: engage.cityMunicipality,
              streetAddress: engage.streetAddress,
              salesRep: engage.salesRep,
              contacts: engage.contacts,
              visits: engage.visits,
              actionItems: engage.actionItems,
            );
            final payload = syncEngage.toJson();
            payload.remove('name'); // Always remove name for CREATE requests to let server assign/determine naming
            
            final response = await http.post(
              url,
              headers: _headers,
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 10));
            
            if (response.statusCode == 200 || response.statusCode == 201) {
              final body = jsonDecode(response.body);
              final created = COREnergyEngage.fromJson(body['data']);
              await _saveDetailToCache(created.name, created);
              if (created.institutionName != null) {
                await _saveDetailToCache(created.institutionName!, created);
              }
              somethingSynced = true;
            } else if (response.statusCode == 409 || 
                       response.body.contains('already exists') || 
                       response.body.contains('DuplicateEntryError') || 
                       response.body.contains('Duplicate')) {
              // Self-healing: Convert CREATE to UPDATE if the record already exists on the server
              print('Duplicate COREnergy Engage document detected during sync for ${engage.institutionName}. Falling back to PUT update...');
              
              String? serverDocName;
              try {
                final searchUrl = Uri.parse(
                  '$baseUrl/api/resource/COREnergy%20Engage%20Copy?filters=[["institution_name","=","${engage.institutionName}"]]'
                );
                final searchResponse = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 7));
                if (searchResponse.statusCode == 200) {
                  final searchBody = jsonDecode(searchResponse.body);
                  final List<dynamic> searchData = searchBody['data'] ?? [];
                  if (searchData.isNotEmpty) {
                    serverDocName = searchData[0]['name'];
                  }
                }
              } catch (e) {
                print('Error searching for duplicate document name: $e');
              }

              final targetName = serverDocName ?? engage.name;
              final updateUrl = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy/$targetName');
              final updateResponse = await http.put(
                updateUrl,
                headers: _headers,
                body: jsonEncode(payload),
              ).timeout(const Duration(seconds: 10));
              
              if (updateResponse.statusCode == 200) {
                final body = jsonDecode(updateResponse.body);
                final updated = COREnergyEngage.fromJson(body['data']);
                await _saveDetailToCache(updated.name, updated);
                if (updated.institutionName != null) {
                  await _saveDetailToCache(updated.institutionName!, updated);
                }
                somethingSynced = true;
              } else {
                throw Exception('Sync fallback update failed: ${updateResponse.body}');
              }
            } else {
              throw Exception('Sync create failed: ${response.body}');
            }
          } else if (actionType == 'UPDATE') {
            String targetName = engage.name;
            if (targetName == engage.institutionName) {
              // It's the Institution ID, let's search if the server has a COREnergy Engage ID for this institution
              try {
                final searchUrl = Uri.parse(
                  '$baseUrl/api/resource/COREnergy%20Engage%20Copy?filters=[["institution_name","=","${engage.institutionName}"]]'
                );
                final searchResponse = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 7));
                if (searchResponse.statusCode == 200) {
                  final searchBody = jsonDecode(searchResponse.body);
                  final List<dynamic> searchData = searchBody['data'] ?? [];
                  if (searchData.isNotEmpty) {
                    targetName = searchData[0]['name'];
                  }
                }
              } catch (e) {
                print('Error resolving server name for update: $e');
              }
            }

            final url = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy/$targetName');
            final payloadMap = engage.toJson();
            payloadMap.remove('name');
            final response = await http.put(
              url,
              headers: _headers,
              body: jsonEncode(payloadMap),
            ).timeout(const Duration(seconds: 10));
            
            if (response.statusCode == 200) {
              final body = jsonDecode(response.body);
              final updated = COREnergyEngage.fromJson(body['data']);
              await _saveDetailToCache(updated.name, updated);
              if (updated.institutionName != null) {
                await _saveDetailToCache(updated.institutionName!, updated);
              }
              somethingSynced = true;
            } else if (response.statusCode == 404 || 
                       response.body.contains('DoesNotExistError') || 
                       response.body.contains('not found')) {
              print('COREnergy Engage document does not exist during sync for $targetName. Falling back to POST create...');
              final createUrl = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy');
              final createResponse = await http.post(
                createUrl,
                headers: _headers,
                body: jsonEncode(payloadMap),
              ).timeout(const Duration(seconds: 10));
              
              if (createResponse.statusCode == 200 || createResponse.statusCode == 201) {
                final body = jsonDecode(createResponse.body);
                final created = COREnergyEngage.fromJson(body['data']);
                await _saveDetailToCache(created.name, created);
                if (created.institutionName != null) {
                  await _saveDetailToCache(created.institutionName!, created);
                }
                somethingSynced = true;
              } else {
                throw Exception('Sync fallback create failed: ${createResponse.body}');
              }
            } else {
              throw Exception('Sync update failed: ${response.body}');
            }
          }
          await DbHelper.deletePendingEngagement(tempId);
          _syncMessage = 'Sync successful: "${engage.hospitalClinic ?? engage.name}" is now uploaded.';
          notifyListeners();
        } catch (e) {
          print('Sync failed for offline row $tempId: $e');
          _syncMessage = 'Sync failed for "${engage.hospitalClinic ?? engage.name}": $e';
          notifyListeners();
          break; // Stop syncing to avoid data loss
        }
      }
      
      if (somethingSynced && !_isOffline) {
        await fetchCOREnergyEngages();
      }
    } catch (e) {
      print('syncOfflineData SQLite error: $e');
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  void setProgram(String program) {
    if (selectedProgram != program) {
      selectedProgram = program;
      notifyListeners();
    }
  }

  Future<void> fetchAvailablePrograms() async {
    try {
      final accounts = await hcpAccounts.list(fields: ['account_or_program']);
      final names = accounts
          .map((a) => a.accountName)
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      if (names.isNotEmpty) {
        availablePrograms = names;
        if (!availablePrograms.contains(selectedProgram)) {
          selectedProgram = availablePrograms.first;
        }
        notifyListeners();
      }
    } catch (e) {
      print('Error fetching available programs: $e');
    }
  }
  final String baseUrl = 'https://dev.pmii-marketing.com';
  String? _sessionCookie;
  String? loggedInEmail;

  late final FrappeRepository<Hcp> hcps = FrappeRepository<Hcp>(
    api: this,
    docType: 'HCP',
    fromJson: (json) => Hcp.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<HcpAccount> hcpAccounts = FrappeRepository<HcpAccount>(
    api: this,
    docType: 'HCP Account',
    fromJson: (json) => HcpAccount.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<HcpAccountDoctors> hcpAccountDoctors = FrappeRepository<HcpAccountDoctors>(
    api: this,
    docType: 'HCP Account Doctors',
    fromJson: (json) => HcpAccountDoctors.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<HcpProfileSubmission> submissions = FrappeRepository<HcpProfileSubmission>(
    api: this,
    docType: 'HCP Profile Submission',
    fromJson: (json) => HcpProfileSubmission.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<HcpSurveyTemplate> surveyTemplates = FrappeRepository<HcpSurveyTemplate>(
    api: this,
    docType: 'HCP Survey Template',
    fromJson: (json) => HcpSurveyTemplate.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<HcpSurveyResponse> surveyResponses = FrappeRepository<HcpSurveyResponse>(
    api: this,
    docType: 'HCP Survey Response',
    fromJson: (json) => HcpSurveyResponse.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<HcpType> hcpTypes = FrappeRepository<HcpType>(
    api: this,
    docType: 'HCP Type',
    fromJson: (json) => HcpType.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<Institution> institutions = FrappeRepository<Institution>(
    api: this,
    docType: 'Institution',
    fromJson: (json) => Institution.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<Specialization> specializations = FrappeRepository<Specialization>(
    api: this,
    docType: 'Specialization',
    fromJson: (json) => Specialization.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  late final FrappeRepository<PsgcLocation> psgcLocations = FrappeRepository<PsgcLocation>(
    api: this,
    docType: 'PSGC Location',
    fromJson: (json) => PsgcLocation.fromJson(json),
    toJson: (item) => item.toJson(),
  );

  bool get isAuthenticated => _sessionCookie != null;

  // Header helpers that inject session cookies
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }
    return headers;
  }

  /// Authenticate against ERPNext v15
  Future<bool> login(String username, String password) async {
    if (_isOffline) {
      loggedInEmail = username.trim().isEmpty ? 'offline_user@pims-marketing.com' : username.trim();
      await fetchAvailablePrograms();
      return true;
    }
    final url = Uri.parse('$baseUrl/api/method/login');
    try {
      final response = await http.post(
          url,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'usr': username,
            'pwd': password,
          }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['message'] == 'Logged In') {
          // Store username as the logged-in email
          loggedInEmail = username.trim();
          
          // Parse cookie header to persist session (e.g. sid=xxxxxx)
          final rawCookie = response.headers['set-cookie'];
          if (rawCookie != null) {
            // Keep the relevant parts of the cookie
            _sessionCookie = rawCookie.split(';').firstWhere(
                  (c) => c.trim().startsWith('sid='),
                  orElse: () => '',
                );
          }
          await fetchAvailablePrograms();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Login error: $e');
      return false;
    }
  }

  /// Log out
  void logout() {
    _sessionCookie = null;
    loggedInEmail = null;
  }

  /// Retrieve list of COREnergy engagements
  Future<List<Engagement>> fetchEngagements() async {
    if (_isOffline) {
      final cache = await _readFromCache('engagements_cache.json');
      if (cache != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cache);
          return dataList.map((json) => Engagement.fromJson(json)).toList();
        } catch (_) {}
      }
      return [];
    }
    final url = Uri.parse(
      '$baseUrl/api/resource/COREnergy%20Engage%20Copy?fields=["name","institution_name","region_name","province_name","city_municipality","barangay_name","street_address","sales_rep","leads_source","leads_status","creation","modified"]&limit=5000',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        await _writeToCache('engagements_cache.json', jsonEncode(dataList));
        return dataList.map((json) => Engagement.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load engagements: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch engagements error: $e');
      rethrow;
    }
  }

  /// Retrieve list of Company Institutions with region, province, city, and street address fields
  Future<List<Institution>> fetchInstitutions() async {
    if (_isOffline) {
      final cache = await _readFromCache('institutions_cache.json');
      if (cache != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cache);
          return dataList.map((json) => Institution.fromJson(json)).toList();
        } catch (_) {}
      }
      // Fallback to local asset
      try {
        final String localData = await rootBundle.loadString('assets/institutions.json');
        final List<dynamic> dataList = jsonDecode(localData);
        return dataList.map((json) => Institution.fromJson(json)).toList();
      } catch (err) {
        print('Failed to load local fallback institutions: $err');
        return [];
      }
    }
    final url = Uri.parse(
      '$baseUrl/api/resource/Institution?fields=["name","institution_name","region_name","province_name","city_municipality","street_address"]&limit=5000',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        await _writeToCache('institutions_cache.json', jsonEncode(dataList));
        return dataList.map((json) => Institution.fromJson(json)).toList();
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch institutions API error, loading local cached fallback: $e');
      try {
        final String localData = await rootBundle.loadString('assets/institutions.json');
        final List<dynamic> dataList = jsonDecode(localData);
        return dataList.map((json) => Institution.fromJson(json)).toList();
      } catch (err) {
        print('Failed to load local fallback institutions: $err');
        rethrow;
      }
    }
  }

  /// Create a new Institution entry (routed exclusively to COREnergy Engage Copy DocType for MCP COREnergy App)
  Future<Institution> createInstitution(Institution inst) async {
    final newEngage = COREnergyEngage(
      name: '',
      institutionName: inst.institutionName,
      hospitalClinic: inst.institutionName,
      region: inst.regionName,
      province: inst.provinceName,
      cityMunicipality: inst.cityMunicipality,
      streetAddress: inst.streetAddress,
      salesRep: loggedInEmail ?? 'jptan@profinsights.biz',
    );

    final created = await createCOREnergyEngage(newEngage);
    return Institution(
      name: created.name,
      institutionName: created.hospitalClinic ?? created.institutionName ?? inst.institutionName,
      regionName: created.region,
      provinceName: created.province,
      cityMunicipality: created.cityMunicipality,
      streetAddress: created.streetAddress,
    );
  }

  /// Retrieve list of COREnergy Engage logs
  Future<List<COREnergyEngage>> fetchCOREnergyEngages() async {
    List<COREnergyEngage> baseList = [];
    bool fetchedOnline = false;

    if (!_isOffline) {
      final url = Uri.parse(
        '$baseUrl/api/resource/COREnergy%20Engage%20Copy?fields=["name","institution_name","region_name","province_name","city_municipality","barangay_name","street_address","sales_rep","leads_source","leads_status","creation","modified"]&limit=5000',
      );
      try {
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 7));
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final List<dynamic> dataList = body['data'] ?? [];
          await _writeToCache('corenergy_engages_cache.json', jsonEncode(dataList));
          baseList = dataList.map((json) => COREnergyEngage.fromJson(json)).toList();
          for (var eng in baseList) {
            await DbHelper.saveCachedEngagement(eng);
          }
          fetchedOnline = true;
        }
      } catch (e) {
        print('Fetch COREnergy Engages online failed, reading from cache... error: $e');
        _isOffline = true;
        notifyListeners();
      }
    }

    if (!fetchedOnline) {
      try {
        baseList = await DbHelper.getCachedEngagements();
      } catch (_) {}
        if (baseList.isEmpty) {
          final cache = await _readFromCache('corenergy_engages_cache.json');
          if (cache != null) {
            try {
              final List<dynamic> jsonList = jsonDecode(cache);
              baseList = jsonList.map((json) => COREnergyEngage.fromJson(json)).toList();
            } catch (_) {}
          }
        }
        if (baseList.isEmpty) {
          // Mock fallback if no cache exists yet
        baseList = [
          COREnergyEngage(
            name: 'INST-04249',
            institutionName: 'INST-04249',
            hospitalClinic: 'Bayview Hotel Development Corp',
            region: 'NCR',
            province: 'Metro Manila-Manila',
            cityMunicipality: 'Ermita',
            streetAddress: '123 Roxas Blvd',
            salesRep: loggedInEmail ?? 'jptan@profinsights.biz',
            creation: '2026-07-01 10:00:00',
          ),
          COREnergyEngage(
            name: 'INST-04644',
            institutionName: 'INST-04644',
            hospitalClinic: 'Dolmar Press Incorporated',
            region: 'NCR',
            province: 'Metro Manila-Manila',
            cityMunicipality: 'Ermita',
            streetAddress: '456 Taft Ave',
            salesRep: 'kmtaotao@pims-marketing.com',
            creation: '2026-07-02 11:30:00',
          ),
        ];
      }
    }

    // Apply pending updates from SQLite over the baseList
    final pendingUpdates = await _readPendingUpdates();
    for (var update in pendingUpdates) {
      final idx = baseList.indexWhere((e) => e.name == update.name);
      if (idx != -1) {
        baseList[idx] = update;
      }
    }

    // Apply pending creations from SQLite over the baseList
    final pendingCreates = await _readPendingCreates();
    final existingNames = baseList.map((e) => e.name).toSet();
    for (var create in pendingCreates) {
      if (!existingNames.contains(create.name)) {
        baseList.insert(0, create);
      }
    }

    return baseList;
  }

  /// Retrieve full details of a single COREnergy Engage log (including child tables)
  Future<COREnergyEngage> fetchCOREnergyEngageByName(String name) async {
    // Check local SQLite queues first (if it's a pending create/update, SQLite details are most current)
    final pendingCreates = await _readPendingCreates();
    final matchCreate = pendingCreates.where((e) => e.name == name);
    if (matchCreate.isNotEmpty) return matchCreate.first;

    final pendingUpdates = await _readPendingUpdates();
    final matchUpdate = pendingUpdates.where((e) => e.name == name);
    if (matchUpdate.isNotEmpty) return matchUpdate.first;

    if (_isOffline) {
      final cache = await _readFromCache('engage_details_cache.json');
      if (cache != null) {
        try {
          final Map<String, dynamic> cacheMap = jsonDecode(cache);
          if (cacheMap.containsKey(name)) {
            return COREnergyEngage.fromJson(cacheMap[name]);
          }
        } catch (_) {}
      }

      // Check main list
      final mainList = await fetchCOREnergyEngages();
      final matchMain = mainList.where((e) => e.name == name);
      if (matchMain.isNotEmpty) return matchMain.first;

      throw Exception('COREnergy Engage detail not found in offline cache.');
    }

    final url = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy/$name');
    try {
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final detailedEngage = COREnergyEngage.fromJson(body['data']);
        await _saveDetailToCache(name, detailedEngage);
        return detailedEngage;
      } else {
        throw Exception('Failed to load COREnergy Engage detail: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch detail online failed, reading from cache... error: $e');
      final cache = await _readFromCache('engage_details_cache.json');
      if (cache != null) {
        try {
          final Map<String, dynamic> cacheMap = jsonDecode(cache);
          if (cacheMap.containsKey(name)) {
            return COREnergyEngage.fromJson(cacheMap[name]);
          }
        } catch (_) {}
      }
      throw Exception('COREnergy Engage detail not found in offline cache.');
    }
  }

  /// Create a new COREnergy Engage record
  Future<COREnergyEngage> createCOREnergyEngage(COREnergyEngage engage) async {
    if (_isOffline) {
      return _saveCOREnergyEngageOffline(engage, isCreate: true);
    }

    final url = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy');
    final payload = engage.toJson();
    payload.remove('name'); // Always remove name for CREATE requests to let server assign/determine naming
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        final created = COREnergyEngage.fromJson(body['data']);
        await _saveDetailToCache(created.name, created);

        // Update list cache
        final cache = await _readFromCache('corenergy_engages_cache.json');
        if (cache != null) {
          try {
            final List<dynamic> jsonList = jsonDecode(cache);
            final list = jsonList.map((json) => COREnergyEngage.fromJson(json)).toList();
            if (!list.any((e) => e.name == created.name)) {
              list.insert(0, created);
              await _writeToCache('corenergy_engages_cache.json', jsonEncode(list.map((e) => e.toJson()).toList()));
            }
          } catch (_) {}
        }

        return created;
      } else {
        throw Exception('Failed to create COREnergy Engage: ${response.body}');
      }
    } catch (e) {
      print('Create COREnergy Engage online failed: $e. Falling back to SQLite offline queue...');
      _isOffline = true;
      notifyListeners();
      return _saveCOREnergyEngageOffline(engage, isCreate: true);
    }
  }

  /// Update an existing COREnergy Engage record
  Future<COREnergyEngage> updateCOREnergyEngage(String name, COREnergyEngage engage) async {
    if (_isOffline) {
      return _saveCOREnergyEngageOffline(engage, isCreate: false);
    }

    final url = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy/$name');
    final payloadMap = engage.toJson();
    payloadMap.remove('name');
    try {
      final response = await http.put(
        url,
        headers: _headers,
        body: jsonEncode(payloadMap),
      ).timeout(const Duration(seconds: 7));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final updated = COREnergyEngage.fromJson(body['data']);
        await _saveDetailToCache(name, updated);

        // Update list cache
        final cache = await _readFromCache('corenergy_engages_cache.json');
        if (cache != null) {
          try {
            final List<dynamic> jsonList = jsonDecode(cache);
            final list = jsonList.map((json) => COREnergyEngage.fromJson(json)).toList();
            final idx = list.indexWhere((e) => e.name == name);
            if (idx != -1) {
              list[idx] = updated;
              await _writeToCache('corenergy_engages_cache.json', jsonEncode(list.map((e) => e.toJson()).toList()));
            }
          } catch (_) {}
        }

        return updated;
      } else if (response.statusCode == 404 || 
                 response.body.contains('DoesNotExistError') || 
                 response.body.contains('not found')) {
        print('COREnergy Engage document does not exist online for $name. Falling back to CREATE...');
        return await createCOREnergyEngage(engage);
      } else {
        throw Exception('Failed to update COREnergy Engage: ${response.body}');
      }
    } catch (e) {
      print('Update COREnergy Engage online failed: $e. Falling back to SQLite offline queue...');
      _isOffline = true;
      notifyListeners();
      return _saveCOREnergyEngageOffline(engage, isCreate: false);
    }
  }

  Future<COREnergyEngage> _saveCOREnergyEngageOffline(COREnergyEngage engage, {required bool isCreate}) async {
    final offlineKey = engage.institutionName ?? engage.name;
    final nowStr = DateTime.now().toIso8601String().replaceFirst('T', ' ').substring(0, 19);
    final localEngage = COREnergyEngage(
      name: engage.name.isEmpty ? offlineKey : engage.name,
      institutionName: offlineKey,
      hospitalClinic: engage.hospitalClinic,
      region: engage.region,
      province: engage.province,
      cityMunicipality: engage.cityMunicipality,
      streetAddress: engage.streetAddress,
      salesRep: engage.salesRep,
      creation: engage.creation ?? nowStr,
      modified: nowStr,
      contacts: engage.contacts,
      visits: engage.visits,
      actionItems: engage.actionItems,
    );

    if (isCreate) {
      await _addPendingCreate(localEngage);
    } else {
      await _addPendingUpdate(offlineKey, localEngage);
    }
    await _saveDetailToCache(localEngage.name, localEngage);
    if (localEngage.institutionName != null && localEngage.institutionName != localEngage.name) {
      await _saveDetailToCache(localEngage.institutionName!, localEngage);
    }

    // Update list cache
    final cache = await _readFromCache('corenergy_engages_cache.json');
    if (cache != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(cache);
        final list = jsonList.map((json) => COREnergyEngage.fromJson(json)).toList();
        final idx = list.indexWhere((e) => e.name == localEngage.name || e.institutionName == localEngage.institutionName);
        if (idx != -1) {
          list[idx] = localEngage;
        } else {
          list.insert(0, localEngage);
        }
        await _writeToCache('corenergy_engages_cache.json', jsonEncode(list.map((e) => e.toJson()).toList()));
      } catch (_) {}
    }

    return localEngage;
  }

  /// Create a new engagement record
  Future<Engagement> createEngagement(Engagement engagement) async {
    final url = Uri.parse('$baseUrl/api/resource/COREnergy%20Engage%20Copy');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(engagement.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        return Engagement.fromJson(body['data']);
      } else {
        throw Exception('Failed to create record: ${response.body}');
      }
    } catch (e) {
      print('Create engagement error: $e');
      rethrow;
    }
  }

  /// Update an existing engagement record
  Future<Engagement> updateEngagement(String name, Engagement engagement) async {
    final url = Uri.parse(
      '$baseUrl/api/resource/COREnergy%20Engage%20Copy/${Uri.encodeComponent(name)}',
    );
    try {
      final response = await http.put(
        url,
        headers: _headers,
        body: jsonEncode(engagement.toJson()),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return Engagement.fromJson(body['data']);
      } else {
        throw Exception('Failed to update record: ${response.body}');
      }
    } catch (e) {
      print('Update engagement error: $e');
      rethrow;
    }
  }

  /// Retrieve list of HCP/Doctors
  Future<List<Hcp>> fetchDoctors() async {
    final url = Uri.parse(
      '$baseUrl/api/resource/HCP?fields=["*"]&limit=200',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        return dataList.map((json) => Hcp.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load doctors: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch doctors error: $e');
      rethrow;
    }
  }

  /// Fetch full details of a specific Doctor (HCP) including child tables
  Future<Hcp> fetchDoctorDetail(String name) async {
    final url = Uri.parse(
      '$baseUrl/api/resource/HCP/${Uri.encodeComponent(name)}',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return Hcp.fromJson(body['data']);
      } else {
        throw Exception('Failed to load doctor details: ${response.body}');
      }
    } catch (e) {
      print('Fetch doctor detail error: $e');
      rethrow;
    }
  }

  /// Create a new HCP/Doctor record
  Future<Hcp> createDoctor(Hcp hcp) async {
    final url = Uri.parse('$baseUrl/api/resource/HCP');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(hcp.toJson()),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return Hcp.fromJson(body['data']);
      } else {
        throw Exception('Failed to create doctor: ${response.body}');
      }
    } catch (e) {
      print('Create doctor error: $e');
      rethrow;
    }
  }

  /// Update an existing HCP/Doctor record
  Future<Hcp> updateDoctor(String name, Hcp hcp) async {
    final url = Uri.parse(
      '$baseUrl/api/resource/HCP/${Uri.encodeComponent(name)}',
    );
    try {
      final response = await http.put(
        url,
        headers: _headers,
        body: jsonEncode(hcp.toJson()),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return Hcp.fromJson(body['data']);
      } else {
        throw Exception('Failed to update doctor: ${response.body}');
      }
    } catch (e) {
      print('Update doctor error: $e');
      rethrow;
    }
  }

  /// Retrieve list of HCP Profile Submissions
  Future<List<HcpProfileSubmission>> fetchSubmissions() async {
    final url = Uri.parse(
      '$baseUrl/api/resource/HCP%20Profile%20Submission?fields=["*"]&limit=100',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        return dataList.map((json) => HcpProfileSubmission.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load submissions: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch submissions error: $e');
      rethrow;
    }
  }

  /// Create a new HCP Profile Submission record
  Future<HcpProfileSubmission> createSubmission(HcpProfileSubmission submission) async {
    final url = Uri.parse('$baseUrl/api/resource/HCP%20Profile%20Submission');
    try {
      final response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(submission.toJson()),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return HcpProfileSubmission.fromJson(body['data']);
      } else {
        throw Exception('Failed to create submission: ${response.body}');
      }
    } catch (e) {
      print('Create submission error: $e');
      rethrow;
    }
  }

  /// Retrieve list of Specializations
  Future<List<Specialization>> fetchSpecializations() async {
    final url = Uri.parse(
      '$baseUrl/api/resource/Specialization?fields=["name","specialty","specialty_group","parent_specialization","is_group"]&limit=500',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        return dataList.map((json) => Specialization.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load specializations: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch specializations error: $e');
      rethrow;
    }
  }

  /// Retrieve list of PSGC Locations
  Future<List<PsgcLocation>> fetchPsgcLocations() async {
    if (_isOffline) {
      final cache = await _readFromCache('psgc_locations_cache.json');
      if (cache != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cache);
          return dataList.map((json) => PsgcLocation.fromJson(json)).toList();
        } catch (_) {}
      }
      return [];
    }
    final url = Uri.parse(
      '$baseUrl/api/resource/PSGC%20Location?fields=["name","location_label","location_type","parent_psgc_location","psgc_code","is_group"]&filters=[["location_type","in",["Region","Province","City"]]]&limit=3000',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        await _writeToCache('psgc_locations_cache.json', jsonEncode(dataList));
        return dataList.map((json) => PsgcLocation.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load PSGC locations: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch PSGC locations error: $e');
      final cache = await _readFromCache('psgc_locations_cache.json');
      if (cache != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cache);
          return dataList.map((json) => PsgcLocation.fromJson(json)).toList();
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Retrieve active Survey Templates
  Future<List<HcpSurveyTemplate>> fetchSurveyTemplates() async {
    final url = Uri.parse(
      '$baseUrl/api/resource/HCP%20Survey%20Template?fields=["name","template_name","is_active","account_or_program","description"]&filters=[["is_active","=",1]]',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        
        // Survey templates have nested questions child table, we load details for active ones
        List<HcpSurveyTemplate> templates = [];
        for (var item in dataList) {
          final detailUrl = Uri.parse('$baseUrl/api/resource/HCP%20Survey%20Template/${Uri.encodeComponent(item['name'])}');
          final detailResp = await http.get(detailUrl, headers: _headers);
          if (detailResp.statusCode == 200) {
            final detailBody = jsonDecode(detailResp.body);
            templates.add(HcpSurveyTemplate.fromJson(detailBody['data']));
          }
        }
        return templates;
      } else {
        throw Exception('Failed to load survey templates: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch survey templates error: $e');
      rethrow;
    }
  }

  /// Retrieve list of HCP Types (used as Link values for hcp_type field)
  Future<List<HcpType>> fetchHcpTypes() async {
    final url = Uri.parse(
      '$baseUrl/api/resource/HCP%20Type?fields=["name","hcp_type","description"]&limit=50',
    );
    try {
      final response = await http.get(url, headers: _headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        return dataList.map((json) => HcpType.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load HCP types: ${response.statusCode}');
      }
    } catch (e) {
      print('Fetch HCP types error: $e');
      rethrow;
    }
  }
}

class FrappeRepository<T> {
  final ApiService _api;
  final String docType;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, dynamic> Function(T) toJson;

  FrappeRepository({
    required ApiService api,
    required this.docType,
    required this.fromJson,
    required this.toJson,
  }) : _api = api;

  /// Fetch list of records of this DocType
  Future<List<T>> list({
    List<String>? fields,
    List<dynamic>? filters,
    int? limit,
    int? limitStart,
    String? orderBy,
  }) async {
    final Map<String, String> queryParams = {};
    if (fields != null) {
      queryParams['fields'] = jsonEncode(fields);
    }
    if (filters != null) {
      queryParams['filters'] = jsonEncode(filters);
    }
    if (limit != null) {
      queryParams['limit_page_length'] = limit.toString();
    }
    if (limitStart != null) {
      queryParams['limit_start'] = limitStart.toString();
    }
    if (orderBy != null) {
      queryParams['order_by'] = orderBy;
    }

    final uri = Uri.parse('${_api.baseUrl}/api/resource/${Uri.encodeComponent(docType)}')
        .replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

    try {
      final response = await http.get(uri, headers: _api._headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        return dataList.map((json) => fromJson(json)).toList();
      } else {
        throw Exception('Failed to load list for $docType: ${response.statusCode}');
      }
    } catch (e) {
      print('FrappeRepository.list error on $docType: $e');
      rethrow;
    }
  }

  /// Fetch details of a single record by its name (ID), including its nested child tables
  Future<T> get(String name) async {
    final uri = Uri.parse('${_api.baseUrl}/api/resource/${Uri.encodeComponent(docType)}/${Uri.encodeComponent(name)}');
    try {
      final response = await http.get(uri, headers: _api._headers);
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return fromJson(body['data']);
      } else {
        throw Exception('Failed to load detail for $docType ($name): ${response.statusCode}');
      }
    } catch (e) {
      print('FrappeRepository.get error on $docType: $e');
      rethrow;
    }
  }

  /// Create a new record with nested child table arrays
  Future<T> create(T item) async {
    final uri = Uri.parse('${_api.baseUrl}/api/resource/${Uri.encodeComponent(docType)}');
    try {
      final response = await http.post(
        uri,
        headers: _api._headers,
        body: jsonEncode(toJson(item)),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return fromJson(body['data']);
      } else {
        throw Exception('Failed to create $docType: ${response.body}');
      }
    } catch (e) {
      print('FrappeRepository.create error on $docType: $e');
      rethrow;
    }
  }

  /// Update an existing record and dynamically reconcile child tables
  Future<T> update(String name, T item) async {
    final uri = Uri.parse('${_api.baseUrl}/api/resource/${Uri.encodeComponent(docType)}/${Uri.encodeComponent(name)}');
    try {
      final response = await http.put(
        uri,
        headers: _api._headers,
        body: jsonEncode(toJson(item)),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return fromJson(body['data']);
      } else {
        throw Exception('Failed to update $docType ($name): ${response.body}');
      }
    } catch (e) {
      print('FrappeRepository.update error on $docType: $e');
      rethrow;
    }
  }
}

