// Paystack Configuration
//
// IMPORTANT: Before going to production, you MUST:
// 1. Get your API keys from: https://dashboard.paystack.com/#/settings/developer
// 2. Replace the test keys below with your actual production keys
// 3. Set isTestMode to false
// 4. Never commit your production keys to version control

class PaystackKeys {
  // Test Keys (for development only)
  // Get these from: https://dashboard.paystack.com/#/settings/developer
  static const String testPublicKey = 'pk_test_9dd37d69842f6b713adf0fe9c5520c1aa54750db';
  static const String testSecretKey = 'sk_test_c88ef9567db8c43d4ff823437aa5b1416fad8868';

  // Production Keys (add these when ready for production)
  static const String livePublicKey = 'pk_live_YOUR_PUBLIC_KEY_HERE';
  static const String liveSecretKey = 'sk_live_YOUR_SECRET_KEY_HERE';

  // Environment settings
  static const bool isTestMode = true; // Set to false for production

  // Get active keys based on mode
  static String get publicKey => isTestMode ? testPublicKey : livePublicKey;
  static String get secretKey => isTestMode ? testSecretKey : liveSecretKey;

  // Payment configuration
  static const String currency = 'NGN'; // Paystack primarily uses NGN
  static const String companyName = 'Devotional App';
}

// HOW TO GET YOUR PAYSTACK API KEYS:
//
// 1. Sign up or log in at: https://dashboard.paystack.com/
// 2. Go to Settings > API Keys & Webhooks
// 3. Copy your Public Key and Secret Key
// 4. For testing, use the TEST keys (they start with pk_test_ and sk_test_)
// 5. For production, use the LIVE keys (they start with pk_live_ and sk_live_)
//
// PAYSTACK ADVANTAGES FOR NIGERIAN APPS:
// - Built specifically for Africa
// - Excellent NGN support
// - Local payment methods (Bank Transfer, USSD, QR, etc.)
// - Lower fees for Nigerian transactions
// - Better customer support in African timezone
// - Instant settlement
// - Easy testing
//
// SUPPORTED PAYMENT METHODS:
// - Card (Mastercard, Visa, Verve)
// - Bank Transfer
// - USSD
// - Mobile Money
// - QR Code
// - Bank Account
//
// TEST CARDS:
// - Success: 4084 0840 8408 4081 (CVV: 408, Expiry: any future date, PIN: 0000, OTP: 123456)
// - Decline (Insufficient Funds): 5060 6666 6666 6666 6666 (CVV: 123)
// - Timeout: 5078 5078 5078 5078 (CVV: 081)
//
// CURRENCIES SUPPORTED:
// - NGN (Nigerian Naira) - Primary
// - USD (US Dollar)
// - GHS (Ghanaian Cedi)
// - KES (Kenyan Shilling)
// - ZAR (South African Rand)
