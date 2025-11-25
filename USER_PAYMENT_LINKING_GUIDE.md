# User Payment Linking Guide

This guide explains how payments are linked to user profiles in your Devotional App.

## Overview

Every payment made through Flutterwave is automatically linked to the user's profile with:
- **User ID** - Unique identifier for the user
- **Email Address** - User's email (from Google Sign-In or manual entry)
- **Name** - User's display name
- **Payment History** - All transactions linked to the user
- **Backend Sync** - Automatic synchronization to Supabase (if configured)

---

## How It Works

### 1. User Profile Creation

When a user opens the app, a unique profile is automatically created:

```dart
// Automatically generated on first launch
User ID: user_1234567890
Email: user@devotionalapp.com (default)
Name: Devotional User (default)
```

### 2. Google Sign-In Integration (Recommended)

Update the user profile after Google Sign-In:

```dart
import 'package:google_sign_in/google_sign_in.dart';
import 'payment_database.dart';

// After successful Google Sign-In
final GoogleSignInAccount? account = await GoogleSignIn().signIn();

if (account != null) {
  // Link payment profile to Google account
  await UserManager.instance.setUserProfile(
    userId: account.id,
    email: account.email,
    name: account.displayName ?? 'User',
    photoUrl: account.photoUrl,
  );
}
```

### 3. Payment Linking

Every payment is automatically linked with:

```dart
PaymentRecord {
  userId: "google_user_123456",
  userEmail: "john@example.com",
  userName: "John Doe",
  transactionId: "FLW-TX-123456789",
  amount: 1.50,
  planName: "3-Month Premium",
  status: "successful",
  createdAt: 2025-11-23 10:30:00,
  // ... more fields
}
```

---

## Database Structure

### Local Database (SQLite)

Payments are stored locally in `payments.db`:

```sql
CREATE TABLE payments (
  id INTEGER PRIMARY KEY,
  user_id TEXT NOT NULL,           -- Links to user profile
  user_email TEXT NOT NULL,         -- User's email
  user_name TEXT NOT NULL,          -- User's name
  transaction_id TEXT UNIQUE,       -- Flutterwave transaction ID
  tx_ref TEXT,                      -- Transaction reference
  amount REAL,                      -- Payment amount
  currency TEXT,                    -- USD, NGN, etc.
  plan_id TEXT,                     -- Subscription plan ID
  plan_name TEXT,                   -- Plan name
  plan_duration_months INTEGER,     -- Duration in months
  status TEXT,                      -- successful, failed, cancelled
  created_at TEXT,                  -- Payment date
  verified_at TEXT,                 -- Verification date
  metadata TEXT                     -- Additional data (JSON)
);

-- Indexes for fast queries
CREATE INDEX idx_user_id ON payments(user_id);
CREATE INDEX idx_user_email ON payments(user_email);
CREATE INDEX idx_transaction_id ON payments(transaction_id);
```

### Backend Database (Supabase)

Create this table in your Supabase project:

```sql
CREATE TABLE payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id TEXT NOT NULL,
  user_email TEXT NOT NULL,
  user_name TEXT NOT NULL,
  transaction_id TEXT UNIQUE NOT NULL,
  tx_ref TEXT NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  currency TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  plan_name TEXT NOT NULL,
  plan_duration_months INTEGER NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  verified_at TIMESTAMPTZ,
  metadata JSONB,

  -- Indexes
  CONSTRAINT payments_transaction_id_key UNIQUE (transaction_id)
);

-- Create indexes
CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_user_email ON payments(user_email);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_created_at ON payments(created_at DESC);

-- Enable Row Level Security (RLS)
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only see their own payments
CREATE POLICY "Users can view their own payments"
  ON payments FOR SELECT
  USING (auth.uid()::text = user_id OR auth.email() = user_email);

-- Policy: Insert new payments
CREATE POLICY "Allow authenticated users to insert payments"
  ON payments FOR INSERT
  TO authenticated
  WITH CHECK (true);
```

---

## Setting Up Supabase Sync

### Step 1: Configure Supabase

1. Go to your [Supabase Dashboard](https://app.supabase.com/)
2. Create a new project or select existing
3. Get your credentials:
   - Project URL: `https://xxxxx.supabase.co`
   - Anon Key: `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

### Step 2: Store Credentials

```dart
import 'package:shared_preferences/shared_preferences.dart';

final prefs = await SharedPreferences.getInstance();
await prefs.setString('supabase_url', 'https://xxxxx.supabase.co');
await prefs.setString('supabase_anon_key', 'your-anon-key-here');
```

### Step 3: Automatic Sync

Payments are automatically synced to Supabase after each transaction. The sync happens in the background in `PaymentDatabase._syncToBackend()`.

---

## Using the Payment System

### Get User's Payment History

```dart
import 'flutterwave_service.dart';

// Get all payments for current user
final payments = await FlutterwaveService.instance.getUserPaymentHistory();

for (var payment in payments) {
  print('${payment.planName}: \$${payment.amount}');
  print('Status: ${payment.status}');
  print('Date: ${payment.createdAt}');
}
```

### Get Last Payment

```dart
final lastPayment = await FlutterwaveService.instance.getLastPayment();

if (lastPayment != null) {
  print('Last payment: ${lastPayment.planName}');
  print('Amount: \$${lastPayment.amount}');
}
```

### Get Total Spent

```dart
final totalSpent = await FlutterwaveService.instance.getTotalSpent();
print('Total spent: \$${totalSpent.toStringAsFixed(2)}');
```

### Get Payment Count

```dart
final count = await FlutterwaveService.instance.getPaymentCount();
print('Total payments: $count');
```

---

## Payment History UI

Navigate to the payment history page:

```dart
import 'payment_history_page.dart';

// Navigate to payment history
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (context) => const PaymentHistoryPage(),
  ),
);
```

### Features:
- ✅ View all payment history
- ✅ See payment details
- ✅ Track total spent
- ✅ Filter by user
- ✅ Payment status indicators
- ✅ Transaction IDs
- ✅ Detailed payment information

---

## Querying Payments

### By User ID

```dart
final userId = await UserManager.instance.getUserId();
final payments = await PaymentDatabase.instance.getPaymentsByUserId(userId);
```

### By Email

```dart
final payments = await PaymentDatabase.instance.getPaymentsByEmail('user@example.com');
```

### By Transaction ID

```dart
final payment = await PaymentDatabase.instance.getPaymentByTransactionId('FLW-TX-123');
```

### Successful Payments Only

```dart
final successfulPayments = await PaymentDatabase.instance.getSuccessfulPayments(userId);
```

---

## Multi-Device Sync

### Scenario: User switches devices

When a user logs in on a new device:

1. **Local Storage**: Empty on new device
2. **Supabase Backend**: Has all payment history
3. **Sync Solution**: Fetch from Supabase on login

```dart
// After Google Sign-In on new device
await UserManager.instance.setUserProfile(
  userId: account.id,
  email: account.email,
  name: account.displayName ?? 'User',
);

// TODO: Implement - Fetch payment history from Supabase
// final response = await Supabase.instance.client
//   .from('payments')
//   .select()
//   .eq('user_email', account.email);
//
// for (var payment in response) {
//   await PaymentDatabase.instance.insertPayment(
//     PaymentRecord.fromMap(payment)
//   );
// }
```

---

## Security Best Practices

### 1. Row Level Security (RLS)

Always enable RLS on Supabase:
- Users can only see their own payments
- Prevents unauthorized access

### 2. Verify Payment Server-Side

Never trust client-side payment verification:

```dart
// Backend verification (recommended)
final response = await http.get(
  Uri.parse('https://api.flutterwave.com/v3/transactions/$txId/verify'),
  headers: {'Authorization': 'Bearer $secretKey'},
);
```

### 3. Encrypt Sensitive Data

Consider encrypting payment metadata before storing.

---

## Testing

### Test with Multiple Users

1. **Clear current profile**:
```dart
await UserManager.instance.clearUserProfile();
```

2. **Create test user 1**:
```dart
await UserManager.instance.setUserProfile(
  userId: 'test_user_1',
  email: 'user1@test.com',
  name: 'Test User 1',
);
```

3. **Make payment** - linked to user1@test.com

4. **Create test user 2**:
```dart
await UserManager.instance.setUserProfile(
  userId: 'test_user_2',
  email: 'user2@test.com',
  name: 'Test User 2',
);
```

5. **Verify separation** - User 2 should not see User 1's payments

---

## Migration from Old System

If you have existing payments without user links:

```dart
// Update old payments with current user
final prefs = await SharedPreferences.getInstance();
final oldTxId = prefs.getString('last_payment_txid');

if (oldTxId != null) {
  final userId = await UserManager.instance.getUserId();
  final userEmail = await UserManager.instance.getUserEmail();

  // Create payment record for old transaction
  await PaymentDatabase.instance.insertPayment(
    PaymentRecord(
      userId: userId,
      userEmail: userEmail,
      userName: await UserManager.instance.getUserName(),
      transactionId: oldTxId,
      txRef: prefs.getString('last_payment_txref') ?? '',
      amount: prefs.getDouble('last_payment_amount') ?? 0.0,
      currency: 'USD',
      planId: prefs.getString('last_payment_plan') ?? '',
      planName: 'Unknown Plan',
      planDurationMonths: 3,
      status: prefs.getString('last_payment_status') ?? 'unknown',
      createdAt: DateTime.parse(
        prefs.getString('last_payment_date') ?? DateTime.now().toIso8601String()
      ),
    ),
  );
}
```

---

## Common Use Cases

### 1. Check if User Has Active Subscription

```dart
final payments = await FlutterwaveService.instance.getUserPaymentHistory();
final hasActiveSubscription = payments.any(
  (p) => p.status == 'successful' &&
         p.createdAt.isAfter(DateTime.now().subtract(Duration(days: 90)))
);
```

### 2. Get User's Most Recent Plan

```dart
final lastPayment = await FlutterwaveService.instance.getLastPayment();
if (lastPayment != null && lastPayment.status == 'successful') {
  print('Current plan: ${lastPayment.planName}');
}
```

### 3. Calculate Lifetime Value

```dart
final totalSpent = await FlutterwaveService.instance.getTotalSpent();
print('Lifetime value: \$${totalSpent.toStringAsFixed(2)}');
```

---

## Troubleshooting

### Issue: Payments not showing for user

**Solution**: Check user ID consistency
```dart
final userId = await UserManager.instance.getUserId();
print('Current user ID: $userId');

final payments = await PaymentDatabase.instance.getPaymentsByUserId(userId);
print('Payments found: ${payments.length}');
```

### Issue: Duplicate payments after device switch

**Solution**: Use transaction ID uniqueness
- Database has UNIQUE constraint on `transaction_id`
- Duplicate inserts will fail silently

### Issue: Backend sync failing

**Solution**: Check Supabase credentials
```dart
final prefs = await SharedPreferences.getInstance();
print('Supabase URL: ${prefs.getString('supabase_url')}');
print('Key configured: ${prefs.getString('supabase_anon_key') != null}');
```

---

## Next Steps

1. ✅ Integrate Google Sign-In for user authentication
2. ✅ Set up Supabase project and configure credentials
3. ✅ Add payment history button to your app
4. ✅ Test with multiple test users
5. ✅ Implement payment history sync from Supabase

---

## Support

For questions or issues with payment linking:
- Check the payment database: `lib/payment_database.dart`
- Review payment service: `lib/flutterwave_service.dart`
- See payment history UI: `lib/payment_history_page.dart`

**Happy coding! 🚀**
