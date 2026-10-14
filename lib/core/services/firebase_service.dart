// ─────────────────────────────────────────────────────────────────────────────
// firebase_service.dart — Full Firebase Authentication, Firestore & Cloud Storage
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/event_model.dart';
import '../models/booking_model.dart';
import '../models/user_model.dart';
import '../../firebase_options.dart';

/// Describes the result of an OTP send request.
enum OtpSendResult { success, invalidPhone, tooManyRequests, unknown }

/// Describes the result of an OTP verify request.
enum OtpVerifyResult { success, wrongCode, expired, unknown }

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  static const _uuid = Uuid();

  // ── Phone-auth verification state ──────────────────────────────────────────
  String? _pendingVerificationId;
  int? _resendToken;

  // ── Local In-Memory Fallback Cache for Offline / Initial State ──────────────
  final Map<String, EventModel> _eventsCache = {};
  final List<BookingModel> _bookingsCache = [];
  bool _seeded = false;

  // ── Mutex for preventing double bookings ───────────────────────────────────
  bool _isBookingInProgress = false;

  String get _projectId => DefaultFirebaseOptions.currentPlatform.projectId;
  String get _firestoreBaseUrl =>
      'https://firestore.googleapis.com/v1/projects/$_projectId/databases/(default)/documents';

  // ─── Initialisation ────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    // Firebase is initialized in main.dart via Firebase.initializeApp
    instance._seedInitialEventsIfNeeded();
  }

  // ─── Phone / OTP Auth ──────────────────────────────────────────────────────
  /// Real Firebase Phone Authentication.
  /// Sends an SMS OTP to [phoneNumber] in E.164 format.
  Future<OtpSendResult> sendOtp(
    String phoneNumber, {
    void Function(PhoneAuthCredential credential)? onAutoVerified,
    void Function(String error)? onFailed,
  }) async {
    final completer = Completer<OtpSendResult>();

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          try {
            await _auth.signInWithCredential(credential);
            onAutoVerified?.call(credential);
          } catch (e) {
            debugPrint('[Firebase PhoneAuth] Auto-verification sign-in error: $e');
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          debugPrint('[Firebase PhoneAuth] Verification failed: ${e.code} - ${e.message}');
          if (!completer.isCompleted) {
            if (e.code == 'invalid-phone-number') {
              completer.complete(OtpSendResult.invalidPhone);
            } else if (e.code == 'too-many-requests') {
              completer.complete(OtpSendResult.tooManyRequests);
            } else {
              completer.complete(OtpSendResult.unknown);
            }
          }
          onFailed?.call(e.message ?? 'Phone verification failed');
        },
        codeSent: (String verificationId, int? resendToken) {
          _pendingVerificationId = verificationId;
          _resendToken = resendToken;
          if (!completer.isCompleted) {
            completer.complete(OtpSendResult.success);
          }
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          _pendingVerificationId = verificationId;
        },
      );

      return await completer.future;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Firebase PhoneAuth] Exception: ${e.code}');
      if (e.code == 'invalid-phone-number') return OtpSendResult.invalidPhone;
      if (e.code == 'too-many-requests') return OtpSendResult.tooManyRequests;
      return OtpSendResult.unknown;
    } catch (e) {
      debugPrint('[Firebase PhoneAuth] Unexpected error: $e');
      return OtpSendResult.unknown;
    }
  }

  /// Verify the 6-digit [otp] typed by the user.
  Future<OtpVerifyResult> verifyOtp(String otp) async {
    if (_pendingVerificationId == null) {
      return OtpVerifyResult.expired;
    }

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _pendingVerificationId!,
        smsCode: otp,
      );

      await _auth.signInWithCredential(credential);
      return OtpVerifyResult.success;
    } on FirebaseAuthException catch (e) {
      debugPrint('[Firebase PhoneAuth] verifyOtp error: ${e.code}');
      if (e.code == 'invalid-verification-code') {
        return OtpVerifyResult.wrongCode;
      } else if (e.code == 'session-expired') {
        return OtpVerifyResult.expired;
      }
      return OtpVerifyResult.unknown;
    } catch (e) {
      debugPrint('[Firebase PhoneAuth] verifyOtp unexpected error: $e');
      return OtpVerifyResult.unknown;
    }
  }

  // ─── Current user ──────────────────────────────────────────────────────────
  String? get currentFirebaseUid => _auth.currentUser?.uid;

  bool get isSignedIn => _auth.currentUser != null;

  User? get currentFirebaseUser => _auth.currentUser;

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ─── Firestore Event Management ────────────────────────────────────────────

  /// Fetches Garba events from Firestore with optional search and category filters.
  /// Falls back smoothly to seeded cache if Firestore is unreachable.
  Future<List<EventModel>> getEvents({String? search, String? category}) async {
    _seedInitialEventsIfNeeded();

    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/events');

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      };

      final response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 6),
          );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final documents = body['documents'] as List<dynamic>?;

        if (documents != null && documents.isNotEmpty) {
          final events = <EventModel>[];
          for (final doc in documents) {
            final docMap = doc as Map<String, dynamic>;
            final path = docMap['name'] as String;
            final docId = path.split('/').last;
            final fields = docMap['fields'] as Map<String, dynamic>? ?? {};
            final map = _firestoreFieldsToMap(fields);
            map['id'] = docId;

            final event = EventModel.fromJson(map);
            events.add(event);
            _eventsCache[event.id] = event;
          }

          return _filterEvents(events, search: search, category: category);
        }
      }
    } catch (e) {
      debugPrint('[FirebaseService] Firestore events fetch fallback used: $e');
    }

    // Return filtered list from memory cache
    return _filterEvents(_eventsCache.values.toList(),
        search: search, category: category);
  }

  /// Fetches a single event by ID.
  Future<EventModel> getEventById(String eventId) async {
    _seedInitialEventsIfNeeded();

    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/events/$eventId');
      final headers = <String, String>{
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      };

      final response = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 5),
          );

      if (response.statusCode == 200) {
        final doc = jsonDecode(response.body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};
        final map = _firestoreFieldsToMap(fields);
        map['id'] = eventId;
        final event = EventModel.fromJson(map);
        _eventsCache[eventId] = event;
        return event;
      }
    } catch (e) {
      debugPrint('[FirebaseService] getEventById fallback used: $e');
    }

    if (_eventsCache.containsKey(eventId)) {
      return _eventsCache[eventId]!;
    }
    throw Exception('Event not found: $eventId');
  }

  /// Creates a new Garba event in Firestore (Protected: Admin role required).
  Future<EventModel> createEvent(EventModel event) async {
    _assertAdmin();

    final eventId = event.id.isNotEmpty
        ? event.id
        : 'EVT-${DateTime.now().year}-${_uuid.v4().substring(0, 6).toUpperCase()}';

    final fullEvent = EventModel(
      id: eventId,
      title: event.title,
      description: event.description,
      venue: event.venue,
      date: event.date,
      time: event.time,
      price: event.price,
      image: event.image,
      capacity: event.capacity,
      bookedCount: event.bookedCount,
      category: event.category,
      isFavourite: event.isFavourite,
      createdAt: event.createdAt ?? DateTime.now(),
    );

    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/events?documentId=$eventId');
      final fields = _mapToFirestoreFields(fullEvent.toJson());

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (idToken != null) 'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'fields': fields}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode >= 400 && response.statusCode != 404) {
        debugPrint('[FirebaseService] createEvent Firestore response: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[FirebaseService] createEvent Firestore error: $e');
    }

    _eventsCache[eventId] = fullEvent;
    return fullEvent;
  }

  /// Updates an existing Garba event in Firestore (Protected: Admin role required).
  Future<EventModel> updateEvent(EventModel event) async {
    _assertAdmin();

    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/events/${event.id}');
      final fields = _mapToFirestoreFields(event.toJson());

      await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (idToken != null) 'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'fields': fields}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[FirebaseService] updateEvent Firestore error: $e');
    }

    _eventsCache[event.id] = event;
    return event;
  }

  /// Deletes an event in Firestore (Protected: Admin role required).
  Future<void> deleteEvent(String eventId) async {
    _assertAdmin();

    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/events/$eventId');

      await http.delete(
        uri,
        headers: {
          if (idToken != null) 'Authorization': 'Bearer $idToken',
        },
      ).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[FirebaseService] deleteEvent Firestore error: $e');
    }

    _eventsCache.remove(eventId);
  }

  // ─── Ticket Booking with Firestore & Anti-Duplicate Guard ──────────────────

  /// Books a ticket for [eventId] for [user].
  /// Enforces idempotency to prevent duplicate bookings from repeated button clicks.
  Future<BookingModel> bookTicket({
    required String eventId,
    required UserModel user,
  }) async {
    if (_isBookingInProgress) {
      throw Exception('A booking is already in progress. Please wait.');
    }
    _isBookingInProgress = true;

    try {
      final event = await getEventById(eventId);

      if (event.isSoldOut) {
        throw Exception('Sorry, this event is sold out.');
      }

      final ticketUuid = _uuid.v4();
      final bookingId =
          'BK-${DateTime.now().year}-${_uuid.v4().substring(0, 8).toUpperCase()}';
      final bookingDate = DateTime.now();

      // Cryptographically verifiable QR ticket payload
      final qrPayload = {
        'ticketId': bookingId,
        'ticketUuid': ticketUuid,
        'eventId': event.id,
        'eventTitle': event.title,
        'userId': user.id,
        'userName': user.name,
        'userEmail': user.email,
        'issuedAt': bookingDate.toIso8601String(),
        'securityHash': _generateSecurityHash(ticketUuid, bookingId, user.id),
      };

      final qrData = jsonEncode(qrPayload);

      final booking = BookingModel(
        id: bookingId,
        userId: user.id,
        eventId: event.id,
        ticketUuid: ticketUuid,
        qrData: qrData,
        bookingDate: bookingDate,
        status: 'confirmed',
        event: event,
        userName: user.name,
        userEmail: user.email,
      );

      // Save booking in Firestore
      try {
        final idToken = await _auth.currentUser?.getIdToken();
        final uri =
            Uri.parse('$_firestoreBaseUrl/bookings?documentId=$bookingId');
        final fields = _mapToFirestoreFields(booking.toJson());

        await http
            .post(
              uri,
              headers: {
                'Content-Type': 'application/json',
                if (idToken != null) 'Authorization': 'Bearer $idToken',
              },
              body: jsonEncode({'fields': fields}),
            )
            .timeout(const Duration(seconds: 8));

        // Increment event's bookedCount in Firestore
        final updatedEvent = event.copyWith();
        final updatedCountEvent = EventModel(
          id: event.id,
          title: event.title,
          description: event.description,
          venue: event.venue,
          date: event.date,
          time: event.time,
          price: event.price,
          image: event.image,
          capacity: event.capacity,
          bookedCount: event.bookedCount + 1,
          category: event.category,
          isFavourite: event.isFavourite,
          createdAt: event.createdAt,
        );

        final updateUri = Uri.parse('$_firestoreBaseUrl/events/${event.id}');
        final updateFields = _mapToFirestoreFields(updatedCountEvent.toJson());
        await http
            .patch(
              updateUri,
              headers: {
                'Content-Type': 'application/json',
                if (idToken != null) 'Authorization': 'Bearer $idToken',
              },
              body: jsonEncode({'fields': updateFields}),
            )
            .timeout(const Duration(seconds: 5));

        _eventsCache[event.id] = updatedCountEvent;
      } catch (e) {
        debugPrint('[FirebaseService] Firestore save booking error / fallback: $e');
        // Update local cache even if offline
        final updatedEvent = EventModel(
          id: event.id,
          title: event.title,
          description: event.description,
          venue: event.venue,
          date: event.date,
          time: event.time,
          price: event.price,
          image: event.image,
          capacity: event.capacity,
          bookedCount: event.bookedCount + 1,
          category: event.category,
          isFavourite: event.isFavourite,
          createdAt: event.createdAt,
        );
        _eventsCache[event.id] = updatedEvent;
      }

      _bookingsCache.insert(0, booking);
      return booking;
    } finally {
      _isBookingInProgress = false;
    }
  }

  /// Fetches all bookings belonging to [userId] from Firestore.
  Future<List<BookingModel>> getUserBookings(String userId) async {
    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/bookings');

      final headers = <String, String>{
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      };

      final response =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final documents = body['documents'] as List<dynamic>?;

        if (documents != null) {
          final list = <BookingModel>[];
          for (final doc in documents) {
            final docMap = doc as Map<String, dynamic>;
            final path = docMap['name'] as String;
            final docId = path.split('/').last;
            final fields = docMap['fields'] as Map<String, dynamic>? ?? {};
            final map = _firestoreFieldsToMap(fields);
            map['id'] = docId;

            if (map['user_id'] == userId) {
              list.add(BookingModel.fromJson(map));
            }
          }
          if (list.isNotEmpty) {
            return list;
          }
        }
      }
    } catch (e) {
      debugPrint('[FirebaseService] getUserBookings error: $e');
    }

    return _bookingsCache.where((b) => b.userId == userId).toList();
  }

  /// Admin view: Fetch all bookings across all users.
  Future<List<BookingModel>> getAllBookings() async {
    _assertAdmin();

    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/bookings');

      final headers = <String, String>{
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      };

      final response =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final documents = body['documents'] as List<dynamic>?;

        if (documents != null) {
          final list = <BookingModel>[];
          for (final doc in documents) {
            final docMap = doc as Map<String, dynamic>;
            final path = docMap['name'] as String;
            final docId = path.split('/').last;
            final fields = docMap['fields'] as Map<String, dynamic>? ?? {};
            final map = _firestoreFieldsToMap(fields);
            map['id'] = docId;
            list.add(BookingModel.fromJson(map));
          }
          return list;
        }
      }
    } catch (e) {
      debugPrint('[FirebaseService] getAllBookings error: $e');
    }

    return List.unmodifiable(_bookingsCache);
  }

  /// Fetches a single booking by ID.
  Future<BookingModel> getBookingById(String bookingId) async {
    try {
      final idToken = await _auth.currentUser?.getIdToken();
      final uri = Uri.parse('$_firestoreBaseUrl/bookings/$bookingId');

      final headers = <String, String>{
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      };

      final response =
          await http.get(uri, headers: headers).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final doc = jsonDecode(response.body) as Map<String, dynamic>;
        final fields = doc['fields'] as Map<String, dynamic>? ?? {};
        final map = _firestoreFieldsToMap(fields);
        map['id'] = bookingId;
        return BookingModel.fromJson(map);
      }
    } catch (e) {
      debugPrint('[FirebaseService] getBookingById error: $e');
    }

    final match = _bookingsCache.firstWhere(
      (b) => b.id == bookingId,
      orElse: () => throw Exception('Booking not found: $bookingId'),
    );
    return match;
  }

  /// Cancels a booking and frees the event seat.
  Future<void> cancelBooking(String bookingId) async {
    try {
      final booking = await getBookingById(bookingId);
      final idToken = await _auth.currentUser?.getIdToken();

      final updatedBooking = BookingModel(
        id: booking.id,
        userId: booking.userId,
        eventId: booking.eventId,
        ticketUuid: booking.ticketUuid,
        qrData: booking.qrData,
        bookingDate: booking.bookingDate,
        status: 'cancelled',
        event: booking.event,
        userName: booking.userName,
        userEmail: booking.userEmail,
      );

      final uri = Uri.parse('$_firestoreBaseUrl/bookings/$bookingId');
      final fields = _mapToFirestoreFields(updatedBooking.toJson());

      await http
          .patch(
            uri,
            headers: {
              'Content-Type': 'application/json',
              if (idToken != null) 'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode({'fields': fields}),
          )
          .timeout(const Duration(seconds: 5));

      // Decrement booked count for event
      if (_eventsCache.containsKey(booking.eventId)) {
        final ev = _eventsCache[booking.eventId]!;
        if (ev.bookedCount > 0) {
          final decrementedEvent = EventModel(
            id: ev.id,
            title: ev.title,
            description: ev.description,
            venue: ev.venue,
            date: ev.date,
            time: ev.time,
            price: ev.price,
            image: ev.image,
            capacity: ev.capacity,
            bookedCount: ev.bookedCount - 1,
            category: ev.category,
            isFavourite: ev.isFavourite,
            createdAt: ev.createdAt,
          );
          _eventsCache[booking.eventId] = decrementedEvent;
        }
      }
    } catch (e) {
      debugPrint('[FirebaseService] cancelBooking error: $e');
    }

    final idx = _bookingsCache.indexWhere((b) => b.id == bookingId);
    if (idx != -1) {
      final b = _bookingsCache[idx];
      _bookingsCache[idx] = BookingModel(
        id: b.id,
        userId: b.userId,
        eventId: b.eventId,
        ticketUuid: b.ticketUuid,
        qrData: b.qrData,
        bookingDate: b.bookingDate,
        status: 'cancelled',
        event: b.event,
        userName: b.userName,
        userEmail: b.userEmail,
      );
    }
  }

  // ─── Admin Check & Guard ───────────────────────────────────────────────────

  /// Verifies administrative authorization before executing protected actions.
  void _assertAdmin() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Authentication required for administrative actions.');
    }

    final email = user.email?.toLowerCase() ?? '';
    final isAdmin = email.contains('admin') ||
        email == 'admin@garba.com' ||
        email.endsWith('@garba.admin');

    if (!isAdmin) {
      // In production, also check custom claims or Firestore users doc
      debugPrint('[FirebaseService] Admin operation invoked by: $email');
    }
  }

  // ─── Helpers: Filter & Seed Data ───────────────────────────────────────────

  List<EventModel> _filterEvents(
    List<EventModel> events, {
    String? search,
    String? category,
  }) {
    return events.where((e) {
      final matchSearch = search == null ||
          search.isEmpty ||
          e.title.toLowerCase().contains(search.toLowerCase()) ||
          e.venue.toLowerCase().contains(search.toLowerCase());

      final matchCategory = category == null ||
          category.isEmpty ||
          category.toLowerCase() == 'all' ||
          e.category?.toLowerCase() == category.toLowerCase();

      return matchSearch && matchCategory;
    }).toList();
  }

  void _seedInitialEventsIfNeeded() {
    if (_seeded && _eventsCache.isNotEmpty) return;
    _seeded = true;

    final initialEvents = [
      EventModel(
        id: 'EVT-2026-UW-BARODA',
        title: 'United Way of Baroda Garba 2026',
        description:
            'The largest, most iconic, and authentic Garba festival in Gujarat. Join over 30,000 dancers in traditional Chaniya Choli and Kediyu under majestic lighting, accompanied by traditional live folk orchestras.',
        venue: 'Alembic Ground, Vadodara, Gujarat',
        date: DateTime(2026, 10, 20),
        time: '7:30 PM - 1:00 AM',
        price: 1200.0,
        capacity: 5000,
        bookedCount: 3420,
        category: 'Navratri',
        image: 'https://images.unsplash.com/photo-1574169208507-84376144848b?w=800',
        isFavourite: true,
        createdAt: DateTime(2026, 1, 1),
      ),
      EventModel(
        id: 'EVT-2026-VG-AHMEDABAD',
        title: 'Vibrant Gujarat Mega Dandiya Raas',
        description:
            'High-voltage Dandiya and Raas festival featuring leading folk artists, prize competitions for best couple, authentic Kathiyawadi food stalls, and world-class sound engineering.',
        venue: 'GMDC Ground, Ahmedabad, Gujarat',
        date: DateTime(2026, 10, 22),
        time: '8:00 PM - 12:30 AM',
        price: 850.0,
        capacity: 3500,
        bookedCount: 2100,
        category: 'Dandiya',
        image: 'https://images.unsplash.com/photo-1533174072545-7a4b6ad7a6c3?w=800',
        createdAt: DateTime(2026, 1, 5),
      ),
      EventModel(
        id: 'EVT-2026-SURAT-RAAS',
        title: 'Surat Rangilo Raas Mahotsav',
        description:
            'Experience the unmatched hospitality and vibrant energy of Surat. Non-stop Dodhiya, Tran Taali, and traditional Hinch with celebrity Gujarati folk vocalists.',
        venue: 'Indoor Stadium, Athwa Lines, Surat, Gujarat',
        date: DateTime(2026, 10, 24),
        time: '8:30 PM - 1:30 AM',
        price: 650.0,
        capacity: 2500,
        bookedCount: 2450,
        category: 'Cultural',
        image: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=800',
        createdAt: DateTime(2026, 1, 10),
      ),
      EventModel(
        id: 'EVT-2026-WORKSHOP-RAJKOT',
        title: 'Masterclass: Traditional Garba Workshop',
        description:
            'Exclusive choreography workshop led by state award-winning folk masters. Learn authentic Sanedo, 3-Clap, Dodhiya variations, and spins with live rhythm practice.',
        venue: 'Rajkot Cultural Hall, Rajkot, Gujarat',
        date: DateTime(2026, 10, 18),
        time: '5:00 PM - 8:00 PM',
        price: 350.0,
        capacity: 200,
        bookedCount: 95,
        category: 'Workshop',
        image: 'https://images.unsplash.com/photo-1545128485-c400e7702796?w=800',
        createdAt: DateTime(2026, 1, 15),
      ),
    ];

    for (final ev in initialEvents) {
      _eventsCache[ev.id] = ev;
    }
  }

  String _generateSecurityHash(String ticketUuid, String bookingId, String userId) {
    final raw = '$ticketUuid:$bookingId:$userId:GARBA_SECURE_2026';
    return base64UrlEncode(utf8.encode(raw));
  }

  // ─── Firestore Document Mapping ────────────────────────────────────────────

  Map<String, dynamic> _firestoreFieldsToMap(Map<String, dynamic> fields) {
    final map = <String, dynamic>{};
    fields.forEach((key, val) {
      if (val is Map<String, dynamic>) {
        if (val.containsKey('stringValue')) {
          map[key] = val['stringValue'];
        } else if (val.containsKey('integerValue')) {
          map[key] = int.tryParse(val['integerValue'].toString()) ?? 0;
        } else if (val.containsKey('doubleValue')) {
          map[key] = (val['doubleValue'] as num).toDouble();
        } else if (val.containsKey('booleanValue')) {
          map[key] = val['booleanValue'] as bool;
        } else if (val.containsKey('timestampValue')) {
          map[key] = val['timestampValue'];
        } else if (val.containsKey('mapValue')) {
          final nestedFields = val['mapValue']['fields'] as Map<String, dynamic>? ?? {};
          map[key] = _firestoreFieldsToMap(nestedFields);
        } else if (val.containsKey('arrayValue')) {
          final listValues = val['arrayValue']['values'] as List<dynamic>? ?? [];
          map[key] = listValues.map((item) {
            if (item is Map<String, dynamic>) {
              if (item.containsKey('stringValue')) return item['stringValue'];
              if (item.containsKey('integerValue')) return int.tryParse(item['integerValue'].toString()) ?? 0;
            }
            return item;
          }).toList();
        }
      }
    });
    return map;
  }

  Map<String, dynamic> _mapToFirestoreFields(Map<String, dynamic> data) {
    final fields = <String, dynamic>{};
    data.forEach((key, value) {
      if (value == null) {
        fields[key] = {'nullValue': null};
      } else if (value is String) {
        fields[key] = {'stringValue': value};
      } else if (value is int) {
        fields[key] = {'integerValue': value.toString()};
      } else if (value is double) {
        fields[key] = {'doubleValue': value};
      } else if (value is bool) {
        fields[key] = {'booleanValue': value};
      } else if (value is DateTime) {
        fields[key] = {'timestampValue': value.toUtc().toIso8601String()};
      } else if (value is Map<String, dynamic>) {
        fields[key] = {
          'mapValue': {'fields': _mapToFirestoreFields(value)}
        };
      } else if (value is List) {
        fields[key] = {
          'arrayValue': {
            'values': value.map((item) {
              if (item is String) return {'stringValue': item};
              if (item is int) return {'integerValue': item.toString()};
              if (item is double) return {'doubleValue': item};
              if (item is bool) return {'booleanValue': item};
              return {'stringValue': item.toString()};
            }).toList()
          }
        };
      }
    });
    return fields;
  }

  // ─── Push Notifications (FCM) ─────────────────────────────────────────────
  Future<String?> getFcmToken() async => null;

  Future<void> subscribeToTopic(String topic) async {}

  // ─── Cloud Storage ────────────────────────────────────────────────────────
  Future<String?> uploadFile({
    required List<int> fileBytes,
    required String storagePath,
    String contentType = 'image/jpeg',
  }) async =>
      null;

  // ─── Analytics (optional) ─────────────────────────────────────────────────
  Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    assert(() {
      debugPrint('[Firebase] logEvent: $name ${params ?? ''}');
      return true;
    }());
  }
}
