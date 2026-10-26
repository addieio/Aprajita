import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aprajita_app/models/contact_model.dart';
import 'package:aprajita_app/models/location_model.dart';
import 'package:aprajita_app/services/storage_service.dart';
import 'package:aprajita_app/services/hardware_service.dart';
import 'package:aprajita_app/services/twilio_service.dart';
import 'package:aprajita_app/views/contacts_view.dart';
import 'package:aprajita_app/views/home_view.dart';
import 'package:aprajita_app/services/location_service.dart';
import 'package:aprajita_app/services/emergency_service.dart';
import 'package:aprajita_app/services/nearby_community_service.dart';
import 'package:aprajita_app/services/supabase_service.dart';
import 'package:aprajita_app/theme/app_theme.dart';

void main() {
  test('Contact phone validation test', () {
    final validIndian = TrustedContact.validatePhone('+91 98765 43210');
    expect(validIndian.isValid, true);
    expect(validIndian.formattedNumber, '+919876543210');

    final rawTenDigits = TrustedContact.validatePhone('9876543210');
    expect(rawTenDigits.isValid, true);
    expect(rawTenDigits.formattedNumber, '+919876543210');

    final userNumber = TrustedContact.validatePhone('9355771234');
    expect(userNumber.isValid, true);
    expect(userNumber.formattedNumber, '+919355771234');

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

  test('StorageService contact edit in-place and delete test', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = await StorageService.init();

    // 1. Initial load returns default contact
    final initialContacts = storage.loadContacts();
    expect(initialContacts.length, 1);
    expect(initialContacts.first.id, 'contact-primary-default');

    // 2. Edit contact (e.g. user changes number to 9355771234)
    final editedContact = initialContacts.first.copyWith(
      name: 'My Mother',
      phone: '+919355771234',
    );
    await storage.updateContact(editedContact);

    final contactsAfterEdit = storage.loadContacts();
    expect(contactsAfterEdit.length, 1); // EXACTLY 1 contact, no duplicate created!
    expect(contactsAfterEdit.first.name, 'My Mother');
    expect(contactsAfterEdit.first.phone, '+919355771234');

    // 3. User edits number again to a new number
    final updatedAgain = contactsAfterEdit.first.copyWith(
      name: 'My Mother',
      phone: '+919876500000',
    );
    await storage.updateContact(updatedAgain);
    final contactsAfterSecondEdit = storage.loadContacts();
    expect(contactsAfterSecondEdit.length, 1); // Still exactly 1 contact!
    expect(contactsAfterSecondEdit.first.phone, '+919876500000');

    // 4. Delete the contact
    await storage.deleteContact(updatedAgain.id);
    final contactsAfterDelete = storage.loadContacts();
    expect(contactsAfterDelete.isEmpty, true); // Stays empty, does NOT resurrect old contact!
  });

  testWidgets('ContactsView displays Add Contact option when contacts are empty', (tester) async {
    SharedPreferences.setMockInitialValues({'aprajita_contacts': '[]', 'aprajita_primary_contact_id': ''});
    final storage = await StorageService.init();

    // Verify loaded list is empty
    expect(storage.loadContacts().isEmpty, true);

    final hardware = HardwareService();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: ContactsView(
            storageService: storage,
            hardwareService: hardware,
            twilioService: TwilioService(storage),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify empty state is displayed with Add Contact button
    expect(find.text('No Emergency Contacts Added'), findsOneWidget);
    expect(find.text('Add Trusted Contact'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget); // Top app bar add button

    // Tap Add Trusted Contact button to open dialog
    await tester.tap(find.text('Add Trusted Contact'));
    await tester.pumpAndSettle();

    // Verify dialog opened without ParentData/Spacer crash!
    expect(find.text('Add Trusted Contact'), findsWidgets);
    expect(find.text('Contact Name'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);

    // Close dialog and clean up timers
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    hardware.enableSimulationMode(false);
  });

  testWidgets('HomeView displays prominent Add Contact option when contacts are empty', (tester) async {
    SharedPreferences.setMockInitialValues({'aprajita_contacts': '[]', 'aprajita_primary_contact_id': ''});
    final storage = await StorageService.init();
    final hardware = HardwareService();
    final location = LocationService();
    final twilio = TwilioService(storage);
    final supabase = SupabaseService(storage);
    final nearby = NearbyCommunityService(supabase);
    final emergency = EmergencyService(
      storageService: storage,
      twilioService: twilio,
      locationService: location,
      hardwareService: hardware,
      nearbyService: nearby,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: HomeView(
            emergencyService: emergency,
            hardwareService: hardware,
            locationService: location,
            storageService: storage,
            twilioService: twilio,
            onNavigateToContacts: () {},
            onNavigateToHardware: () {},
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 300));

    // Verify empty state is displayed prominently
    expect(find.text('NO CONTACT CONFIGURED'), findsOneWidget);
    expect(find.text('ACTION REQUIRED'), findsOneWidget);
    expect(find.text('Tap here to add emergency contact number'), findsOneWidget);
    expect(find.text('Add Contact'), findsOneWidget);

    // Tap Add Contact button to open dialog
    await tester.tap(find.text('Add Contact'));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify dialog opened cleanly without crash
    expect(find.text('Add Trusted Contact'), findsWidgets);
    expect(find.text('Contact Name'), findsOneWidget);
    expect(find.text('Mobile Number'), findsOneWidget);

    // Cancel dialog and clean up
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));
    hardware.enableSimulationMode(false);
  });
}
