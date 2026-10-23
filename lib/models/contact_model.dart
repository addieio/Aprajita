class TrustedContact {
  final String id;
  final String name;
  final String phone;
  final bool isEmergencyRecipient;
  final bool isPrimary;
  final bool syncedToKeychain;
  final DateTime addedAt;

  TrustedContact({
    required this.id,
    required this.name,
    required this.phone,
    this.isEmergencyRecipient = true,
    this.isPrimary = false,
    this.syncedToKeychain = false,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  TrustedContact copyWith({
    String? id,
    String? name,
    String? phone,
    bool? isEmergencyRecipient,
    bool? isPrimary,
    bool? syncedToKeychain,
    DateTime? addedAt,
  }) {
    return TrustedContact(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      isEmergencyRecipient: isEmergencyRecipient ?? this.isEmergencyRecipient,
      isPrimary: isPrimary ?? this.isPrimary,
      syncedToKeychain: syncedToKeychain ?? this.syncedToKeychain,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'isEmergencyRecipient': isEmergencyRecipient,
      'isPrimary': isPrimary,
      'syncedToKeychain': syncedToKeychain,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  factory TrustedContact.fromJson(Map<String, dynamic> map) {
    return TrustedContact(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      isEmergencyRecipient: map['isEmergencyRecipient'] ?? true,
      isPrimary: map['isPrimary'] ?? false,
      syncedToKeychain: map['syncedToKeychain'] ?? false,
      addedAt: map['addedAt'] != null
          ? DateTime.tryParse(map['addedAt']) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  /// Normalizes and validates phone numbers.
  /// Handles +91, 0, or raw 10 digits for India, or international E.164.
  static ValidationResult validatePhone(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.isEmpty) {
      return ValidationResult(isValid: false, message: 'Phone number is required.');
    }

    // Indian mobile standard regex: 10 digits starting with 6, 7, 8, or 9
    final indianRegex = RegExp(r'^(?:\+91|91|0)?([6789]\d{9})$');
    final indianMatch = indianRegex.firstMatch(cleaned);

    if (indianMatch != null) {
      final tenDigits = indianMatch.group(1)!;
      return ValidationResult(
        isValid: true,
        formattedNumber: '+91$tenDigits',
        displayNumber: '+91 ${tenDigits.substring(0, 5)} ${tenDigits.substring(5)}',
      );
    }

    // International E.164 format check: + followed by 8 to 15 digits
    final intlRegex = RegExp(r'^\+[1-9]\d{7,14}$');
    if (intlRegex.hasMatch(cleaned)) {
      return ValidationResult(
        isValid: true,
        formattedNumber: cleaned,
        displayNumber: cleaned,
      );
    }

    return ValidationResult(
      isValid: false,
      message: 'Enter a valid 10-digit mobile number (e.g. +91 98765 43210).',
    );
  }
}

class ValidationResult {
  final bool isValid;
  final String? formattedNumber;
  final String? displayNumber;
  final String? message;

  ValidationResult({
    required this.isValid,
    this.formattedNumber,
    this.displayNumber,
    this.message,
  });
}
