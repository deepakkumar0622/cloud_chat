import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/contact_model.dart';

class ContactService {
  ContactService._();

  static final ContactService instance = ContactService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _currentUid {
    final uid = _auth.currentUser?.uid;

    if (uid == null) {
      throw Exception('User is not authenticated.');
    }

    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _contacts =>
      _firestore.collection('users').doc(_currentUid).collection('contacts');

  /// Add a new contact.
  Future<String> addContact({
    required String contactName,
    required String phoneNumber,
  }) async {
    final name = contactName.trim();
    final phone = phoneNumber.trim();

    if (name.isEmpty) {
      throw Exception('Contact name cannot be empty.');
    }

    if (phone.isEmpty) {
      throw Exception('Phone number cannot be empty.');
    }

    // Prevent duplicate contacts with the same phone number.
    final existingContact = await _contacts
        .where('phoneNumber', isEqualTo: phone)
        .limit(1)
        .get();

    if (existingContact.docs.isNotEmpty) {
      throw Exception('This contact already exists.');
    }

    final document = _contacts.doc();

    final contact = ContactModel(
      id: document.id,
      contactName: name,
      phoneNumber: phone,
    );

    await document.set(contact.toCreateMap());

    return document.id;
  }

  /// Listen to the current user's contacts.
  Stream<List<ContactModel>> watchContacts() {
    return _contacts.orderBy('contactName').snapshots().map((snapshot) {
      return snapshot.docs.map((document) {
        return ContactModel.fromMap(document.id, document.data());
      }).toList();
    });
  }

  /// Update an existing contact.
  Future<void> updateContact({
    required String contactId,
    required String contactName,
    required String phoneNumber,
  }) async {
    final name = contactName.trim();
    final phone = phoneNumber.trim();

    if (name.isEmpty) {
      throw Exception('Contact name cannot be empty.');
    }

    if (phone.isEmpty) {
      throw Exception('Phone number cannot be empty.');
    }

    final document = _contacts.doc(contactId);

    final snapshot = await document.get();

    if (!snapshot.exists) {
      throw Exception('Contact not found.');
    }

    // Check duplicates excluding the contact being edited.
    final duplicate = await _contacts
        .where('phoneNumber', isEqualTo: phone)
        .limit(2)
        .get();

    final hasDuplicate = duplicate.docs.any((doc) => doc.id != contactId);

    if (hasDuplicate) {
      throw Exception('Another contact already uses this number.');
    }

    await document.update({
      'contactName': name,
      'phoneNumber': phone,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete an existing contact.
  Future<void> deleteContact(String contactId) async {
    await _contacts.doc(contactId).delete();
  }

  /// Listen to the saved contact name using phone number or recipient UID.
  Stream<String?> watchContactName({String? phoneNumber, String? matchedUid}) {
    // Phone number is the primary lookup.
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      return _contacts
          .where('phoneNumber', isEqualTo: phoneNumber.trim())
          .limit(1)
          .snapshots()
          .map((snapshot) {
            if (snapshot.docs.isEmpty) return null;

            return snapshot.docs.first.data()['contactName'] as String?;
          });
    }

    // Use UID when the phone number is unavailable.
    if (matchedUid != null && matchedUid.trim().isNotEmpty) {
      return _contacts
          .where('matchedUid', isEqualTo: matchedUid.trim())
          .limit(1)
          .snapshots()
          .map((snapshot) {
            if (snapshot.docs.isEmpty) return null;

            return snapshot.docs.first.data()['contactName'] as String?;
          });
    }

    return Stream<String?>.value(null);
  }
}
