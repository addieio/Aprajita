import 'package:flutter_test/flutter_test.dart';
import 'package:aprajita_app/models/contact_model.dart';
import 'package:aprajita_app/models/location_model.dart';

void main() {
  test('Contact phone validation test', () {
    final validIndian = TrustedContact.validatePhone('+91 98765 43210');
    expect(validIndian.isValid, true);
    expect(validIndian.formattedNumber, '+919876543210');

    final rawTenDigits = TrustedContact.validatePhone('9876543210');
    expect(rawTenDigits.isValid, true);
    expect(rawTenDigits.formattedNumber, '+919876543210');

    final invalidPhone = TrustedContact.validatePhone('1234');
    expect(invalidPhone.isValid, false);
  });

  test('Location model distance test', () {
    final loc1 = GpsLocation(
      lat: 28.5457,
      lng: 77.2732,
      accuracy: 10,
      timestamp: DateTime.now(),
      source: GpsSource.phoneGps,
    );

    // Same location should have 0 distance
    final dist = loc1.distanceTo(28.5457, 77.2732);
    expect(dist < 1.0, true);
  });
}
