import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// Payment Record Model
class PaymentRecord {
  final int? id;
  final String userId;
  final String userEmail;
  final String userName;
  final String transactionId;
  final String txRef;
  final double amount;
  final String currency;
  final String planId;
  final String planName;
  final int planDurationMonths;
  final String status;
  final DateTime createdAt;
  final DateTime? verifiedAt;
  final Map<String, dynamic>? metadata;

  PaymentRecord({
    this.id,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.transactionId,
    required this.txRef,
    required this.amount,
    required this.currency,
    required this.planId,
    required this.planName,
    required this.planDurationMonths,
    required this.status,
    required this.createdAt,
    this.verifiedAt,
    this.metadata,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'user_email': userEmail,
      'user_name': userName,
      'transaction_id': transactionId,
      'tx_ref': txRef,
      'amount': amount,
      'currency': currency,
      'plan_id': planId,
      'plan_name': planName,
      'plan_duration_months': planDurationMonths,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'verified_at': verifiedAt?.toIso8601String(),
      'metadata': metadata != null ? jsonEncode(metadata) : null,
    };
  }

  factory PaymentRecord.fromMap(Map<String, dynamic> map) {
    return PaymentRecord(
      id: map['id'] as int?,
      userId: map['user_id'] as String,
      userEmail: map['user_email'] as String,
      userName: map['user_name'] as String,
      transactionId: map['transaction_id'] as String,
      txRef: map['tx_ref'] as String,
      amount: (map['amount'] as num).toDouble(),
      currency: map['currency'] as String,
      planId: map['plan_id'] as String,
      planName: map['plan_name'] as String,
      planDurationMonths: map['plan_duration_months'] as int,
      status: map['status'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      verifiedAt: map['verified_at'] != null
          ? DateTime.parse(map['verified_at'] as String)
          : null,
      metadata: map['metadata'] != null
          ? jsonDecode(map['metadata'] as String)
          : null,
    );
  }

  // For Supabase/Backend
  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'user_email': userEmail,
      'user_name': userName,
      'transaction_id': transactionId,
      'tx_ref': txRef,
      'amount': amount,
      'currency': currency,
      'plan_id': planId,
      'plan_name': planName,
      'plan_duration_months': planDurationMonths,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'verified_at': verifiedAt?.toIso8601String(),
      'metadata': metadata,
    };
  }
}

// Payment Database Manager
class PaymentDatabase {
  static final PaymentDatabase instance = PaymentDatabase._init();
  static Database? _database;

  PaymentDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('payments.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        user_email TEXT NOT NULL,
        user_name TEXT NOT NULL,
        transaction_id TEXT NOT NULL UNIQUE,
        tx_ref TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        plan_id TEXT NOT NULL,
        plan_name TEXT NOT NULL,
        plan_duration_months INTEGER NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        verified_at TEXT,
        metadata TEXT
      )
    ''');

    // Create indexes for faster queries
    await db.execute(
      'CREATE INDEX idx_user_id ON payments(user_id)',
    );
    await db.execute(
      'CREATE INDEX idx_transaction_id ON payments(transaction_id)',
    );
    await db.execute(
      'CREATE INDEX idx_user_email ON payments(user_email)',
    );
  }

  // Insert payment record
  Future<int> insertPayment(PaymentRecord payment) async {
    final db = await database;
    final id = await db.insert(
      'payments',
      payment.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Sync to backend
    await _syncToBackend(payment);

    return id;
  }

  // Get all payments for a user
  Future<List<PaymentRecord>> getPaymentsByUserId(String userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) => PaymentRecord.fromMap(maps[i]));
  }

  // Get all payments for a user by email
  Future<List<PaymentRecord>> getPaymentsByEmail(String email) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'user_email = ?',
      whereArgs: [email],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) => PaymentRecord.fromMap(maps[i]));
  }

  // Get payment by transaction ID
  Future<PaymentRecord?> getPaymentByTransactionId(String txId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'transaction_id = ?',
      whereArgs: [txId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return PaymentRecord.fromMap(maps[0]);
  }

  // Get successful payments for a user
  Future<List<PaymentRecord>> getSuccessfulPayments(String userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'payments',
      where: 'user_id = ? AND status = ?',
      whereArgs: [userId, 'successful'],
      orderBy: 'created_at DESC',
    );

    return List.generate(maps.length, (i) => PaymentRecord.fromMap(maps[i]));
  }

  // Update payment status
  Future<void> updatePaymentStatus({
    required String transactionId,
    required String status,
    DateTime? verifiedAt,
  }) async {
    final db = await database;
    await db.update(
      'payments',
      {
        'status': status,
        'verified_at': verifiedAt?.toIso8601String(),
      },
      where: 'transaction_id = ?',
      whereArgs: [transactionId],
    );
  }

  // Get total amount spent by user
  Future<double> getTotalSpent(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM payments WHERE user_id = ? AND status = ?',
      [userId, 'successful'],
    );

    return (result[0]['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Get payment count for user
  Future<int> getPaymentCount(String userId) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM payments WHERE user_id = ?',
      [userId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Delete all payments (for testing)
  Future<void> deleteAllPayments() async {
    final db = await database;
    await db.delete('payments');
  }

  // Sync payment to backend (Supabase)
  Future<void> _syncToBackend(PaymentRecord payment) async {
    try {
      // Get Supabase URL and key from environment or SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final supabaseUrl = prefs.getString('supabase_url');
      final supabaseKey = prefs.getString('supabase_anon_key');

      if (supabaseUrl == null || supabaseKey == null) {
        print('⚠️ Supabase credentials not configured. Skipping backend sync.');
        return;
      }

      // Send to Supabase
      final response = await http.post(
        Uri.parse('$supabaseUrl/rest/v1/payments'),
        headers: {
          'apikey': supabaseKey,
          'Authorization': 'Bearer $supabaseKey',
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal',
        },
        body: jsonEncode(payment.toJson()),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('✅ Payment synced to Supabase');
        print('   Transaction: ${payment.transactionId}');
      } else {
        print('⚠️ Failed to sync payment to Supabase: ${response.statusCode}');
        print('   Response: ${response.body}');
        if (response.statusCode == 401 || response.statusCode == 403) {
          print('   💡 This is due to Row Level Security (RLS) policies.');
          print('   💡 Payment is saved locally and can be synced later.');
        }
      }
    } catch (e) {
      print('⚠️ Error syncing payment to backend: $e');
      // Don't throw - local storage is still working
    }
  }

  // Sync payments FROM Supabase (for cross-device access)
  Future<int> syncPaymentsFromSupabase(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final supabaseUrl = prefs.getString('supabase_url');
      final supabaseKey = prefs.getString('supabase_anon_key');

      if (supabaseUrl == null || supabaseKey == null) {
        print('⚠️ Supabase not configured. Using local payments only.');
        return 0;
      }

      print('☁️  Loading payment history from cloud...');

      // Fetch user's payments from Supabase
      final response = await http.get(
        Uri.parse('$supabaseUrl/rest/v1/payments?user_id=eq.$userId&select=*&order=created_at.desc'),
        headers: {
          'apikey': supabaseKey,
          'Authorization': 'Bearer $supabaseKey',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        if (data.isEmpty) {
          print('   No cloud payments found for user');
          return 0;
        }

        int syncedCount = 0;
        final db = await database;

        for (var paymentData in data) {
          // Check if payment already exists locally
          final txId = paymentData['transaction_id'] as String;
          final existing = await getPaymentByTransactionId(txId);

          if (existing == null) {
            // Payment doesn't exist locally - add it
            final payment = PaymentRecord(
              userId: paymentData['user_id'] as String,
              userEmail: paymentData['user_email'] as String,
              userName: paymentData['user_name'] as String,
              transactionId: txId,
              txRef: paymentData['tx_ref'] as String,
              amount: (paymentData['amount'] as num).toDouble(),
              currency: paymentData['currency'] as String,
              planId: paymentData['plan_id'] as String,
              planName: paymentData['plan_name'] as String,
              planDurationMonths: paymentData['plan_duration_months'] as int,
              status: paymentData['status'] as String,
              createdAt: DateTime.parse(paymentData['created_at'] as String),
              verifiedAt: paymentData['verified_at'] != null
                  ? DateTime.parse(paymentData['verified_at'] as String)
                  : null,
              metadata: paymentData['metadata'] != null
                  ? Map<String, dynamic>.from(paymentData['metadata'])
                  : null,
            );

            // Insert without triggering backend sync (to avoid duplicate sync)
            await db.insert(
              'payments',
              payment.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            syncedCount++;
          }
        }

        if (syncedCount > 0) {
          print('✅ Synced $syncedCount payment(s) from cloud');
        } else {
          print('   All payments already in local database');
        }

        return syncedCount;
      } else {
        print('⚠️  Failed to fetch payments: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      print('⚠️  Failed to sync payments from cloud: $e');
      return 0;
    }
  }
}

// User Manager - handles user profile and linking
class UserManager {
  static final UserManager instance = UserManager._init();
  UserManager._init();

  // Get current user ID (from Google Sign-In or generate one)
  Future<String> getUserId() async {
    final prefs = await SharedPreferences.getInstance();

    // Try to get existing user ID
    String? userId = prefs.getString('user_id');

    if (userId == null) {
      // Generate a unique user ID if none exists
      userId = 'user_${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString('user_id', userId);
    }

    return userId;
  }

  // Get user email
  Future<String> getUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_email') ?? 'user@devotionalapp.com';
  }

  // Get user name
  Future<String> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name') ?? 'Devotional User';
  }

  // Set user profile (call this after Google Sign-In)
  Future<void> setUserProfile({
    required String userId,
    required String email,
    required String name,
    String? photoUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', userId);
    await prefs.setString('user_email', email);
    await prefs.setString('user_name', name);
    if (photoUrl != null) {
      await prefs.setString('user_photo_url', photoUrl);
    }
  }

  // Clear user profile (on logout)
  Future<void> clearUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('user_email');
    await prefs.remove('user_name');
    await prefs.remove('user_photo_url');
  }

  // Check if user is logged in
  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') != null;
  }

  // Get user profile
  Future<Map<String, String>> getUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'user_id': prefs.getString('user_id') ?? '',
      'email': prefs.getString('user_email') ?? '',
      'name': prefs.getString('user_name') ?? '',
      'photo_url': prefs.getString('user_photo_url') ?? '',
    };
  }
}
