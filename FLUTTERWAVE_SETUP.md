# Flutterwave Integration Guide

This guide will help you set up and configure Flutterwave payments in your Devotional App.

## Table of Contents
1. [Getting Started](#getting-started)
2. [Configuration](#configuration)
3. [Testing](#testing)
4. [Going to Production](#going-to-production)
5. [Troubleshooting](#troubleshooting)

---

## Getting Started

### 1. Create a Flutterwave Account

1. Visit [Flutterwave Dashboard](https://dashboard.flutterwave.com/signup)
2. Sign up for a free account
3. Complete your business profile verification
4. Once verified, you'll get access to test and live API keys

### 2. Get Your API Keys

1. Log in to your [Flutterwave Dashboard](https://dashboard.flutterwave.com/login)
2. Navigate to **Settings** > **API Keys**
3. You'll see two sets of keys:
   - **Test Keys** (for development)
   - **Live Keys** (for production)

4. Copy the following keys:
   - Public Key (starts with `FLWPUBK_TEST-` for test mode)
   - Secret Key (starts with `FLWSECK_TEST-` for test mode)
   - Encryption Key

---

## Configuration

### Step 1: Add Your API Keys

Open the file `lib/flutterwave_config.dart` and replace the placeholder values:

```dart
class FlutterwaveKeys {
  // Test Keys (for development only)
  static const String testPublicKey = 'FLWPUBK_TEST-your-actual-test-public-key-here';
  static const String testSecretKey = 'FLWSECK_TEST-your-actual-test-secret-key-here';
  static const String testEncryptionKey = 'FLWSECK_TEST-your-actual-encryption-key-here';

  // Production Keys (add when ready for production)
  static const String livePublicKey = 'FLWPUBK-your-actual-live-public-key-here';
  static const String liveSecretKey = 'FLWSECK-your-actual-live-secret-key-here';
  static const String liveEncryptionKey = 'FLWSECK-your-actual-live-encryption-key-here';

  // Set to true for testing, false for production
  static const bool isTestMode = true;

  // ... rest of the file
}
```

### Step 2: Configure Currency and Payment Methods

In the same file (`lib/flutterwave_config.dart`), you can customize:

```dart
// Change currency based on your location
static const String currency = 'USD'; // or 'NGN', 'GHS', 'KES', etc.

// Available payment methods to show users
static const String paymentOptions = 'card,mobilemoney,ussd,account,banktransfer';
```

#### Supported Currencies:
- **USD** - US Dollar
- **NGN** - Nigerian Naira
- **GHS** - Ghanaian Cedi
- **KES** - Kenyan Shilling
- **ZAR** - South African Rand
- **UGX** - Ugandan Shilling
- **TZS** - Tanzanian Shilling
- And more...

#### Payment Methods:
- `card` - Credit/Debit Cards (Visa, Mastercard, Verve)
- `mobilemoney` - MTN, Vodafone, Airtel, etc.
- `ussd` - Bank USSD codes
- `account` - Direct bank account
- `banktransfer` - Bank transfer
- `mpesa` - M-Pesa (Kenya)

### Step 3: Update Business Information

```dart
static const String businessName = 'Your App Name';
static const String businessLogo = 'https://your-domain.com/logo.png';
static const String callbackUrl = 'https://your-domain.com/payment/callback';
```

---

## Testing

### Test Mode

By default, the app runs in **test mode** (`isTestMode = true`). This means:
- No real money is charged
- You can test the payment flow
- Transactions are simulated

### Test Cards

Flutterwave provides test cards for testing:

#### Successful Payment
- **Card Number:** 5531886652142950
- **CVV:** 564
- **Expiry:** 09/32
- **PIN:** 3310
- **OTP:** 12345

#### Failed Payment
- **Card Number:** 5531886652142950
- **CVV:** 564
- **Expiry:** 09/32
- **PIN:** 3310
- **OTP:** 12344 (different OTP)

### Testing the Integration

1. Run your app
2. Navigate to the subscription plans page
3. Select a plan
4. Complete the payment using test cards
5. Verify the subscription is activated

---

## Going to Production

### Before Launching

⚠️ **IMPORTANT CHECKLIST:**

- [ ] Get your business verified on Flutterwave
- [ ] Obtain your **LIVE** API keys from the dashboard
- [ ] Update `flutterwave_config.dart` with live keys
- [ ] Set `isTestMode = false` in `flutterwave_config.dart`
- [ ] Test thoroughly in production mode
- [ ] Implement webhook for payment verification (see below)
- [ ] Set up proper error logging
- [ ] **NEVER** commit your production API keys to version control

### Production Configuration

```dart
// In lib/flutterwave_config.dart
static const bool isTestMode = false; // ⚠️ Set to false for production
```

### Security Best Practices

1. **Never hardcode production keys in your app**
   - Consider using environment variables
   - Use Flutter's build configuration
   - Implement secure key storage

2. **Always verify payments on your backend**
   - Don't trust client-side verification alone
   - Implement webhook verification
   - Use Flutterwave's verification API

3. **Implement webhook verification**
   ```dart
   // Example webhook implementation (backend)
   Future<bool> verifyPaymentWebhook(String transactionId) async {
     final response = await http.get(
       Uri.parse('https://api.flutterwave.com/v3/transactions/$transactionId/verify'),
       headers: {
         'Authorization': 'Bearer ${FlutterwaveKeys.secretKey}',
       },
     );

     if (response.statusCode == 200) {
       final data = json.decode(response.body);
       return data['data']['status'] == 'successful' &&
              data['data']['amount'] == expectedAmount;
     }
     return false;
   }
   ```

---

## Payment Verification

### Client-Side Verification (Current Implementation)

The app currently implements basic client-side verification in `lib/flutterwave_service.dart`:

```dart
Future<bool> verifyPayment({
  required String transactionId,
  required String txRef,
}) async {
  // In test mode, automatically approve
  if (FlutterwaveKeys.isTestMode) {
    return true;
  }

  // TODO: Implement actual backend verification
  return true;
}
```

### Backend Verification (Recommended for Production)

For production, implement server-side verification:

1. Set up a backend server
2. Implement Flutterwave webhook endpoint
3. Verify payment status via API
4. Update subscription in your database

Example backend verification:

```dart
// Backend endpoint: /api/verify-payment
Future<bool> verifyPaymentOnBackend(String transactionId) async {
  try {
    final response = await http.get(
      Uri.parse('https://api.flutterwave.com/v3/transactions/$transactionId/verify'),
      headers: {
        'Authorization': 'Bearer YOUR_SECRET_KEY',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      // Check if payment was successful
      if (data['status'] == 'success' &&
          data['data']['status'] == 'successful') {

        // Verify amount matches what was expected
        final paidAmount = data['data']['amount'];
        final currency = data['data']['currency'];

        // Update subscription in database
        // Send confirmation to user

        return true;
      }
    }
    return false;
  } catch (e) {
    print('Verification error: $e');
    return false;
  }
}
```

---

## Troubleshooting

### Common Issues

#### 1. "Invalid Public Key" Error
**Solution:** Verify you've copied the correct public key from Flutterwave dashboard

#### 2. Payment Window Not Opening
**Solution:**
- Check internet connectivity
- Verify API keys are correct
- Ensure test mode is enabled for testing

#### 3. Payment Successful but Subscription Not Activated
**Solution:**
- Check the payment verification logic
- Verify the transaction ID is being saved
- Check app logs for errors

#### 4. "Currency Not Supported" Error
**Solution:** Change the currency in `flutterwave_config.dart` to a supported one for your region

### Debug Mode

Enable detailed logging by checking the console output. Look for:
- `✅` Success messages
- `❌` Error messages
- Transaction IDs
- Payment status updates

### Getting Help

1. **Flutterwave Documentation:** https://developer.flutterwave.com/docs
2. **Flutterwave Support:** support@flutterwave.com
3. **Developer Community:** https://developer.flutterwave.com/discuss

---

## Additional Features

### Viewing Payment History

Users can view their last payment:

```dart
final lastPayment = await FlutterwaveService.instance.getLastPayment();
if (lastPayment != null) {
  print('Last payment: ${lastPayment['transaction_id']}');
  print('Amount: ${lastPayment['amount']}');
  print('Date: ${lastPayment['date']}');
}
```

### Customizing Payment UI

You can customize the payment experience in `lib/flutterwave_config.dart`:

```dart
static const String businessName = 'Your App Name';
static const String businessLogo = 'https://your-logo-url.png';
```

---

## Next Steps

1. ✅ Configure your API keys
2. ✅ Test the payment flow
3. ✅ Verify subscriptions are activated correctly
4. ✅ Set up webhook verification
5. ✅ Deploy to production

---

## Support

For issues with this integration, check:
- [Flutterwave Documentation](https://developer.flutterwave.com/docs)
- [Flutter Package Documentation](https://pub.dev/packages/flutterwave_standard)

**Happy coding! 🚀**
