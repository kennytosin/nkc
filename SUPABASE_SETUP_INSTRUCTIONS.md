# Supabase Setup Instructions

Your Supabase credentials have been configured! Follow these steps to complete the setup.

## ✅ Credentials Configured

- **Project URL:** `https://mmwxmkenjsojevilyxyx.supabase.co`
- **Anon Key:** Configured in [lib/supabase_config.dart](lib/supabase_config.dart)

---

## 📋 Step 1: Create the Payments Table

1. Go to your [Supabase Dashboard](https://app.supabase.com/project/mmwxmkenjsojevilyxyx)
2. Click on **SQL Editor** in the left sidebar
3. Click **New Query**
4. Copy and paste this SQL:

```sql
-- Create payments table
CREATE TABLE IF NOT EXISTS payments (
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
  metadata JSONB
);

-- Create indexes for fast queries
CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_user_email ON payments(user_email);
CREATE INDEX idx_payments_transaction_id ON payments(transaction_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_created_at ON payments(created_at DESC);

-- Enable Row Level Security
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own payments
CREATE POLICY "Users can view their own payments"
  ON payments FOR SELECT
  USING (user_email = auth.email() OR user_id = auth.uid()::text);

-- Policy: Allow inserting payments (for anonymous users making payments)
CREATE POLICY "Allow insert payments"
  ON payments FOR INSERT
  WITH CHECK (true);

-- Policy: Users can update their own payments
CREATE POLICY "Users can update their own payments"
  ON payments FOR UPDATE
  USING (user_email = auth.email() OR user_id = auth.uid()::text);
```

5. Click **Run** to execute the SQL
6. You should see "Success. No rows returned"

---

## 🚀 Step 2: Initialize Supabase in Your App

Add this to your app's initialization (in [lib/main.dart](lib/main.dart)):

```dart
import 'supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await SupabaseConfig.initialize();

  runApp(const MyApp());
}
```

---

## ✅ Step 3: Test the Integration

### Test Payment Sync

1. Make a test payment in your app
2. Check the Supabase dashboard:
   - Go to **Table Editor**
   - Select **payments** table
   - You should see your payment record!

### View in Supabase Dashboard

```
https://app.supabase.com/project/mmwxmkenjsojevilyxyx/editor/payments
```

---

## 🔍 Verify Setup

Run this query in Supabase SQL Editor to check:

```sql
-- Check if table exists
SELECT * FROM payments LIMIT 5;

-- Check row count
SELECT COUNT(*) FROM payments;

-- View recent payments
SELECT
  user_email,
  plan_name,
  amount,
  status,
  created_at
FROM payments
ORDER BY created_at DESC
LIMIT 10;
```

---

## 📊 Useful Queries

### Get all successful payments

```sql
SELECT * FROM payments
WHERE status = 'successful'
ORDER BY created_at DESC;
```

### Get payments by email

```sql
SELECT * FROM payments
WHERE user_email = 'user@example.com'
ORDER BY created_at DESC;
```

### Get revenue summary

```sql
SELECT
  COUNT(*) as total_payments,
  SUM(amount) as total_revenue,
  AVG(amount) as average_payment
FROM payments
WHERE status = 'successful';
```

### Get payments by plan

```sql
SELECT
  plan_name,
  COUNT(*) as count,
  SUM(amount) as revenue
FROM payments
WHERE status = 'successful'
GROUP BY plan_name
ORDER BY revenue DESC;
```

---

## 🔐 Security Notes

### Row Level Security (RLS)

The policies ensure:
- ✅ Users can only view their own payments
- ✅ Anyone can insert payments (needed for anonymous checkout)
- ✅ Users can update their own payments only

### Test Policies

```sql
-- As authenticated user (will only see their payments)
SELECT * FROM payments;

-- As anonymous (can insert, cannot select others' data)
INSERT INTO payments (...) VALUES (...);
```

---

## 🔄 Sync Existing Payments

If you have existing local payments, sync them:

```dart
import 'payment_database.dart';
import 'supabase_config.dart';

// Get all local payments
final userId = await UserManager.instance.getUserId();
final localPayments = await PaymentDatabase.instance.getPaymentsByUserId(userId);

// Sync to Supabase
for (var payment in localPayments) {
  await SupabaseConfig.syncPayment(payment.toJson());
}

print('✅ Synced ${localPayments.length} payments to Supabase');
```

---

## 📱 Real-time Updates (Optional)

Enable real-time subscriptions to payments:

```dart
import 'supabase_config.dart';

// Listen to payment changes
final subscription = SupabaseConfig.client
    .from('payments')
    .stream(primaryKey: ['id'])
    .eq('user_email', userEmail)
    .listen((data) {
      print('Payment updated: $data');
      // Refresh UI
    });

// Don't forget to cancel when done
subscription.cancel();
```

---

## 🐛 Troubleshooting

### Issue: Payments not syncing

**Check:**
1. Supabase credentials are correct
2. Table exists in Supabase
3. RLS policies are set up correctly

**Debug:**
```dart
// Check if Supabase is configured
final isConfigured = await SupabaseConfig.isConfigured();
print('Supabase configured: $isConfigured');

// Test connection
try {
  final response = await SupabaseConfig.client.from('payments').select().limit(1);
  print('✅ Connection successful');
} catch (e) {
  print('❌ Connection failed: $e');
}
```

### Issue: RLS Policy blocking inserts

**Solution:** Check the insert policy allows anonymous inserts

```sql
-- View current policies
SELECT * FROM pg_policies WHERE tablename = 'payments';

-- Drop and recreate if needed
DROP POLICY IF EXISTS "Allow insert payments" ON payments;
CREATE POLICY "Allow insert payments"
  ON payments FOR INSERT
  WITH CHECK (true);
```

---

## ✅ Next Steps

1. ✅ Run the SQL to create the table
2. ✅ Initialize Supabase in main.dart
3. ✅ Test a payment
4. ✅ Verify in Supabase dashboard
5. ✅ Set up real-time sync (optional)

Your payment system is now fully integrated with Supabase! 🚀
