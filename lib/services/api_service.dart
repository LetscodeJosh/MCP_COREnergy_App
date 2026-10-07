import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/engagement.dart';
import '../models/hcp.dart';
import '../models/submission.dart';
import '../models/lookup_models.dart';
import '../models/hcp_account.dart';
import '../models/corenergy_engage.dart';
import '../app_config.dart';
import 'db_helper.dart';

class ApiService extends ChangeNotifier {
  ApiService() {
    _restoreSavedSession();
    checkOnlineStatus();
    _startAutoSyncTimer();
  }

  String? _savedPassword;
  String? _csrfToken;

  Future<void> _restoreSavedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastBaseUrl = prefs.getString('pims_active_base_url');
      if (lastBaseUrl != null && lastBaseUrl != baseUrl) {
        // Base URL changed (e.g. dev -> production). Flush obsolete session cookies
        await prefs.remove('pims_session_cookie');
        _sessionCookie = null;
      }
      await prefs.setString('pims_active_base_url', baseUrl);

      final savedCookie = prefs.getString('pims_session_cookie');
      final savedEmail = prefs.getString('pims_logged_in_email');
      final savedPassword = prefs.getString('pims_saved_password');
      if (savedCookie != null && savedCookie.isNotEmpty) {
        _sessionCookie = savedCookie;
      }
      if (savedEmail != null && savedEmail.isNotEmpty) {
        loggedInEmail = savedEmail;
      }
      if (savedPassword != null && savedPassword.isNotEmpty) {
        _savedPassword = savedPassword;
      }
      notifyListeners();
    } catch (_) {}
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
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        // Always check online status to keep the UI Mode indicator accurate
        final isOnline = await checkOnlineStatus();
        if (isOnline && !_isSyncing) {
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
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      final online = response.statusCode == 200;
      if (_isOffline != !online) {
        _isOffline = !online;
        notifyListeners();
      }
      return online;
    } catch (_) {
      if (!_isOffline) {
        _isOffline = true;
        notifyListeners();
      }
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
      await ensureCsrfToken();

      // Clean up legacy pending institution rows without posting to Institution DocType (reserved for HCP App)
      try {
        final pendingInstRows = await DbHelper.getPendingInstitutions();
        for (var instRow in pendingInstRows) {
          await DbHelper.deletePendingInstitution(instRow['temp_id']);
        }
      } catch (e) {
        print('Cleanup legacy institution rows warning: $e');
      }

      final pendingRows = await DbHelper.getPendingEngagements();
      if (pendingRows.isEmpty) {
        return; // finally block will reset _isSyncing
      }

      for (var row in pendingRows) {
        final String tempId = row['temp_id'];
        final String actionType = row['action_type'];
        final rowData = jsonDecode(row['data']);

        try {
          if (actionType == 'ENG_CREATE' || actionType == 'ENG_UPDATE') {
            final Engagement eng = Engagement.fromJson(Map<String, dynamic>.from(rowData));
            final targetDocType = eng.unsuccessfulCall
                ? 'Unsuccessful%20COREnergy%20Engagement'
                : 'Successful%20COREnergy%20Engagement';

            final payload = eng.toJson();
            if (actionType == 'ENG_CREATE' || tempId.startsWith('ENG-OFFLINE-')) {
              payload.remove('name');
            }
            if (payload['company'] != null) {
              final comp = payload['company'].toString().trim();
              final resolvedId = await _resolveInstitutionId(comp);
              if (resolvedId != null) {
                payload['company'] = resolvedId;
              } else {
                payload.remove('company');
              }
            }
            if (payload['latitude'] == null || payload['latitude'].toString().isEmpty) {
              payload['latitude'] = '0.0';
            }
            if (payload['longitude'] == null || payload['longitude'].toString().isEmpty) {
              payload['longitude'] = '0.0';
            }
            if (!eng.unsuccessfulCall) {
              payload.remove('reason_for_unsuccessful_call');
            }

            final isCreate = (actionType == 'ENG_CREATE' || tempId.startsWith('ENG-OFFLINE-'));
            final url = isCreate
                ? Uri.parse('$baseUrl/api/resource/$targetDocType')
                : Uri.parse('$baseUrl/api/resource/$targetDocType/${Uri.encodeComponent(tempId)}');

            http.Response response = isCreate
                ? await http.post(url, headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 15))
                : await http.put(url, headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 15));

            if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
              final reauthed = await _reAuthenticateSilently();
              if (reauthed) {
                response = isCreate
                    ? await http.post(url, headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 15))
                    : await http.put(url, headers: _headers, body: jsonEncode(payload)).timeout(const Duration(seconds: 15));
              }
            }

            if (response.statusCode == 200 || response.statusCode == 201) {
              final body = jsonDecode(response.body);
              final serverName = body['data']?['name'];
              await DbHelper.deletePendingEngagement(tempId);
              somethingSynced = true;

              if (serverName != null && tempId != serverName) {
                final cache = await _readFromCache('engagements_cache.json');
                if (cache != null) {
                  try {
                    final List<dynamic> cachedList = jsonDecode(cache);
                    for (int i = 0; i < cachedList.length; i++) {
                      if (cachedList[i]['name'] == tempId) {
                        cachedList[i]['name'] = serverName;
                        break;
                      }
                    }
                    await _writeToCache('engagements_cache.json', jsonEncode(cachedList));
                  } catch (_) {}
                }
              }
              _syncMessage = 'Sync successful: Engagement uploaded.';
              notifyListeners();
            } else {
              print('Sync engagement row $tempId failed with ${response.statusCode}: ${response.body}');
            }
            continue;
          }

          final COREnergyEngage engage = COREnergyEngage.fromJson(Map<String, dynamic>.from(rowData));
          final targetDocTypes = ['COREnergy%20Engage%20Copy', 'COREnergy%20Engage'];
          if (actionType == 'CREATE') {
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
            payload.remove('name');

            http.Response? response;
            for (final dt in targetDocTypes) {
              try {
                final url = Uri.parse('$baseUrl/api/resource/$dt');
                response = await http.post(
                  url,
                  headers: _headers,
                  body: jsonEncode(payload),
                ).timeout(const Duration(seconds: 15));

                if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
                  final reauthed = await _reAuthenticateSilently();
                  if (reauthed) {
                    response = await http.post(
                      url,
                      headers: _headers,
                      body: jsonEncode(payload),
                    ).timeout(const Duration(seconds: 15));
                  }
                }

                if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 409) {
                  break;
                }
              } catch (_) {}
            }

            if (response != null && (response.statusCode == 200 || response.statusCode == 201)) {
              final body = jsonDecode(response.body);
              final created = COREnergyEngage.fromJson(body['data']);
              await _saveDetailToCache(created.name, created);
              if (created.institutionName != null) {
                await _saveDetailToCache(created.institutionName!, created);
              }
              somethingSynced = true;
            } else if (response != null && (response.statusCode == 409 ||
                       response.body.contains('already exists') ||
                       response.body.contains('DuplicateEntryError') ||
                       response.body.contains('Duplicate'))) {
              print('Duplicate COREnergy Engage document detected during sync for ${engage.institutionName}. Falling back to PUT update...');

              String? serverDocName;
              String activeDocType = 'COREnergy%20Engage%20Copy';
              for (final dt in targetDocTypes) {
                try {
                  final searchUrl = Uri.parse(
                    '$baseUrl/api/resource/$dt?filters=[["institution_name","=","${engage.institutionName}"]]'
                  );
                  final searchResponse = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 10));
                  if (searchResponse.statusCode == 200) {
                    final searchBody = jsonDecode(searchResponse.body);
                    final List<dynamic> searchData = searchBody['data'] ?? [];
                    if (searchData.isNotEmpty) {
                      serverDocName = searchData[0]['name'];
                      activeDocType = dt;
                      break;
                    }
                  }
                } catch (e) {
                  print('Error searching for duplicate document name in $dt: $e');
                }
              }

              final targetName = serverDocName ?? engage.name;
              final updateUrl = Uri.parse('$baseUrl/api/resource/$activeDocType/$targetName');
              final updateResponse = await http.put(
                updateUrl,
                headers: _headers,
                body: jsonEncode(payload),
              ).timeout(const Duration(seconds: 15));

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
              throw Exception('Sync create failed: ${response?.body ?? "No server response"}');
            }
          } else if (actionType == 'UPDATE') {
            String targetName = engage.name;
            String activeDocType = 'COREnergy%20Engage%20Copy';
            if (targetName == engage.institutionName) {
              for (final dt in targetDocTypes) {
                try {
                  final searchUrl = Uri.parse(
                    '$baseUrl/api/resource/$dt?filters=[["institution_name","=","${engage.institutionName}"]]'
                  );
                  final searchResponse = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 10));
                  if (searchResponse.statusCode == 200) {
                    final searchBody = jsonDecode(searchResponse.body);
                    final List<dynamic> searchData = searchBody['data'] ?? [];
                    if (searchData.isNotEmpty) {
                      targetName = searchData[0]['name'];
                      activeDocType = dt;
                      break;
                    }
                  }
                } catch (e) {
                  print('Error resolving server name for update in $dt: $e');
                }
              }
            }

            final payloadMap = engage.toJson();
            payloadMap.remove('name');
            http.Response? response;
            for (final dt in [activeDocType, if (activeDocType != targetDocTypes[0]) targetDocTypes[0], targetDocTypes[1]]) {
              try {
                final url = Uri.parse('$baseUrl/api/resource/$dt/$targetName');
                response = await http.put(
                  url,
                  headers: _headers,
                  body: jsonEncode(payloadMap),
                ).timeout(const Duration(seconds: 15));

                if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
                  final reauthed = await _reAuthenticateSilently();
                  if (reauthed) {
                    response = await http.put(
                      url,
                      headers: _headers,
                      body: jsonEncode(payloadMap),
                    ).timeout(const Duration(seconds: 15));
                  }
                }

                if (response.statusCode == 200) break;
              } catch (_) {}
            }

            if (response != null && response.statusCode == 200) {
              final body = jsonDecode(response.body);
              final updated = COREnergyEngage.fromJson(body['data']);
              await _saveDetailToCache(updated.name, updated);
              if (updated.institutionName != null) {
                await _saveDetailToCache(updated.institutionName!, updated);
              }
              somethingSynced = true;
            } else if (response != null && (response.statusCode == 404 ||
                       response.body.contains('DoesNotExistError') ||
                       response.body.contains('not found'))) {
              print('COREnergy Engage document does not exist during sync for $targetName. Falling back to POST create...');
              http.Response? createResponse;
              for (final dt in targetDocTypes) {
                try {
                  final createUrl = Uri.parse('$baseUrl/api/resource/$dt');
                  createResponse = await http.post(
                    createUrl,
                    headers: _headers,
                    body: jsonEncode(payloadMap),
                  ).timeout(const Duration(seconds: 15));

                  if ((createResponse.statusCode == 401 || createResponse.statusCode == 403) && loggedInEmail != null) {
                    final reauthed = await _reAuthenticateSilently();
                    if (reauthed) {
                      createResponse = await http.post(
                        createUrl,
                        headers: _headers,
                        body: jsonEncode(payloadMap),
                      ).timeout(const Duration(seconds: 15));
                    }
                  }

                  if (createResponse.statusCode == 200 || createResponse.statusCode == 201) break;
                } catch (_) {}
              }

              if (createResponse != null && (createResponse.statusCode == 200 || createResponse.statusCode == 201)) {
                final body = jsonDecode(createResponse.body);
                final created = COREnergyEngage.fromJson(body['data']);
                await _saveDetailToCache(created.name, created);
                if (created.institutionName != null) {
                  await _saveDetailToCache(created.institutionName!, created);
                }
                somethingSynced = true;
              } else {
                throw Exception('Sync fallback create failed: ${createResponse?.body ?? "No server response"}');
              }
            } else {
              throw Exception('Sync update failed: ${response?.body ?? "No server response"}');
            }
          }
          await DbHelper.deletePendingEngagement(tempId);
          _syncMessage = 'Sync successful: "${engage.hospitalClinic ?? engage.name}" is now uploaded.';
          notifyListeners();
        } catch (e) {
          print('Sync failed for offline row $tempId: $e');
          _syncMessage = 'Sync warning: row $tempId deferred.';
          notifyListeners();
          // Skip this row and continue with remaining rows instead of blocking the entire queue
          continue;
        }
      }

      if (somethingSynced && !_isOffline) {
        await fetchEngagements();
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
  String get baseUrl => AppConfig.baseUrl;
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

  // Header helpers that inject session cookies and CSRF tokens
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_sessionCookie != null) {
      headers['Cookie'] = _sessionCookie!;
    }
    if (_csrfToken != null && _csrfToken!.isNotEmpty) {
      headers['X-Frappe-CSRF-Token'] = _csrfToken!;
    }
    return headers;
  }

  /// Ensure a valid Frappe CSRF Token is available for mutating API calls
  Future<String?> ensureCsrfToken() async {
    if (_csrfToken != null && _csrfToken!.isNotEmpty) {
      return _csrfToken;
    }
    if (_isOffline || _sessionCookie == null) {
      return null;
    }
    try {
      final appUrl = Uri.parse('$baseUrl/app');
      final appRes = await http.get(appUrl, headers: {
        'Cookie': _sessionCookie!,
        'Accept': 'text/html,application/xhtml+xml',
      }).timeout(const Duration(seconds: 6));
      if (appRes.statusCode == 200) {
        final html = appRes.body;
        final csrfMatch = RegExp(r'frappe\.csrf_token\s*=\s*["\x27]([^"\x27]+)["\x27]').firstMatch(html);
        if (csrfMatch != null) {
          _csrfToken = csrfMatch.group(1);
          return _csrfToken;
        }
      }
    } catch (e) {
      print('Error extracting CSRF token: $e');
    }
    return _csrfToken;
  }

  /// Autonomous silent re-authentication to prevent session expiry lockouts
  Future<bool> _reAuthenticateSilently() async {
    if (loggedInEmail == null || _savedPassword == null) return false;
    try {
      final url = Uri.parse('$baseUrl/api/method/login');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'usr': loggedInEmail,
          'pwd': _savedPassword,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final rawCookie = response.headers['set-cookie'];
        if (rawCookie != null) {
          final match = RegExp(r'sid=([^;,\s]+)').firstMatch(rawCookie);
          if (match != null) {
            _sessionCookie = 'sid=${match.group(1)}';
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('pims_session_cookie', _sessionCookie!);
            await ensureCsrfToken();
            return true;
          }
        }
      }
    } catch (e) {
      print('Silent re-authentication notice: $e');
    }
    return false;
  }

  /// Authenticate against ERPNext v15
  Future<bool> login(String username, String password) async {
    if (_isOffline) {
      loggedInEmail = username.trim().isEmpty ? 'offline_user@pims-marketing.com' : username.trim();
      _savedPassword = password;
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
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['message'] == 'Logged In') {
          // Store username as the logged-in email
          loggedInEmail = username.trim();
          _savedPassword = password;
          
          // Parse cookie header to persist session (e.g. sid=xxxxxx)
          final rawCookie = response.headers['set-cookie'];
          if (rawCookie != null) {
            final match = RegExp(r'sid=([^;,\s]+)').firstMatch(rawCookie);
            if (match != null) {
              _sessionCookie = 'sid=${match.group(1)}';
            }
            try {
              final prefs = await SharedPreferences.getInstance();
              if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
                await prefs.setString('pims_session_cookie', _sessionCookie!);
              }
              await prefs.setString('pims_logged_in_email', loggedInEmail ?? '');
              await prefs.setString('pims_saved_password', password);
            } catch (_) {}
          }
          await ensureCsrfToken();
          await fetchAvailablePrograms();
          return true;
        }
      }
      return false;
    } catch (e) {
      print('Login network error: $e');
      // If network unreachable or timeout, gracefully authenticate offline
      _isOffline = true;
      loggedInEmail = username.trim().isEmpty ? 'offline_user@pims-marketing.com' : username.trim();
      _savedPassword = password;
      notifyListeners();
      await fetchAvailablePrograms();
      return true;
    }
  }

  /// Log out
  void logout() async {
    _sessionCookie = null;
    loggedInEmail = null;
    _savedPassword = null;
    _csrfToken = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pims_session_cookie');
      await prefs.remove('pims_logged_in_email');
      await prefs.remove('pims_saved_password');
    } catch (_) {}
    notifyListeners();
  }

  Future<List<Engagement>> _applyPendingEngagements(List<Engagement> list) async {
    try {
      final pendingRows = await DbHelper.getPendingEngagements();
      for (var row in pendingRows) {
        final action = row['action_type'];
        if (action == 'ENG_CREATE' || action == 'ENG_UPDATE') {
          try {
            final engJson = jsonDecode(row['data']);
            final pendingEng = Engagement.fromJson(Map<String, dynamic>.from(engJson));
            final idx = list.indexWhere((e) => e.name == pendingEng.name);
            if (idx != -1) {
              list[idx] = pendingEng;
            } else {
              list.insert(0, pendingEng);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      print('Error applying pending engagements: $e');
    }
    return list;
  }

  /// Retrieve list of COREnergy engagements
  Future<List<Engagement>> fetchEngagements() async {
    if (_isOffline) {
      final cache = await _readFromCache('engagements_cache.json');
      if (cache != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cache);
          if (dataList.isNotEmpty) {
            final list = dataList.map((json) => Engagement.fromJson(Map<String, dynamic>.from(json))).toList();
            return await _applyPendingEngagements(list);
          }
        } catch (_) {}
      }
      final fallback = await _loadFallbackEngagements();
      return await _applyPendingEngagements(fallback);
    }

    final List<dynamic> combinedList = [];
    const fieldsJson = '["name","company","latitude","longitude","location_accuracy","picture","sales_rep","contact","last_name","position_or_role","email_address","contact_number","date_and_time_of_sales_appointment","decision_maker_or_responsible_person_not_available","reason_for_unsuccessful_call","unsuccessful_call","creation","modified"]';

    try {
      // 1. Fetch Successful COREnergy Engagement
      final succUrl = Uri.parse(
        '$baseUrl/api/resource/Successful%20COREnergy%20Engagement?fields=$fieldsJson&limit_page_length=5000',
      );
      var succResponse = await http.get(succUrl, headers: _headers).timeout(const Duration(seconds: 15));
      if ((succResponse.statusCode == 401 || succResponse.statusCode == 403) && loggedInEmail != null) {
        final reauthed = await _reAuthenticateSilently();
        if (reauthed) {
          succResponse = await http.get(succUrl, headers: _headers).timeout(const Duration(seconds: 15));
        }
      }
      if (succResponse.statusCode == 200) {
        final body = jsonDecode(succResponse.body);
        final List<dynamic> dataList = body['data'] ?? [];
        for (var item in dataList) {
          item['unsuccessful_call'] = 0;
          combinedList.add(item);
        }
      }

      // 2. Fetch Unsuccessful COREnergy Engagement
      final unsuccUrl = Uri.parse(
        '$baseUrl/api/resource/Unsuccessful%20COREnergy%20Engagement?fields=$fieldsJson&limit_page_length=5000',
      );
      var unsuccResponse = await http.get(unsuccUrl, headers: _headers).timeout(const Duration(seconds: 15));
      if ((unsuccResponse.statusCode == 401 || unsuccResponse.statusCode == 403) && loggedInEmail != null) {
        final reauthed = await _reAuthenticateSilently();
        if (reauthed) {
          unsuccResponse = await http.get(unsuccUrl, headers: _headers).timeout(const Duration(seconds: 15));
        }
      }
      if (unsuccResponse.statusCode == 200) {
        final body = jsonDecode(unsuccResponse.body);
        final List<dynamic> dataList = body['data'] ?? [];
        for (var item in dataList) {
          item['unsuccessful_call'] = 1;
          combinedList.add(item);
        }
      }

      if (combinedList.isNotEmpty) {
        combinedList.sort((a, b) => (b['creation'] ?? '').toString().compareTo((a['creation'] ?? '').toString()));
        await _writeToCache('engagements_cache.json', jsonEncode(combinedList));
        final list = combinedList.map((json) => Engagement.fromJson(Map<String, dynamic>.from(json))).toList();
        return await _applyPendingEngagements(list);
      }
    } catch (e) {
      print('Fetch engagements online warning: $e');
    }

    final cache = await _readFromCache('engagements_cache.json');
    if (cache != null) {
      try {
        final List<dynamic> dataList = jsonDecode(cache);
        if (dataList.isNotEmpty) {
          final list = dataList.map((json) => Engagement.fromJson(Map<String, dynamic>.from(json))).toList();
          return await _applyPendingEngagements(list);
        }
      } catch (_) {}
    }
    final fallback = await _loadFallbackEngagements();
    return await _applyPendingEngagements(fallback);
  }

  Future<List<Engagement>> _loadFallbackEngagements() async {
    try {
      final String localData = await rootBundle.loadString('assets/engagements.json');
      final List<dynamic> dataList = jsonDecode(localData);
      return dataList.map((json) => Engagement.fromJson(Map<String, dynamic>.from(json))).toList();
    } catch (e) {
      print('Failed to load fallback engagements: $e');
      return [];
    }
  }

  /// Retrieve list of Company Institutions with region, province, city, and street address fields
  Future<List<Institution>> fetchInstitutions() async {
    if (_isOffline) {
      final cache = await _readFromCache('institutions_cache.json');
      if (cache != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cache);
          if (dataList.isNotEmpty) {
            return dataList.map((json) => Institution.fromJson(Map<String, dynamic>.from(json))).toList();
          }
        } catch (_) {}
      }
      return await _loadFallbackInstitutions();
    }
    final url = Uri.parse(
      '$baseUrl/api/resource/Institution?fields=["name","institution_name","region_name","province_name","city_municipality","street_address"]&limit_page_length=5000',
    );
    try {
      var response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
      if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
        final reauthed = await _reAuthenticateSilently();
        if (reauthed) {
          response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
        }
      }
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        if (dataList.isNotEmpty) {
          await _writeToCache('institutions_cache.json', jsonEncode(dataList));
          return dataList.map((json) => Institution.fromJson(Map<String, dynamic>.from(json))).toList();
        }
      }
    } catch (e) {
      print('Fetch institutions API error, loading local cached fallback: $e');
    }

    final cache = await _readFromCache('institutions_cache.json');
    if (cache != null) {
      try {
        final List<dynamic> dataList = jsonDecode(cache);
        if (dataList.isNotEmpty) {
          return dataList.map((json) => Institution.fromJson(Map<String, dynamic>.from(json))).toList();
        }
      } catch (_) {}
    }
    return await _loadFallbackInstitutions();
  }

  Future<List<Institution>> _loadFallbackInstitutions() async {
    try {
      final String localData = await rootBundle.loadString('assets/institutions.json');
      final List<dynamic> dataList = jsonDecode(localData);
      return dataList.map((json) => Institution.fromJson(Map<String, dynamic>.from(json))).toList();
    } catch (err) {
      print('Failed to load local fallback institutions: $err');
      return [];
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
      final targetDocTypes = ['COREnergy%20Engage%20Copy', 'COREnergy%20Engage'];
      for (final dt in targetDocTypes) {
        final url = Uri.parse(
          '$baseUrl/api/resource/$dt?fields=["name","institution_name","region_name","province_name","city_municipality","barangay_name","street_address","sales_rep","leads_source","leads_status","ownership_nationality","latitude","longitude","location_accuracy","creation","modified"]&limit_page_length=5000',
        );
        try {
          var response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
          if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
            final reauthed = await _reAuthenticateSilently();
            if (reauthed) {
              response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 15));
            }
          }
          if (response.statusCode == 200) {
            final body = jsonDecode(response.body);
            final List<dynamic> dataList = body['data'] ?? [];
            if (dataList.isNotEmpty) {
              await _writeToCache('corenergy_engages_cache.json', jsonEncode(dataList));
              baseList = dataList.map((json) => COREnergyEngage.fromJson(Map<String, dynamic>.from(json))).toList();
              // Fast asynchronous batch save so main UI thread does not freeze
              DbHelper.saveCachedEngagementsBatch(baseList).catchError((e) {
                print('Batch cache save error: $e');
              });
              fetchedOnline = true;
              break;
            }
          }
        } catch (e) {
          print('Fetch $dt online error: $e');
        }
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
        try {
          final String localData = await rootBundle.loadString('assets/institutions.json');
          final List<dynamic> jsonList = jsonDecode(localData);
          baseList = jsonList.map((j) => COREnergyEngage(
            name: j['name'] ?? '',
            institutionName: j['name'],
            hospitalClinic: j['institution_name'],
            region: j['region_name'],
            province: j['province_name'],
            cityMunicipality: j['city_municipality'],
            streetAddress: j['street_address'],
            salesRep: loggedInEmail ?? 'kmtaotao@pims-marketing.com',
          )).toList();
        } catch (_) {}
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

    final targetDocTypes = ['COREnergy%20Engage%20Copy', 'COREnergy%20Engage'];
    for (final dt in targetDocTypes) {
      final url = Uri.parse('$baseUrl/api/resource/$dt/$name');
      try {
        var response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 7));
        if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
          final reauthed = await _reAuthenticateSilently();
          if (reauthed) {
            response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 7));
          }
        }
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final detailedEngage = COREnergyEngage.fromJson(body['data']);
          await _saveDetailToCache(name, detailedEngage);
          return detailedEngage;
        }
      } catch (e) {
        print('Fetch detail on $dt failed: $e');
      }
    }

    final cache = await _readFromCache('engage_details_cache.json');
    if (cache != null) {
      try {
        final Map<String, dynamic> cacheMap = jsonDecode(cache);
        if (cacheMap.containsKey(name)) {
          return COREnergyEngage.fromJson(cacheMap[name]);
        }
      } catch (_) {}
    }

    // Fallback: Check main engagements list for this record
    try {
      final mainList = await fetchCOREnergyEngages();
      final matchMain = mainList.where((e) => e.name == name || e.institutionName == name);
      if (matchMain.isNotEmpty) return matchMain.first;
    } catch (_) {}

    return COREnergyEngage(
      name: name,
      hospitalClinic: name,
      institutionName: name,
    );
  }

  /// Resolve raw company name/ID into a verified Institution DocType link ID to prevent 417 LinkValidationError
  Future<String?> _resolveInstitutionId(String? rawCompany) async {
    if (rawCompany == null || rawCompany.isEmpty) return null;
    final comp = rawCompany.trim();
    if (comp.toLowerCase() == 'corenergy' || comp.toLowerCase() == 'null') return null;

    final instList = await fetchInstitutions();
    // 1. Direct match by ID (e.g. INST-00012)
    final direct = instList.where((i) => i.name.toLowerCase() == comp.toLowerCase());
    if (direct.isNotEmpty) return direct.first.name;

    // 2. Match by institutionName
    final byName = instList.where((i) =>
        i.institutionName.toLowerCase() == comp.toLowerCase() ||
        i.institutionName.toLowerCase().contains(comp.toLowerCase()));
    if (byName.isNotEmpty) return byName.first.name;

    return null;
  }

  /// Automatically sync visits from COREnergy Engage Copy into Successful/Unsuccessful COREnergy Engagement DocTypes
  Future<void> _syncCOREnergyVisitsToEngagements(COREnergyEngage engage) async {
    try {
      if (engage.visits.isEmpty) return;
      for (var visit in engage.visits) {
        final eng = Engagement(
          name: null,
          company: engage.name.isNotEmpty ? engage.name : engage.institutionName,
          salesRep: engage.salesRep ?? loggedInEmail ?? 'jptan@profinsights.biz',
          dateAndTimeOfSalesAppointment: DateTime.now().toString().substring(0, 19),
          unsuccessfulCall: visit.unsuccessfulCall,
          reasonForUnsuccessfulCall: visit.unsuccessfulCall
              ? (visit.reasonForUnsuccessfulCall ?? 'Prior appointment or letter needed')
              : null,
          decisionMakerOrResponsiblePersonNotAvailable: visit.decisionMakerNotAvailable,
          latitude: (engage.latitude != null && engage.latitude != '0.0') ? engage.latitude : '14.5995',
          longitude: (engage.longitude != null && engage.longitude != '0.0') ? engage.longitude : '120.9842',
          locationAccuracy: double.tryParse(engage.locationAccuracy ?? '') ?? 0.0,
        );
        createEngagement(eng).catchError((e) {
          print('Auto-sync visit to engagement warning: $e');
          return eng;
        });
      }
    } catch (e) {
      print('Cross-sync visits to Engagement warning: $e');
    }
  }

  /// Automatically sync an engagement visit into COREnergy Engage Copy's visits child table
  Future<void> _syncEngagementToCOREnergyEngageCopy(Engagement eng) async {
    try {
      final comp = eng.company;
      if (comp == null || comp.isEmpty) return;

      final engages = await fetchCOREnergyEngages();
      final match = engages.where((e) => e.name == comp || e.institutionName == comp);
      if (match.isEmpty) return;

      final target = match.first;
      final newVisit = COREnergyEngageVisit(
        successfulCall: !eng.unsuccessfulCall,
        unsuccessfulCall: eng.unsuccessfulCall,
        reasonForUnsuccessfulCall: eng.reasonForUnsuccessfulCall,
        decisionMakerNotAvailable: eng.decisionMakerOrResponsiblePersonNotAvailable,
        notes: 'Engagement visit by ${eng.salesRep ?? "Sales Rep"} on ${eng.dateAndTimeOfSalesAppointment ?? DateTime.now().toString()}',
      );

      final updatedVisits = List<COREnergyEngageVisit>.from(target.visits);
      updatedVisits.insert(0, newVisit);

      final updatedEngage = COREnergyEngage(
        name: target.name,
        institutionName: target.institutionName,
        hospitalClinic: target.hospitalClinic,
        region: target.region,
        province: target.province,
        cityMunicipality: target.cityMunicipality,
        barangayName: target.barangayName,
        streetAddress: target.streetAddress,
        salesRep: target.salesRep ?? eng.salesRep,
        leadsSource: target.leadsSource,
        leadsStatus: target.leadsStatus,
        ownershipNationality: target.ownershipNationality,
        latitude: (eng.latitude != null && eng.latitude != '0.0') ? eng.latitude : target.latitude,
        longitude: (eng.longitude != null && eng.longitude != '0.0') ? eng.longitude : target.longitude,
        locationAccuracy: (eng.locationAccuracy > 0.0) ? eng.locationAccuracy.toString() : target.locationAccuracy,
        contacts: target.contacts,
        visits: updatedVisits,
        actionItems: target.actionItems,
      );

      await updateCOREnergyEngage(target.name, updatedEngage);
    } catch (e) {
      print('Warning: Failed to cross-sync engagement to COREnergy Engage Copy: $e');
    }
  }

  /// Create a new COREnergy Engage record
  Future<COREnergyEngage> createCOREnergyEngage(COREnergyEngage engage) async {
    if (_isOffline) {
      return _saveCOREnergyEngageOffline(engage, isCreate: true);
    }

    await ensureCsrfToken();
    final targetDocTypes = ['COREnergy%20Engage%20Copy', 'COREnergy%20Engage'];
    final payload = engage.toJson();
    payload.remove('name'); // Always remove name for CREATE requests to let server assign/determine naming

    for (final dt in targetDocTypes) {
      try {
        final url = Uri.parse('$baseUrl/api/resource/$dt');
        var response = await http.post(
          url,
          headers: _headers,
          body: jsonEncode(payload),
        ).timeout(const Duration(seconds: 15));

        if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
          final reauthed = await _reAuthenticateSilently();
          if (reauthed) {
            response = await http.post(
              url,
              headers: _headers,
              body: jsonEncode(payload),
            ).timeout(const Duration(seconds: 15));
          }
        }

        if (response.statusCode == 200 || response.statusCode == 201) {
          final body = jsonDecode(response.body);
          final created = COREnergyEngage.fromJson(body['data']);
          await _saveDetailToCache(created.name, created);
          if (created.institutionName != null) {
            await _saveDetailToCache(created.institutionName!, created);
          }

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

          // Auto-sync visits to Engagement DocTypes
          _syncCOREnergyVisitsToEngagements(created);

          return created;
        }
      } catch (e) {
        print('Create COREnergy Engage on $dt failed: $e');
      }
    }

    print('Create online failed on both DocTypes, saving offline to SQLite...');
    return _saveCOREnergyEngageOffline(engage, isCreate: true);
  }

  /// Update an existing COREnergy Engage record
  Future<COREnergyEngage> updateCOREnergyEngage(String name, COREnergyEngage engage) async {
    if (_isOffline) {
      return _saveCOREnergyEngageOffline(engage, isCreate: false);
    }

    await ensureCsrfToken();
    final targetDocTypes = ['COREnergy%20Engage%20Copy', 'COREnergy%20Engage'];
    final payloadMap = engage.toJson();
    payloadMap.remove('name');

    for (final dt in targetDocTypes) {
      try {
        final url = Uri.parse('$baseUrl/api/resource/$dt/$name');
        var response = await http.put(
          url,
          headers: _headers,
          body: jsonEncode(payloadMap),
        ).timeout(const Duration(seconds: 15));

        if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
          final reauthed = await _reAuthenticateSilently();
          if (reauthed) {
            response = await http.put(
              url,
              headers: _headers,
              body: jsonEncode(payloadMap),
            ).timeout(const Duration(seconds: 15));
          }
        }

        if (response.statusCode == 200) {
          final body = jsonDecode(response.body);
          final updated = COREnergyEngage.fromJson(body['data']);
          await _saveDetailToCache(name, updated);
          if (updated.institutionName != null) {
            await _saveDetailToCache(updated.institutionName!, updated);
          }

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

          // Auto-sync visits to Engagement DocTypes
          _syncCOREnergyVisitsToEngagements(updated);

          return updated;
        } else if (response.statusCode == 404 || 
                   response.body.contains('DoesNotExistError') || 
                   response.body.contains('not found')) {
          print('COREnergy Engage document does not exist online for $name. Falling back to CREATE...');
          return await createCOREnergyEngage(engage);
        }
      } catch (e) {
        print('Update COREnergy Engage on $dt failed: $e');
      }
    }

    print('Update online failed on both DocTypes, saving offline to SQLite...');
    return _saveCOREnergyEngageOffline(engage, isCreate: false);
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

  /// Save engagement locally to SQLite and local disk cache when offline or if network dispatch fails
  Future<Engagement> _saveEngagementOffline(Engagement engagement, {required bool isCreate}) async {
    final tempId = (engagement.name != null && engagement.name!.isNotEmpty)
        ? engagement.name!
        : 'ENG-OFFLINE-${DateTime.now().millisecondsSinceEpoch}';

    final offlineEngagement = Engagement(
      name: tempId,
      unsuccessfulCall: engagement.unsuccessfulCall,
      reasonForUnsuccessfulCall: engagement.reasonForUnsuccessfulCall,
      company: (engagement.company != null && engagement.company!.toLowerCase() != 'corenergy' && engagement.company!.toLowerCase() != 'null')
          ? engagement.company
          : null,
      salesRep: (engagement.salesRep != null && engagement.salesRep!.isNotEmpty)
          ? engagement.salesRep
          : (loggedInEmail ?? 'jptan@profinsights.biz'),
      contact: engagement.contact,
      lastName: engagement.lastName,
      positionOrRole: engagement.positionOrRole,
      emailAddress: engagement.emailAddress,
      contactNumber: engagement.contactNumber,
      dateAndTimeOfSalesAppointment: (engagement.dateAndTimeOfSalesAppointment != null && engagement.dateAndTimeOfSalesAppointment!.isNotEmpty)
          ? engagement.dateAndTimeOfSalesAppointment
          : DateTime.now().toString().substring(0, 19),
      decisionMakerOrResponsiblePersonNotAvailable: engagement.decisionMakerOrResponsiblePersonNotAvailable,
      latitude: (engagement.latitude != null && engagement.latitude!.isNotEmpty) ? engagement.latitude : '0.0',
      longitude: (engagement.longitude != null && engagement.longitude!.isNotEmpty) ? engagement.longitude : '0.0',
      locationAccuracy: engagement.locationAccuracy,
      picture: engagement.picture,
      creation: engagement.creation ?? DateTime.now().toIso8601String(),
      modified: DateTime.now().toIso8601String(),
    );

    // Save to SQLite pending queue
    try {
      final action = isCreate ? 'ENG_CREATE' : 'ENG_UPDATE';
      await DbHelper.insertPendingRaw(tempId, jsonEncode(offlineEngagement.toJson()), action);
    } catch (e) {
      print('Error saving pending engagement to SQLite: $e');
    }

    // Immediately update local cache list in engagements_cache.json
    final cache = await _readFromCache('engagements_cache.json');
    List<dynamic> cachedList = [];
    if (cache != null) {
      try {
        cachedList = jsonDecode(cache);
      } catch (_) {}
    }
    final existingIdx = cachedList.indexWhere((item) => item['name'] == tempId);
    if (existingIdx != -1) {
      cachedList[existingIdx] = offlineEngagement.toJson();
    } else {
      cachedList.insert(0, offlineEngagement.toJson());
    }
    await _writeToCache('engagements_cache.json', jsonEncode(cachedList));
    notifyListeners();

    return offlineEngagement;
  }

  /// Create a new engagement record online with automatic offline SQLite fallback
  Future<Engagement> createEngagement(Engagement engagement) async {
    if (_isOffline) {
      return await _saveEngagementOffline(engagement, isCreate: true);
    }

    final targetDocType = engagement.unsuccessfulCall
        ? 'Unsuccessful%20COREnergy%20Engagement'
        : 'Successful%20COREnergy%20Engagement';

    final payload = engagement.toJson();
    // Defensive sanitization: resolve valid institution ID to prevent 417 LinkValidationError
    if (payload['company'] != null) {
      final comp = payload['company'].toString().trim();
      final resolvedId = await _resolveInstitutionId(comp);
      if (resolvedId != null) {
        payload['company'] = resolvedId;
      } else {
        payload.remove('company');
      }
    }
    if (payload['latitude'] == null || payload['latitude'].toString().isEmpty) {
      payload['latitude'] = '0.0';
    }
    if (payload['longitude'] == null || payload['longitude'].toString().isEmpty) {
      payload['longitude'] = '0.0';
    }
    if (!engagement.unsuccessfulCall) {
      payload.remove('reason_for_unsuccessful_call');
    }
    if (payload['sales_rep'] == null || payload['sales_rep'].toString().trim().isEmpty) {
      payload['sales_rep'] = loggedInEmail ?? 'jptan@profinsights.biz';
    }
    if (payload['date_and_time_of_sales_appointment'] == null || payload['date_and_time_of_sales_appointment'].toString().trim().isEmpty) {
      payload['date_and_time_of_sales_appointment'] = DateTime.now().toString().substring(0, 19);
    }

    try {
      await ensureCsrfToken();
      final url = Uri.parse('$baseUrl/api/resource/$targetDocType');
      var response = await http.post(
        url,
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
        final reauthed = await _reAuthenticateSilently();
        if (reauthed) {
          response = await http.post(
            url,
            headers: _headers,
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 15));
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        final created = Engagement.fromJson(Map<String, dynamic>.from(body['data']));

        // Update local engagements cache list
        final cache = await _readFromCache('engagements_cache.json');
        List<dynamic> cachedList = [];
        if (cache != null) {
          try {
            cachedList = jsonDecode(cache);
          } catch (_) {}
        }
        cachedList.insert(0, created.toJson());
        await _writeToCache('engagements_cache.json', jsonEncode(cachedList));
        notifyListeners();

        // Cross-sync this engagement into COREnergy Engage Copy visits
        _syncEngagementToCOREnergyEngageCopy(created);

        return created;
      } else {
        print('Create engagement server error: ${response.statusCode} - ${response.body}. Queueing offline...');
        return await _saveEngagementOffline(engagement, isCreate: true);
      }
    } catch (e) {
      print('Create engagement network exception: $e. Queueing offline...');
      return await _saveEngagementOffline(engagement, isCreate: true);
    }
  }

  /// Update an existing engagement record online with automatic offline SQLite fallback
  Future<Engagement> updateEngagement(String name, Engagement engagement) async {
    if (_isOffline) {
      return await _saveEngagementOffline(engagement, isCreate: false);
    }

    final targetDocType = engagement.unsuccessfulCall
        ? 'Unsuccessful%20COREnergy%20Engagement'
        : 'Successful%20COREnergy%20Engagement';

    final payload = engagement.toJson();
    payload.remove('name');
    if (payload['company'] != null) {
      final comp = payload['company'].toString().trim();
      final resolvedId = await _resolveInstitutionId(comp);
      if (resolvedId != null) {
        payload['company'] = resolvedId;
      } else {
        payload.remove('company');
      }
    }

    try {
      await ensureCsrfToken();
      final url = Uri.parse('$baseUrl/api/resource/$targetDocType/${Uri.encodeComponent(name)}');
      var response = await http.put(
        url,
        headers: _headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if ((response.statusCode == 401 || response.statusCode == 403) && loggedInEmail != null) {
        final reauthed = await _reAuthenticateSilently();
        if (reauthed) {
          response = await http.put(
            url,
            headers: _headers,
            body: jsonEncode(payload),
          ).timeout(const Duration(seconds: 15));
        }
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final updated = Engagement.fromJson(Map<String, dynamic>.from(body['data']));

        // Update local engagements cache list
        final cache = await _readFromCache('engagements_cache.json');
        if (cache != null) {
          try {
            final List<dynamic> cachedList = jsonDecode(cache);
            final idx = cachedList.indexWhere((item) => item['name'] == name);
            if (idx != -1) {
              cachedList[idx] = updated.toJson();
            } else {
              cachedList.insert(0, updated.toJson());
            }
            await _writeToCache('engagements_cache.json', jsonEncode(cachedList));
          } catch (_) {}
        }
        notifyListeners();

        // Cross-sync this engagement into COREnergy Engage Copy visits
        _syncEngagementToCOREnergyEngageCopy(updated);

        return updated;
      } else {
        print('Update engagement server error: ${response.statusCode} - ${response.body}. Queueing offline...');
        return await _saveEngagementOffline(engagement, isCreate: false);
      }
    } catch (e) {
      print('Update engagement network exception: $e. Queueing offline...');
      return await _saveEngagementOffline(engagement, isCreate: false);
    }
  }

  /// Retrieve list of HCP/Doctors with 24/7 cache fallback
  Future<List<Hcp>> fetchDoctors() async {
    return hcps.list(limit: 200);
  }

  /// Fetch full details of a specific Doctor (HCP) including child tables
  Future<Hcp> fetchDoctorDetail(String name) async {
    return hcps.get(name);
  }

  /// Create a new HCP/Doctor record
  Future<Hcp> createDoctor(Hcp hcp) async {
    return hcps.create(hcp);
  }

  /// Update an existing HCP/Doctor record
  Future<Hcp> updateDoctor(String name, Hcp hcp) async {
    return hcps.update(name, hcp);
  }

  /// Retrieve list of HCP Profile Submissions with 24/7 cache fallback
  Future<List<HcpProfileSubmission>> fetchSubmissions() async {
    return submissions.list(limit: 100);
  }

  /// Create a new HCP Profile Submission record
  Future<HcpProfileSubmission> createSubmission(HcpProfileSubmission submission) async {
    return submissions.create(submission);
  }

  /// Retrieve list of Specializations with 24/7 cache fallback
  Future<List<Specialization>> fetchSpecializations() async {
    return specializations.list(limit: 500);
  }

  /// Retrieve list of PSGC Locations
  Future<List<PsgcLocation>> fetchPsgcLocations() async {
    if (_isOffline) {
      final cache = await _readFromCache('psgc_locations_cache.json');
      if (cache != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cache);
          if (dataList.isNotEmpty) {
            return dataList.map((json) => PsgcLocation.fromJson(json)).toList();
          }
        } catch (_) {}
      }
      return _buildFallbackPsgcLocations();
    }
    final url = Uri.parse(
      '$baseUrl/api/resource/PSGC%20Location?fields=["name","location_label","location_type","parent_psgc_location","psgc_code","is_group"]&filters=[["location_type","in",["Region","Province","City"]]]&limit=3000',
    );
    try {
      final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        if (dataList.isNotEmpty) {
          await _writeToCache('psgc_locations_cache.json', jsonEncode(dataList));
          return dataList.map((json) => PsgcLocation.fromJson(json)).toList();
        }
      }
    } catch (e) {
      print('Fetch PSGC locations error: $e');
    }

    final cache = await _readFromCache('psgc_locations_cache.json');
    if (cache != null) {
      try {
        final List<dynamic> dataList = jsonDecode(cache);
        if (dataList.isNotEmpty) {
          return dataList.map((json) => PsgcLocation.fromJson(json)).toList();
        }
      } catch (_) {}
    }
    return _buildFallbackPsgcLocations();
  }

  List<PsgcLocation> _buildFallbackPsgcLocations() {
    return [
      PsgcLocation(name: 'NCR', locationLabel: 'NCR', locationType: 'Region', psgcCode: '1300000000'),
      PsgcLocation(name: 'CALABARZON', locationLabel: 'CALABARZON', locationType: 'Region', psgcCode: '0400000000'),
      PsgcLocation(name: 'Central Luzon', locationLabel: 'Central Luzon', locationType: 'Region', psgcCode: '0300000000'),
      PsgcLocation(name: 'Central Visayas', locationLabel: 'Central Visayas', locationType: 'Region', psgcCode: '0700000000'),
      PsgcLocation(name: 'Davao Region', locationLabel: 'Davao Region', locationType: 'Region', psgcCode: '1100000000'),
      PsgcLocation(name: 'Laguna', locationLabel: 'Laguna', locationType: 'Province', psgcCode: '0403400000'),
      PsgcLocation(name: 'Cavite', locationLabel: 'Cavite', locationType: 'Province', psgcCode: '0402100000'),
      PsgcLocation(name: 'Metro Manila-Manila', locationLabel: 'Metro Manila-Manila', locationType: 'Province', psgcCode: '1376000000'),
      PsgcLocation(name: 'Santa Rosa City', locationLabel: 'Santa Rosa City', locationType: 'City', psgcCode: '0403428000'),
      PsgcLocation(name: 'Biñan City', locationLabel: 'Biñan City', locationType: 'City', psgcCode: '0403403000'),
      PsgcLocation(name: 'Cabuyao City', locationLabel: 'Cabuyao City', locationType: 'City', psgcCode: '0403404000'),
      PsgcLocation(name: 'Calamba City', locationLabel: 'Calamba City', locationType: 'City', psgcCode: '0403405000'),
    ];
  }

  /// Retrieve active Survey Templates with 24/7 resilience and cache fallback
  Future<List<HcpSurveyTemplate>> fetchSurveyTemplates() async {
    const cacheKey = 'survey_templates_cache.json';
    if (_isOffline) {
      final cached = await _readFromCache(cacheKey);
      if (cached != null) {
        try {
          final List<dynamic> list = jsonDecode(cached);
          return list.map((j) => HcpSurveyTemplate.fromJson(Map<String, dynamic>.from(j))).toList();
        } catch (_) {}
      }
      return [];
    }

    try {
      final templates = await surveyTemplates.list(
        fields: ["name", "template_name", "is_active", "account_or_program", "description"],
        filters: [["is_active", "=", 1]],
      );
      List<HcpSurveyTemplate> fullTemplates = [];
      for (var t in templates) {
        try {
          final full = await surveyTemplates.get(t.name);
          fullTemplates.add(full);
        } catch (_) {
          fullTemplates.add(t);
        }
      }
      if (fullTemplates.isNotEmpty) {
        await _writeToCache(cacheKey, jsonEncode(fullTemplates.map((t) => t.toJson()).toList()));
      }
      return fullTemplates;
    } catch (e) {
      print('Fetch survey templates error: $e');
      final cached = await _readFromCache(cacheKey);
      if (cached != null) {
        try {
          final List<dynamic> list = jsonDecode(cached);
          return list.map((j) => HcpSurveyTemplate.fromJson(Map<String, dynamic>.from(j))).toList();
        } catch (_) {}
      }
      return [];
    }
  }

  /// Retrieve list of HCP Types (used as Link values for hcp_type field) with 24/7 resilience
  Future<List<HcpType>> fetchHcpTypes() async {
    return hcpTypes.list(limit: 50);
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

  String _sanitizeCacheKey(String key) {
    return key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  /// Fetch list of records of this DocType with 15s timeout, silent retry, and local cache fallback
  Future<List<T>> list({
    List<String>? fields,
    List<dynamic>? filters,
    int? limit,
    int? limitStart,
    String? orderBy,
  }) async {
    final cacheKey = 'frappe_${_sanitizeCacheKey(docType)}_list.json';

    // If currently offline, immediately attempt to serve from local disk cache
    if (_api.isOffline) {
      final cached = await _api._readFromCache(cacheKey);
      if (cached != null) {
        try {
          final List<dynamic> dataList = jsonDecode(cached);
          return dataList.map((json) => fromJson(Map<String, dynamic>.from(json))).toList();
        } catch (e) {
          print('Error parsing offline cache for $docType: $e');
        }
      }
      return [];
    }

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
      var response = await http.get(uri, headers: _api._headers).timeout(const Duration(seconds: 15));

      // Auto-reauthenticate on expired session
      if ((response.statusCode == 401 || response.statusCode == 403) && _api.loggedInEmail != null) {
        final reauthed = await _api._reAuthenticateSilently();
        if (reauthed) {
          response = await http.get(uri, headers: _api._headers).timeout(const Duration(seconds: 15));
        }
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final List<dynamic> dataList = body['data'] ?? [];
        await _api._writeToCache(cacheKey, jsonEncode(dataList));
        return dataList.map((json) => fromJson(Map<String, dynamic>.from(json))).toList();
      } else {
        print('FrappeRepository.list server returned ${response.statusCode} for $docType');
      }
    } catch (e) {
      print('FrappeRepository.list network error on $docType: $e');
    }

    // Fallback: Read from local cache if network call fails or times out
    final cached = await _api._readFromCache(cacheKey);
    if (cached != null) {
      try {
        final List<dynamic> dataList = jsonDecode(cached);
        return dataList.map((json) => fromJson(Map<String, dynamic>.from(json))).toList();
      } catch (_) {}
    }

    return [];
  }

  /// Fetch details of a single record by its name (ID), including its nested child tables
  Future<T> get(String name) async {
    final cacheKey = 'frappe_${_sanitizeCacheKey(docType)}_${_sanitizeCacheKey(name)}_detail.json';

    if (_api.isOffline) {
      final cached = await _api._readFromCache(cacheKey);
      if (cached != null) {
        try {
          return fromJson(Map<String, dynamic>.from(jsonDecode(cached)));
        } catch (_) {}
      }
    }

    final uri = Uri.parse('${_api.baseUrl}/api/resource/${Uri.encodeComponent(docType)}/${Uri.encodeComponent(name)}');
    try {
      var response = await http.get(uri, headers: _api._headers).timeout(const Duration(seconds: 15));

      // Auto-reauthenticate on expired session
      if ((response.statusCode == 401 || response.statusCode == 403) && _api.loggedInEmail != null) {
        final reauthed = await _api._reAuthenticateSilently();
        if (reauthed) {
          response = await http.get(uri, headers: _api._headers).timeout(const Duration(seconds: 15));
        }
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'];
        await _api._writeToCache(cacheKey, jsonEncode(data));
        return fromJson(Map<String, dynamic>.from(data));
      }
    } catch (e) {
      print('FrappeRepository.get network error on $docType ($name): $e');
    }

    // Fallback to cached detail
    final cached = await _api._readFromCache(cacheKey);
    if (cached != null) {
      try {
        return fromJson(Map<String, dynamic>.from(jsonDecode(cached)));
      } catch (_) {}
    }

    throw Exception('Failed to load detail for $docType ($name)');
  }

  /// Create a new record with nested child table arrays
  Future<T> create(T item) async {
    await _api.ensureCsrfToken();
    final uri = Uri.parse('${_api.baseUrl}/api/resource/${Uri.encodeComponent(docType)}');
    try {
      var response = await http.post(
        uri,
        headers: _api._headers,
        body: jsonEncode(toJson(item)),
      ).timeout(const Duration(seconds: 15));

      if ((response.statusCode == 401 || response.statusCode == 403) && _api.loggedInEmail != null) {
        final reauthed = await _api._reAuthenticateSilently();
        if (reauthed) {
          response = await http.post(
            uri,
            headers: _api._headers,
            body: jsonEncode(toJson(item)),
          ).timeout(const Duration(seconds: 15));
        }
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final body = jsonDecode(response.body);
        final created = fromJson(Map<String, dynamic>.from(body['data']));
        final name = body['data']['name'];
        if (name != null) {
          final cacheKey = 'frappe_${_sanitizeCacheKey(docType)}_${_sanitizeCacheKey(name.toString())}_detail.json';
          await _api._writeToCache(cacheKey, jsonEncode(body['data']));
        }
        return created;
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
    await _api.ensureCsrfToken();
    final uri = Uri.parse('${_api.baseUrl}/api/resource/${Uri.encodeComponent(docType)}/${Uri.encodeComponent(name)}');
    try {
      var response = await http.put(
        uri,
        headers: _api._headers,
        body: jsonEncode(toJson(item)),
      ).timeout(const Duration(seconds: 15));

      if ((response.statusCode == 401 || response.statusCode == 403) && _api.loggedInEmail != null) {
        final reauthed = await _api._reAuthenticateSilently();
        if (reauthed) {
          response = await http.put(
            uri,
            headers: _api._headers,
            body: jsonEncode(toJson(item)),
          ).timeout(const Duration(seconds: 15));
        }
      }

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final updated = fromJson(Map<String, dynamic>.from(body['data']));
        final cacheKey = 'frappe_${_sanitizeCacheKey(docType)}_${_sanitizeCacheKey(name)}_detail.json';
        await _api._writeToCache(cacheKey, jsonEncode(body['data']));
        return updated;
      } else {
        throw Exception('Failed to update $docType ($name): ${response.body}');
      }
    } catch (e) {
      print('FrappeRepository.update error on $docType: $e');
      rethrow;
    }
  }
}


