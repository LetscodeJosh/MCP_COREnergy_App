import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../models/engagement.dart';
import '../models/lookup_models.dart';
import '../services/api_service.dart';

class DetailScreen extends StatefulWidget {
  final Engagement? engagement;
  final List<Institution> institutions;
  final List<String> salesReps;

  const DetailScreen({
    Key? key,
    this.engagement,
    required this.institutions,
    required this.salesReps,
  }) : super(key: key);

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _formKey = GlobalKey<FormState>();
  
  // Form State
  bool _unsuccessfulCall = false;
  String? _reasonForUnsuccessfulCall;
  String? _selectedCompany;
  Institution? _selectedInstitutionObject;
  String? _selectedSalesRep;
  
  final _contactFirstNameController = TextEditingController();
  final _contactLastNameController = TextEditingController();
  final _positionOrRoleController = TextEditingController();
  final _emailAddressController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _dateTimeSalesController = TextEditingController();
  
  bool _decisionMakerNotAvailable = false;
  
  String? _latitude;
  String? _longitude;
  
  File? _imageFile;
  final _picker = ImagePicker();
  bool _isSaving = false;
  bool _isLocating = false;
  String _selectedCountryCode = '+63';

  final List<String> _unsuccessfulReasons = [
    'Company moved to different address',
    'Prior appointment or letter needed',
    'Decision maker not available',
    'Closed / No longer in operations',
    'Refused to entertain',
    'Other'
  ];

  @override
  void initState() {
    super.initState();
    _populateFields();
  }

  void _populateFields() {
    final item = widget.engagement;
    if (item != null) {
      _unsuccessfulCall = item.unsuccessfulCall;
      _reasonForUnsuccessfulCall = item.reasonForUnsuccessfulCall;
      _selectedCompany = item.company;
      if (item.company != null) {
        _selectedInstitutionObject = widget.institutions.firstWhere(
          (i) => i.name == item.company,
          orElse: () => Institution(name: item.company!, institutionName: item.company!),
        );
      }
      _selectedSalesRep = item.salesRep;
      _contactFirstNameController.text = item.contact ?? '';
      _contactLastNameController.text = item.lastName ?? '';
      _positionOrRoleController.text = item.positionOrRole ?? '';
      _emailAddressController.text = item.emailAddress ?? '';
      _contactNumberController.text = item.contactNumber ?? '';
      _decisionMakerNotAvailable = item.decisionMakerOrResponsiblePersonNotAvailable;
      _latitude = item.latitude;
      _longitude = item.longitude;
      
      final phone = item.contactNumber ?? '';
      if (phone.startsWith('+')) {
        for (var code in ['+63', '+1', '+65', '+60']) {
          if (phone.startsWith(code)) {
            _selectedCountryCode = code;
            _contactNumberController.text = phone.substring(code.length);
            break;
          }
        }
        if (_contactNumberController.text.isEmpty) {
          _contactNumberController.text = phone;
        }
      } else {
        _contactNumberController.text = phone;
      }
      
      // Formatting datetime to "MM-DD-YYYY HH:mm:ss" for input
      if (item.dateAndTimeOfSalesAppointment != null) {
        final raw = item.dateAndTimeOfSalesAppointment!;
        try {
          final year = raw.substring(0, 4);
          final month = raw.substring(5, 7);
          final day = raw.substring(8, 10);
          final time = raw.substring(11);
          _dateTimeSalesController.text = "$month-$day-$year $time";
        } catch (_) {
          _dateTimeSalesController.text = raw;
        }
      }
    }
  }

  Future<void> _getImage() async {
    try {
      final pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
      );
      if (pickedFile != null) {
        setState(() {
          _imageFile = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to take photo: $e')),
      );
    }
  }

  Future<void> _fetchGPS() async {
    setState(() {
      _isLocating = true;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      setState(() {
        _latitude = position.latitude.toStringAsFixed(6);
        _longitude = position.longitude.toStringAsFixed(6);
        _isLocating = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GPS coordinates saved successfully.')),
      );
    } catch (e) {
      setState(() {
        // Fallback to random test environment coords close to Laguna
        final offsetLat = (DateTime.now().millisecond / 1000 - 0.5) * 0.05;
        final offsetLng = (DateTime.now().microsecond / 1000000 - 0.5) * 0.05;
        _latitude = (14.3129 + offsetLat).toStringAsFixed(6);
        _longitude = (121.1009 + offsetLng).toStringAsFixed(6);
        _isLocating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('GPS failure ($e). Seeding mockup location.')),
      );
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

    setState(() {
      _isSaving = true;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);

    // Parse DateTime to ERPNext format (YYYY-MM-DD HH:mm:ss)
    String? formattedDateTime;
    if (_dateTimeSalesController.text.isNotEmpty) {
      try {
        final text = _dateTimeSalesController.text;
        final month = text.substring(0, 2);
        final day = text.substring(3, 5);
        final year = text.substring(6, 10);
        final time = text.substring(11);
        formattedDateTime = "$year-$month-$day $time";
      } catch (_) {
        formattedDateTime = _dateTimeSalesController.text;
      }
    }

    final payload = Engagement(
      name: widget.engagement?.name,
      unsuccessfulCall: _unsuccessfulCall,
      reasonForUnsuccessfulCall: _unsuccessfulCall ? _reasonForUnsuccessfulCall : '',
      company: _selectedCompany,
      salesRep: _selectedSalesRep,
      contact: _contactFirstNameController.text.trim().isEmpty ? null : _contactFirstNameController.text.trim(),
      lastName: _contactLastNameController.text.trim().isEmpty ? null : _contactLastNameController.text.trim(),
      positionOrRole: _positionOrRoleController.text.trim().isEmpty ? null : _positionOrRoleController.text.trim(),
      emailAddress: _emailAddressController.text.trim().isEmpty ? null : _emailAddressController.text.trim(),
      contactNumber: _contactNumberController.text.trim().isEmpty ? null : '$_selectedCountryCode${_contactNumberController.text.trim()}',
      dateAndTimeOfSalesAppointment: formattedDateTime,
      decisionMakerOrResponsiblePersonNotAvailable: _decisionMakerNotAvailable,
      latitude: _latitude,
      longitude: _longitude,
      picture: _imageFile != null ? '/private/files/${_imageFile!.path.split('/').last}' : widget.engagement?.picture,
    );

    try {
      if (widget.engagement != null) {
        await apiService.updateEngagement(widget.engagement!.name!, payload);
      } else {
        await apiService.createEngagement(payload);
      }
      
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Engagement submitted successfully'),
            backgroundColor: Color(0xFF30D158),
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.engagement != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(isEdit ? widget.engagement!.name! : 'New Profiling'),
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
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Details Header Card
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
                  Text(
                    isEdit ? 'RECORD ID' : 'NEW CALL REGISTRATION',
                    style: const TextStyle(color: Color(0xFF636366), fontFamily: 'monospace', fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isEdit ? widget.engagement!.name! : 'Create COREnergy Log',
                    style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Checkbox: Unsuccessful Call
            _buildCheckboxTile(
              value: _unsuccessfulCall,
              label: 'Unsuccessful Call',
              onChanged: (val) {
                setState(() {
                  _unsuccessfulCall = val ?? false;
                  if (!_unsuccessfulCall) _reasonForUnsuccessfulCall = null;
                });
              },
            ),
            const SizedBox(height: 16),

            // Reason for Unsuccessful Call (Dynamic visibility)
            if (_unsuccessfulCall) ...[
              const Text('REASON FOR UNSUCCESSFUL CALL', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildDropdownField<String>(
                value: _reasonForUnsuccessfulCall,
                hint: 'Select Reason...',
                items: _unsuccessfulReasons,
                onChanged: (val) {
                  setState(() {
                    _reasonForUnsuccessfulCall = val;
                  });
                },
                validator: (val) => val == null ? 'Please select a reason' : null,
              ),
              const SizedBox(height: 16),
            ],

            // Company Search Selector
            const Text('COMPANY / INSTITUTION *', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showSearchableInstitutionPicker,
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
                        _selectedCompany == null
                            ? 'Tap to select Company...'
                            : (() {
                                if (_selectedInstitutionObject != null && _selectedInstitutionObject!.name == _selectedCompany) {
                                  return '${_selectedInstitutionObject!.name} - ${_selectedInstitutionObject!.institutionName}';
                                }
                                final match = widget.institutions.firstWhere(
                                  (i) => i.name == _selectedCompany,
                                  orElse: () => Institution(name: _selectedCompany!, institutionName: _selectedCompany!),
                                );
                                return '${match.name} - ${match.institutionName}';
                              })(),
                        style: TextStyle(
                          color: _selectedCompany == null ? const Color(0xFF8E8E93) : const Color(0xFF1C1C1E),
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Color(0xFF8E8E93)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Picture Uploader Area
            const Text('PICTURE', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _getImage,
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD1D1D6)),
                ),
                child: _imageFile != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.file(_imageFile!, fit: BoxFit.cover, width: double.infinity),
                      )
                    : widget.engagement?.picture != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.network(
                              widget.engagement!.picture!.startsWith('http')
                                  ? widget.engagement!.picture!
                                  : 'https://dev.pmii-marketing.com${widget.engagement!.picture}',
                              fit: BoxFit.cover,
                              width: double.infinity,
                            ),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.camera_alt_outlined, color: Color(0xFF8E8E93), size: 36),
                              SizedBox(height: 10),
                              Text('Attach geotagged photo', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 13)),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 16),

            // Location Coordinates widget
            const Text('LOCATION COORDINATES', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isLocating ? null : _fetchGPS,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0056B3),
                side: const BorderSide(color: Color(0xFFD1D1D6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: _isLocating
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF0056B3)),
                    )
                  : const Icon(Icons.location_on_outlined, color: Color(0xFF0056B3), size: 18),
              label: Text(_isLocating ? 'Fetching GPS...' : 'Get Current Location'),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFD1D1D6)),
              ),
              child: Row(
                children: [
                  Expanded(child: Text('Lat: ${_latitude ?? "Not set"}', style: const TextStyle(color: Color(0xFF1C1C1E), fontFamily: 'monospace', fontSize: 13))),
                  Expanded(child: Text('Lng: ${_longitude ?? "Not set"}', style: const TextStyle(color: Color(0xFF1C1C1E), fontFamily: 'monospace', fontSize: 13))),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Sales Rep
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

            // Contact First Name
            _buildInputField(
              controller: _contactFirstNameController,
              label: 'First Name',
              hint: 'Contact First Name',
            ),
            const SizedBox(height: 16),

            // Contact Last Name
            _buildInputField(
              controller: _contactLastNameController,
              label: 'Last Name',
              hint: 'Contact Last Name',
            ),
            const SizedBox(height: 16),

            // Position or Role
            _buildInputField(
              controller: _positionOrRoleController,
              label: 'Position or Role',
              hint: 'e.g. Procurement, MD',
            ),
            const SizedBox(height: 16),

            // Email Address
            _buildInputField(
              controller: _emailAddressController,
              label: 'Email Address',
              hint: 'name@company.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),

            // Contact Number
            const Text('CONTACT NUMBER', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _contactNumberController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
              decoration: InputDecoration(
                prefixIcon: Container(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCountryCode,
                      dropdownColor: Colors.white,
                      style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                      items: const [
                        DropdownMenuItem(value: '+63', child: Text('🇵🇭 +63')),
                        DropdownMenuItem(value: '+1', child: Text('🇺🇸 +1')),
                        DropdownMenuItem(value: '+65', child: Text('🇸🇬 +65')),
                        DropdownMenuItem(value: '+60', child: Text('🇲🇾 +60')),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedCountryCode = val;
                          });
                        }
                      },
                    ),
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                filled: true,
                fillColor: Colors.white,
                hintText: '9170000000',
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
            const SizedBox(height: 16),

            // Date and Time of Sales Appointment
            const Text('DATE AND TIME OF SALES APPOINTMENT', style: TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showErpnextDateTimePicker(context),
              child: AbsorbPointer(
                child: TextFormField(
                  controller: _dateTimeSalesController,
                  style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'MM-DD-YYYY HH:mm:ss',
                    hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
                    suffixIcon: const Icon(Icons.calendar_today, color: Color(0xFF8E8E93), size: 16),
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
              ),
            ),
            const Text('Timezone: Asia/Manila', style: TextStyle(color: Color(0xFF8E8E93), fontSize: 11), textAlign: TextAlign.right),
            const SizedBox(height: 16),

            // Decision Maker
            _buildCheckboxTile(
              value: _decisionMakerNotAvailable,
              label: 'Decision maker or responsible person not available',
              onChanged: (val) {
                setState(() {
                  _decisionMakerNotAvailable = val ?? false;
                });
              },
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxTile({
    required bool value,
    required String label,
    required ValueChanged<bool?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD1D1D6)),
      ),
      child: CheckboxListTile(
        title: Text(label, style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14)),
        value: value,
        activeColor: const Color(0xFF0056B3),
        checkColor: Colors.white,
        onChanged: onChanged,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required T? value,
    required String hint,
    required List<T> items,
    String Function(T)? itemLabelBuilder,
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
              itemLabelBuilder != null ? itemLabelBuilder(item) : item.toString(),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF1C1C1E)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: const TextStyle(color: Color(0xFF636366), fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
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

  void _showSearchableInstitutionPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return SearchableInstitutionPicker(
          institutions: widget.institutions,
          onSelected: (inst) {
            setState(() {
              _selectedCompany = inst.name;
              _selectedInstitutionObject = inst;
            });
          },
        );
      },
    );
  }

  Future<void> _showErpnextDateTimePicker(BuildContext context) async {
    DateTime selectedDate = DateTime.now();
    if (_dateTimeSalesController.text.isNotEmpty) {
      try {
        final text = _dateTimeSalesController.text;
        final month = int.parse(text.substring(0, 2));
        final day = int.parse(text.substring(3, 5));
        final year = int.parse(text.substring(6, 10));
        final hour = int.parse(text.substring(11, 13));
        final minute = int.parse(text.substring(14, 16));
        final second = int.parse(text.substring(17, 19));
        selectedDate = DateTime(year, month, day, hour, minute, second);
      } catch (_) {}
    }

    final DateTime? result = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext context) {
        return _ErpnextDateTimePickerDialog(initialDateTime: selectedDate);
      },
    );

    if (result != null && mounted) {
      setState(() {
        final pad = (int n) => n.toString().padLeft(2, '0');
        _dateTimeSalesController.text =
            "${pad(result.month)}-${pad(result.day)}-${result.year} ${pad(result.hour)}:${pad(result.minute)}:${pad(result.second)}";
      });
    }
  }
}

class SearchableInstitutionPicker extends StatefulWidget {
  final List<Institution> institutions;
  final Function(Institution) onSelected;

  const SearchableInstitutionPicker({
    Key? key,
    required this.institutions,
    required this.onSelected,
  }) : super(key: key);

  @override
  State<SearchableInstitutionPicker> createState() => _SearchableInstitutionPickerState();
}

class _SearchableInstitutionPickerState extends State<SearchableInstitutionPicker> {
  List<Institution> _filteredList = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _filteredList = widget.institutions;
  }

  void _filter(String query) {
    setState(() {
      _searchQuery = query;
      _filteredList = widget.institutions.where((inst) {
        final matchesName = inst.institutionName.toLowerCase().contains(query.toLowerCase());
        final matchesId = inst.name.toLowerCase().contains(query.toLowerCase());
        return matchesName || matchesId;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
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
            'Select Company / Institution',
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.business, size: 48, color: Color(0xFFC7C7CC)),
                          const SizedBox(height: 8),
                          Text(
                            'No matching institutions found for "$_searchQuery".',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                  )
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
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                  builder: (ctx) {
                    return QuickEntryInstitutionSheet(
                      initialName: _searchQuery,
                      onSaved: (newInst) {
                        widget.onSelected(newInst);
                        Navigator.pop(context); // Close SearchableInstitutionPicker
                      },
                    );
                  },
                );
              },
              icon: const Icon(Icons.add, color: Color(0xFF007AFF)),
              label: const Text(
                'Create a New Institution',
                style: TextStyle(color: Color(0xFF007AFF), fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFF007AFF)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class QuickEntryInstitutionSheet extends StatefulWidget {
  final String initialName;
  final Function(Institution) onSaved;

  const QuickEntryInstitutionSheet({
    Key? key,
    required this.initialName,
    required this.onSaved,
  }) : super(key: key);

  @override
  State<QuickEntryInstitutionSheet> createState() => _QuickEntryInstitutionSheetState();
}

class _QuickEntryInstitutionSheetState extends State<QuickEntryInstitutionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _streetController = TextEditingController();
  
  bool _isLoadingLocs = false;
  bool _isSaving = false;
  List<PsgcLocation> _psgcLocations = [];
  
  List<GeographicUnit> _regions = [];
  List<GeographicUnit> _provinces = [];
  List<GeographicUnit> _cities = [];

  GeographicUnit? _selectedRegion;
  GeographicUnit? _selectedProvince;
  GeographicUnit? _selectedCity;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.initialName;
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    setState(() {
      _isLoadingLocs = true;
    });
    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final locs = await apiService.fetchPsgcLocations();
      setState(() {
        _psgcLocations = locs;
        _regions = locs
            .where((l) => l.locationType == 'Region')
            .map((l) => GeographicUnit(l.locationLabel, l.name))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        _isLoadingLocs = false;
      });
    } catch (e) {
      print('Error loading PSGC locations: $e');
      setState(() {
        _isLoadingLocs = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _streetController.dispose();
    super.dispose();
  }

  void _onRegionChanged(GeographicUnit? reg) {
    setState(() {
      _selectedRegion = reg;
      _selectedProvince = null;
      _selectedCity = null;
      _provinces = [];
      _cities = [];
      
      if (reg != null && _psgcLocations.isNotEmpty) {
        _provinces = _psgcLocations
            .where((l) => l.locationType == 'Province' && l.parentPsgcLocation == reg.code)
            .map((l) => GeographicUnit(l.locationLabel, l.name))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      }
    });
  }

  void _onProvinceChanged(GeographicUnit? prov) {
    setState(() {
      _selectedProvince = prov;
      _selectedCity = null;
      _cities = [];
      
      if (prov != null && _psgcLocations.isNotEmpty) {
        _cities = _psgcLocations
            .where((l) => l.locationType == 'City' && l.parentPsgcLocation == prov.code)
            .map((l) => GeographicUnit(l.locationLabel, l.name))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isSaving = true;
    });

    final apiService = Provider.of<ApiService>(context, listen: false);

    final newEngage = COREnergyEngage(
      name: '',
      institutionName: _nameController.text.trim(),
      hospitalClinic: _nameController.text.trim(),
      region: _selectedRegion?.code,
      province: _selectedProvince?.code,
      cityMunicipality: _selectedCity?.code,
      streetAddress: _streetController.text.trim().isEmpty ? null : _streetController.text.trim(),
      salesRep: apiService.loggedInEmail ?? 'jptan@profinsights.biz',
    );

    try {
      final createdEngage = await apiService.createCOREnergyEngage(newEngage);
      
      final createdInst = Institution(
        name: createdEngage.name,
        institutionName: createdEngage.hospitalClinic ?? createdEngage.institutionName ?? _nameController.text.trim(),
        regionName: createdEngage.region,
        provinceName: createdEngage.province,
        cityMunicipality: createdEngage.cityMunicipality,
        streetAddress: createdEngage.streetAddress,
      );

      setState(() {
        _isSaving = false;
      });
      widget.onSaved(createdInst);
      Navigator.pop(context); // Close Quick Entry Sheet
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save institution: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFE5E5EA), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Quick Entry: Create Institution',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                style: const TextStyle(color: Color(0xFF1C1C1E)),
                decoration: InputDecoration(
                  labelText: 'Institution Name *',
                  labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                  filled: true,
                  fillColor: const Color(0xFFF4F6F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Institution name is required' : null,
              ),
              const SizedBox(height: 12),
              _isLoadingLocs
                  ? const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                  : Column(
                      children: [
                        DropdownButtonFormField<GeographicUnit>(
                          value: _selectedRegion,
                          style: const TextStyle(color: Color(0xFF1C1C1E)),
                          decoration: InputDecoration(
                            labelText: 'Region',
                            labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                            filled: true,
                            fillColor: const Color(0xFFF4F6F9),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          items: _regions.map((r) => DropdownMenuItem(value: r, child: Text(r.name, style: const TextStyle(color: Color(0xFF1C1C1E))))).toList(),
                          onChanged: _onRegionChanged,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<GeographicUnit>(
                          value: _selectedProvince,
                          style: const TextStyle(color: Color(0xFF1C1C1E)),
                          decoration: InputDecoration(
                            labelText: 'Province',
                            labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                            filled: true,
                            fillColor: const Color(0xFFF4F6F9),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          items: _provinces.map((p) => DropdownMenuItem(value: p, child: Text(p.name, style: const TextStyle(color: Color(0xFF1C1C1E))))).toList(),
                          onChanged: _onProvinceChanged,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<GeographicUnit>(
                          value: _selectedCity,
                          style: const TextStyle(color: Color(0xFF1C1C1E)),
                          decoration: InputDecoration(
                            labelText: 'City/Municipality',
                            labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                            filled: true,
                            fillColor: const Color(0xFFF4F6F9),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                          ),
                          items: _cities.map((c) => DropdownMenuItem(value: c, child: Text(c.name, style: const TextStyle(color: Color(0xFF1C1C1E))))).toList(),
                          onChanged: (val) => setState(() => _selectedCity = val),
                        ),
                      ],
                    ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _streetController,
                style: const TextStyle(color: Color(0xFF1C1C1E)),
                decoration: InputDecoration(
                  labelText: 'Street Address',
                  labelStyle: const TextStyle(color: Color(0xFF8E8E93)),
                  filled: true,
                  fillColor: const Color(0xFFF4F6F9),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF007AFF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Save Institution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GeographicUnit {
  final String name;
  final String code;
  GeographicUnit(this.name, this.code);
}

class _ErpnextDateTimePickerDialog extends StatefulWidget {
  final DateTime initialDateTime;

  const _ErpnextDateTimePickerDialog({Key? key, required this.initialDateTime}) : super(key: key);

  @override
  State<_ErpnextDateTimePickerDialog> createState() => _ErpnextDateTimePickerDialogState();
}

class _ErpnextDateTimePickerDialogState extends State<_ErpnextDateTimePickerDialog> {
  late DateTime _currentMonth;
  late DateTime _selectedDay;
  late int _hour;
  late int _minute;
  late int _second;

  @override
  void initState() {
    super.initState();
    _currentMonth = DateTime(widget.initialDateTime.year, widget.initialDateTime.month);
    _selectedDay = DateTime(widget.initialDateTime.year, widget.initialDateTime.month, widget.initialDateTime.day);
    _hour = widget.initialDateTime.hour;
    _minute = widget.initialDateTime.minute;
    _second = widget.initialDateTime.second;
  }

  void _onNowPressed() {
    final now = DateTime.now();
    setState(() {
      _currentMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
      _hour = now.hour;
      _minute = now.minute;
      _second = now.second;
    });
  }

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final weekdayOfFirst = firstDayOfMonth.weekday % 7;

    final dayWidgets = <Widget>[];
    for (var heading in ['SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA']) {
      dayWidgets.add(
        Center(
          child: Text(
            heading,
            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    for (var i = 0; i < weekdayOfFirst; i++) {
      dayWidgets.add(const SizedBox.shrink());
    }

    for (var day = 1; day <= daysInMonth; day++) {
      final isSelected = _selectedDay.year == _currentMonth.year &&
          _selectedDay.month == _currentMonth.month &&
          _selectedDay.day == day;
      dayWidgets.add(
        GestureDetector(
          onTap: () {
            setState(() {
              _selectedDay = DateTime(_currentMonth.year, _currentMonth.month, day);
            });
          },
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF0056B3) : Colors.transparent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                day.toString(),
                style: TextStyle(
                  color: isSelected ? Colors.white : const Color(0xFF1C1C1E),
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final pad = (int n) => n.toString().padLeft(2, '0');
    final timeStr = "${pad(_hour)}:${pad(_minute)}:${pad(_second)}";

    final monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, color: Color(0xFF1C1C1E)),
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
                    });
                  },
                ),
                Text(
                  "${monthNames[_currentMonth.month - 1]}, ${_currentMonth.year}",
                  style: const TextStyle(color: Color(0xFF1C1C1E), fontSize: 16, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, color: Color(0xFF1C1C1E)),
                  onPressed: () {
                    setState(() {
                      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: dayWidgets,
            ),
            const Divider(color: Color(0xFFE5E5EA), height: 24),
            Row(
              children: [
                Text(
                  timeStr,
                  style: const TextStyle(color: Color(0xFF1C1C1E), fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _hour.toDouble(),
                          min: 0,
                          max: 23,
                          activeColor: const Color(0xFF0056B3),
                          inactiveColor: const Color(0xFFE5E5EA),
                          onChanged: (val) {
                            setState(() {
                              _hour = val.round();
                            });
                          },
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _minute.toDouble(),
                          min: 0,
                          max: 59,
                          activeColor: const Color(0xFF0056B3),
                          inactiveColor: const Color(0xFFE5E5EA),
                          onChanged: (val) {
                            setState(() {
                              _minute = val.round();
                            });
                          },
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _second.toDouble(),
                          min: 0,
                          max: 59,
                          activeColor: const Color(0xFF0056B3),
                          inactiveColor: const Color(0xFFE5E5EA),
                          onChanged: (val) {
                            setState(() {
                              _second = val.round();
                            });
                          },
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
                  child: TextButton(
                    onPressed: _onNowPressed,
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF1C1C1E),
                      backgroundColor: const Color(0xFFE5E5EA),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final finalResult = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day, _hour, _minute, _second);
                      Navigator.of(context).pop(finalResult);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0056B3),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
