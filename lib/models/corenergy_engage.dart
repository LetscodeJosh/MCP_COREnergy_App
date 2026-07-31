class COREnergyEngageContact {
  String? contactName;
  String? position;
  String? email;
  String? phoneMobile;

  COREnergyEngageContact({
    this.contactName,
    this.position,
    this.email,
    this.phoneMobile,
  });

  factory COREnergyEngageContact.fromJson(Map<String, dynamic> json) {
    return COREnergyEngageContact(
      contactName: json['contact_name'] ?? json['name'],
      position: json['position'],
      email: json['email'],
      phoneMobile: json['phone_mobile'] ?? json['phone'] ?? json['mobile'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'contact_name': contactName,
      'position': position,
      'email': email,
      'phone_mobile': phoneMobile,
    };
  }
}

class COREnergyEngageVisit {
  bool successfulCall;
  bool unsuccessfulCall;
  String? reasonForUnsuccessfulCall;
  bool decisionMakerNotAvailable;
  String? notes;

  COREnergyEngageVisit({
    this.successfulCall = false,
    this.unsuccessfulCall = false,
    this.reasonForUnsuccessfulCall,
    this.decisionMakerNotAvailable = false,
    this.notes,
  });

  factory COREnergyEngageVisit.fromJson(Map<String, dynamic> json) {
    return COREnergyEngageVisit(
      successfulCall: json['successful_call'] == 1 || json['successful_call'] == true,
      unsuccessfulCall: json['unsuccessful_call'] == 1 || json['unsuccessful_call'] == true,
      reasonForUnsuccessfulCall: json['reason_for_unsuccessful_call'],
      decisionMakerNotAvailable: json['decision_maker_or_responsible_person_not_available'] == 1 || json['decision_maker_or_responsible_person_not_available'] == true,
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'successful_call': successfulCall ? 1 : 0,
      'unsuccessful_call': unsuccessfulCall ? 1 : 0,
      'reason_for_unsuccessful_call': reasonForUnsuccessfulCall,
      'decision_maker_or_responsible_person_not_available': decisionMakerNotAvailable ? 1 : 0,
      'notes': notes,
    };
  }
}

class COREnergyEngageActionItem {
  String? nextStep;
  String? targetDate;
  String? nextStepStatus; // "Incomplete" or "Complete"
  String? dateCompleted;

  COREnergyEngageActionItem({
    this.nextStep,
    this.targetDate,
    this.nextStepStatus = "Incomplete",
    this.dateCompleted,
  });

  factory COREnergyEngageActionItem.fromJson(Map<String, dynamic> json) {
    return COREnergyEngageActionItem(
      nextStep: json['next_step'],
      targetDate: json['target_date'],
      nextStepStatus: json['next_step_status'] ?? 'Incomplete',
      dateCompleted: json['date_completed'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'next_step': nextStep,
      'target_date': targetDate,
      'next_step_status': nextStepStatus,
      'date_completed': dateCompleted,
    };
  }
}

class COREnergyEngage {
  final String name; // e.g. INST-00001
  final String? institutionName;
  final String? hospitalClinic;
  final String? region;
  final String? province;
  final String? cityMunicipality;
  final String? barangayName;
  final String? streetAddress;
  final String? salesRep;
  final String? leadsSource;
  final String? leadsStatus;
  final String? ownershipNationality;
  final String? creation;
  final String? modified;

  // Child tables
  final List<COREnergyEngageContact> contacts;
  final List<COREnergyEngageVisit> visits;
  final List<COREnergyEngageActionItem> actionItems;

  COREnergyEngage({
    required this.name,
    this.institutionName,
    this.hospitalClinic,
    this.region,
    this.province,
    this.cityMunicipality,
    this.barangayName,
    this.streetAddress,
    this.salesRep,
    this.leadsSource,
    this.leadsStatus,
    this.ownershipNationality,
    this.creation,
    this.modified,
    this.contacts = const [],
    this.visits = const [],
    this.actionItems = const [],
  });

  factory COREnergyEngage.fromJson(Map<String, dynamic> json) {
    // Parse contacts child table
    var contactsList = json['table_ugpp'] ?? json['contacts'] ?? [];
    List<COREnergyEngageContact> parsedContacts = [];
    if (contactsList is List) {
      parsedContacts = contactsList.map((c) => COREnergyEngageContact.fromJson(c)).toList();
    }

    // Parse visits child table
    var visitsList = json['visits'] ?? json['engagements'] ?? [];
    List<COREnergyEngageVisit> parsedVisits = [];
    if (visitsList is List) {
      parsedVisits = visitsList.map((v) => COREnergyEngageVisit.fromJson(v)).toList();
    }

    // Parse action items child table
    var actionItemsList = json['action_items'] ?? json['next_steps'] ?? [];
    List<COREnergyEngageActionItem> parsedActionItems = [];
    if (actionItemsList is List) {
      parsedActionItems = actionItemsList.map((a) => COREnergyEngageActionItem.fromJson(a)).toList();
    }

    final resolvedInstName = json['institution_name'] ?? json['institution'] ?? '';
    return COREnergyEngage(
      name: json['name'] ?? '',
      institutionName: resolvedInstName.isNotEmpty ? resolvedInstName : (json['name'] ?? ''),
      hospitalClinic: json['name_of_hospital_or_clinic'] ?? json['hospital_clinic'] ?? json['hospital_clinic_name'] ?? json['institution_label'],
      region: json['region_name'] ?? json['region'],
      province: json['province_name'] ?? json['province'],
      cityMunicipality: json['city_municipality'],
      barangayName: json['barangay_name'] ?? json['barangay'],
      streetAddress: json['street_address'],
      salesRep: json['sales_rep'],
      leadsSource: json['leads_source'],
      leadsStatus: json['leads_status'],
      ownershipNationality: json['ownership_nationality'],
      creation: json['creation'],
      modified: json['modified'],
      contacts: parsedContacts,
      visits: parsedVisits,
      actionItems: parsedActionItems,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'institution_name': institutionName,
      'name_of_hospital_or_clinic': hospitalClinic,
      'hospital_clinic': hospitalClinic,
      'hospital_clinic_name': hospitalClinic,
      'institution_label': hospitalClinic,
      if (region != null) 'region_name': region,
      if (region != null) 'region': region,
      if (province != null) 'province_name': province,
      if (province != null) 'province': province,
      if (cityMunicipality != null) 'city_municipality': cityMunicipality,
      if (barangayName != null) 'barangay_name': barangayName,
      if (streetAddress != null) 'street_address': streetAddress,
      if (salesRep != null) 'sales_rep': salesRep,
      if (leadsSource != null) 'leads_source': leadsSource,
      if (leadsStatus != null) 'leads_status': leadsStatus,
      if (ownershipNationality != null) 'ownership_nationality': ownershipNationality,
      // Serialize child tables to multiple common naming keys for safety
      'table_ugpp': contacts.map((c) => c.toJson()).toList(),
      'contacts': contacts.map((c) => c.toJson()).toList(),
      'visits': visits.map((v) => v.toJson()).toList(),
      'engagements': visits.map((v) => v.toJson()).toList(),
      'action_items': actionItems.map((a) => a.toJson()).toList(),
      'next_steps': actionItems.map((a) => a.toJson()).toList(),
    };
  }
}
