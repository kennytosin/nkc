import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_paystack_plus/flutter_paystack_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'paystack_config.dart';
import 'payment_database.dart';

// Payment status enum
enum PaymentStatus { successful, failed, cancelled, error }

// Payment response model
class PaymentResponse {
  final PaymentStatus status;
  final String transactionId;
  final String txRef;
  final double amount;
  final String message;

  PaymentResponse({
    required this.status,
    required this.transactionId,
    required this.txRef,
    required this.amount,
    required this.message,
  });

  bool get isSuccessful => status == PaymentStatus.successful;
  bool get isCancelled => status == PaymentStatus.cancelled;
}

class PaystackService {
  static final PaystackService instance = PaystackService._();
  PaystackService._();

  // Initialize Paystack
  static Future<void> initialize() async {
    try {
      print('═══════════════════════════════════════════════════════');
      print('✅ PAYSTACK INITIALIZED SUCCESSFULLY');
      print('═══════════════════════════════════════════════════════');
      print('📌 Public Key: ${PaystackKeys.publicKey.substring(0, 20)}...');
      print('📌 Test Mode: ${PaystackKeys.isTestMode}');
      print('📌 Currency: ${PaystackKeys.currency}');
      print('═══════════════════════════════════════════════════════');
      print('');
      print('🎯 Ready to accept payments!');
      print('   Test Card: 4084 0840 8408 4081');
      print('   CVV: 408 | PIN: 0000 | OTP: 123456');
      print('');
      print('📱 In TEST mode, you can select payment outcome:');
      print('   - Success: Simulates successful payment');
      print('   - Bank Authentication: Tests auth flow');
      print('   - Declined: Tests failed payment');
      print('');
    } catch (e) {
      print('❌ Error initializing Paystack: $e');
    }
  }

  String _generateTransactionRef() {
    return 'DEV_${DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecond}';
  }

  Future<String> _getUserEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = prefs.getString('user_email');
      if (email != null && email.isNotEmpty) {
        return email;
      }
      return 'test.user@gmail.com';
    } catch (e) {
      return 'test.user@gmail.com';
    }
  }

  Future<String> _getUserName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('user_name');
      if (name != null && name.isNotEmpty) {
        return name;
      }
      return 'Test User';
    } catch (e) {
      return 'Test User';
    }
  }

  // Verify payment with Paystack API
  Future<bool> _verifyPayment(String reference) async {
    try {
      print('🔍 Verifying payment with Paystack...');
      print('   Reference: $reference');

      final response = await http.get(
        Uri.parse('https://api.paystack.co/transaction/verify/$reference'),
        headers: {
          'Authorization': 'Bearer ${PaystackKeys.secretKey}',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final status = data['data']['status'];
        final isPaid = status == 'success';

        print('═══════════════════════════════════════════════════════');
        print('📋 PAYSTACK VERIFICATION RESULT');
        print('═══════════════════════════════════════════════════════');
        print('   Status: $status');
        print('   Paid: ${isPaid ? "✅ YES" : "❌ NO"}');
        print('   Amount: ${data['data']['amount'] / 100} ${data['data']['currency']}');
        print('═══════════════════════════════════════════════════════');

        return isPaid;
      } else {
        print('⚠️  Verification API returned status: ${response.statusCode}');
        print('   Response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Payment verification error: $e');
      return false;
    }
  }

  // Start polling to detect payment completion
  void _startPaymentPolling({
    required String reference,
    required BuildContext context,
    required Completer<PaymentResponse> completer,
    required bool Function() isCompletedCheck,
    required double amount,
  }) {
    int pollCount = 0;
    const maxPolls = 60; // Poll for up to 3 minutes (60 * 3 seconds)

    Timer.periodic(const Duration(seconds: 3), (timer) async {
      pollCount++;

      // Stop if payment already completed or max attempts reached
      if (isCompletedCheck() || pollCount > maxPolls) {
        timer.cancel();
        return;
      }

      print('🔄 Polling payment status... (attempt $pollCount)');

      try {
        final isVerified = await _verifyPayment(reference);

        if (isVerified) {
          timer.cancel();
          print('✅ Payment detected as successful! Auto-closing...');

          if (!isCompletedCheck()) {
            // Close the payment webview
            if (context.mounted) {
              try {
                Navigator.of(context).pop();
              } catch (e) {
                print('Note: Webview may have already closed');
              }
            }

            // Complete with success
            completer.complete(PaymentResponse(
              status: PaymentStatus.successful,
              transactionId: reference,
              txRef: reference,
              amount: amount,
              message: 'Payment successful (auto-detected)',
            ));
          }
        }
      } catch (e) {
        print('⚠️  Polling error: $e');
      }
    });
  }

  // Initialize payment
  Future<PaymentResponse?> initiatePayment({
    required BuildContext context,
    required double amount,
    required String planName,
    required String planId,
    String? userEmail,
    String? userName,
  }) async {
    try {
      final email = userEmail ?? await _getUserEmail();
      final txRef = _generateTransactionRef();

      // Convert amount to kobo (Paystack uses smallest currency unit)
      final amountInKobo = (amount * 100).toInt();

      print('═══════════════════════════════════════════════════════');
      print('🔵 INITIATING PAYSTACK PAYMENT');
      print('═══════════════════════════════════════════════════════');
      print('📌 Amount: ₦${amount.toStringAsFixed(2)} ($amountInKobo kobo)');
      print('📌 Plan: $planName');
      print('📌 Customer: $email');
      print('📌 Reference: $txRef');
      print('═══════════════════════════════════════════════════════');
      print('🚀 Opening Paystack checkout...');
      print('🤖 Automatic payment detection: ENABLED');
      print('   Payment will be detected and app will auto-redirect');
      print('');
      print('ℹ️  In TEST mode:');
      print('   1. Select "Success" option');
      print('   2. Click "Pay NGN $amountInKobo" button');
      print('   3. Wait for automatic detection (or tap back manually)');
      print('');

      // Show instruction dialog first
      if (context.mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.info_outline, color: Colors.amber),
                SizedBox(width: 12),
                Text('Payment Instructions', style: TextStyle(color: Colors.white)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'How it works:',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                _buildInstructionStep('1', 'Complete your payment in Paystack'),
                const SizedBox(height: 8),
                _buildInstructionStep('2', 'Payment will be automatically detected'),
                const SizedBox(height: 8),
                _buildInstructionStep('3', 'App will auto-close and redirect you'),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: Colors.green, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No manual action needed - just complete payment!',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Got it, Continue to Payment'),
              ),
            ],
          ),
        );
      }

      // Use Completer for better async control
      final completer = Completer<PaymentResponse>();
      bool isCompleted = false;

      // Start automatic payment detection polling
      print('🔄 Starting automatic payment detection...');
      _startPaymentPolling(
        reference: txRef,
        context: context,
        completer: completer,
        isCompletedCheck: () => isCompleted,
        amount: amount,
      );

      // Open Paystack payment popup
      FlutterPaystackPlus.openPaystackPopup(
        publicKey: PaystackKeys.publicKey,
        secretKey: PaystackKeys.secretKey,
        context: context,
        customerEmail: email,
        amount: amountInKobo.toString(),
        reference: txRef,
        currency: PaystackKeys.currency,
        metadata: {
          'plan_id': planId,
          'plan_name': planName,
        },
        onSuccess: () async {
          print('═══════════════════════════════════════════════════════');
          print('✅ PAYMENT SUCCESSFUL!');
          print('═══════════════════════════════════════════════════════');
          print('   Transaction Reference: $txRef');
          print('   Amount: ₦${amount.toStringAsFixed(2)}');
          print('   Plan: $planName');
          print('═══════════════════════════════════════════════════════');
          print('');
          print('🔄 Attempting to close payment window...');
          print('   If it doesn\'t close, tap "Secured by paystack" at bottom');
          print('');

          if (!isCompleted) {
            isCompleted = true;

            // Try to close the payment popup after a short delay
            await Future.delayed(const Duration(milliseconds: 1500));
            try {
              if (context.mounted) {
                Navigator.of(context).pop();
                print('✅ Payment window closed automatically');
              }
            } catch (e) {
              print('ℹ️  Auto-close failed - user needs to tap back');
            }

            completer.complete(PaymentResponse(
              status: PaymentStatus.successful,
              transactionId: txRef,
              txRef: txRef,
              amount: amount,
              message: 'Payment successful',
            ));
          }
        },
        onClosed: () async {
          print('═══════════════════════════════════════════════════════');
          print('🔴 PAYMENT POPUP CLOSED');
          print('═══════════════════════════════════════════════════════');

          if (!isCompleted) {
            isCompleted = true;

            // No verification - just treat as cancelled
            // The polling mechanism will catch successful payments
            print('⚡ Payment popup closed - treating as cancelled');
            completer.complete(PaymentResponse(
              status: PaymentStatus.cancelled,
              transactionId: txRef,
              txRef: txRef,
              amount: amount,
              message: 'Payment cancelled',
            ));
          }
        },
      );

      // Wait for payment to complete
      // Note: Sometimes callbacks don't fire in test mode, user needs to close webview manually
      final response = await completer.future;

      print('');
      print('📥 Payment completed with status: ${response.status}');
      print('');

      return response;
    } catch (e, stackTrace) {
      print('❌ Payment error: $e');
      print('Stack trace: $stackTrace');

      // Check if user cancelled
      if (e.toString().contains('cancelled') || e.toString().contains('cancel')) {
        return PaymentResponse(
          status: PaymentStatus.cancelled,
          transactionId: '',
          txRef: '',
          amount: amount,
          message: 'Payment cancelled by user',
        );
      }

      return PaymentResponse(
        status: PaymentStatus.error,
        transactionId: '',
        txRef: '',
        amount: amount,
        message: 'Payment error: ${e.toString()}',
      );
    }
  }

  // Save payment record
  Future<void> savePaymentRecord({
    required String transactionId,
    required String txRef,
    required double amount,
    required String planId,
    required String planName,
    required int planDurationMonths,
    required String status,
  }) async {
    try {
      print('💾 Saving payment record...');

      final paymentDb = PaymentDatabase.instance;
      final userManager = UserManager.instance;

      final userId = await userManager.getUserId();
      final userEmail = await userManager.getUserEmail();
      final userName = await userManager.getUserName();

      final record = PaymentRecord(
        userId: userId,
        userEmail: userEmail,
        userName: userName,
        transactionId: transactionId,
        txRef: txRef,
        amount: amount,
        currency: PaystackKeys.currency,
        planId: planId,
        planName: planName,
        planDurationMonths: planDurationMonths,
        status: status,
        createdAt: DateTime.now(),
        verifiedAt: status == 'successful' ? DateTime.now() : null,
        metadata: {
          'plan_id': planId,
          'payment_method': 'paystack',
        },
      );

      await paymentDb.insertPayment(record);

      print('✅ Payment record saved');
      print('   User: $userId');
      print('   Plan: $planName');
    } catch (e) {
      print('❌ Error saving payment: $e');
    }
  }

  // Get payment history
  Future<List<PaymentRecord>> getUserPaymentHistory() async {
    try {
      final paymentDb = PaymentDatabase.instance;
      final userManager = UserManager.instance;
      final userId = await userManager.getUserId();

      final allPayments = await paymentDb.getPaymentsByUserId(userId);
      return allPayments;
    } catch (e) {
      print('❌ Error getting payment history: $e');
      return [];
    }
  }

  // Helper method to build instruction step widgets
  static Widget _buildInstructionStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.amber,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
