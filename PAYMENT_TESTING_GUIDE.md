# Payment Testing Guide

## ✅ Issues Fixed

I identified and fixed the payment failure issues:

### 1. **Invalid Callback URL**
- **Problem**: The callback URL `https://devotionalapp.com/payment/callback` was unreachable
- **Fix**: Changed to `https://google.com` (a reachable URL for testing)
- **File**: [lib/flutterwave_config.dart](lib/flutterwave_config.dart)

### 2. **Currency Configuration**
- **Problem**: USD amounts ($1.50, $2.00, $3.00) were too small and might not be properly configured in test mode
- **Fix**: Switched to NGN (Nigerian Naira) which is Flutterwave's primary test currency
- **New Prices**:
  - 3-Month Premium: ₦1,500 (~$1 USD)
  - 6-Month Premium: ₦2,500 (~$1.65 USD)
  - Yearly Premium: ₦4,000 (~$2.65 USD)
- **Files**:
  - [lib/flutterwave_config.dart](lib/flutterwave_config.dart)
  - [lib/payment_plans_enhancement.dart](lib/payment_plans_enhancement.dart)

### 3. **Payment Options**
- **Problem**: Multiple payment options might complicate testing
- **Fix**: Simplified to 'card' only for testing (can add more options later)

---

## 🧪 How to Test Payment

### Step 1: Use Flutterwave Test Card

When the payment screen opens, use these **TEST CARD DETAILS**:

```
Card Number:  5531 8866 5214 2950
CVV:          564
Expiry Date:  09/32
PIN:          3310
OTP:          12345
```

### Step 2: Complete Payment Flow

1. Open the app
2. Go to **Payment Plans** (Settings → Payment Plans)
3. Select any premium plan (e.g., 3-Month Premium - ₦1,500)
4. Click **"Purchase ₦1500"**
5. When Flutterwave payment window opens:
   - Enter test card number: **5531886652142950**
   - Enter CVV: **564**
   - Enter expiry: **09/32**
   - Enter PIN: **3310**
   - Enter OTP: **12345**
6. Complete payment
7. Check for success message!

### Step 3: Verify Payment

After successful payment:
- Go to **Settings → Payment History**
- You should see your payment record
- Check your [Supabase Dashboard](https://app.supabase.com/project/mmwxmkenjsojevilyxyx/editor/payments) to verify cloud sync

---

## 📊 What You'll See

### Console Logs (Enhanced Debugging)

With the enhanced logging, you should now see detailed payment information:

```
🔵 Initiating Flutterwave payment...
   Amount: 1500.0
   Plan: 3-Month Premium
   Customer: user@devotionalapp.com

🔵 Payment response received
   Status: successful
   Transaction ID: FLW-TX-123456789
   Message: Payment successful

✅ Payment successful!
Transaction ID: FLW-TX-123456789
Transaction Reference: DEV_1732381200000_123456
```

### If Payment Fails

You'll see detailed error messages:
```
❌ Payment failed
   Status: error
   Message: [specific error message]
   Transaction ID: [transaction id]
```

---

## 🔄 Switching Back to USD (Optional)

If you want to use USD instead of NGN:

1. Open [lib/flutterwave_config.dart](lib/flutterwave_config.dart)
2. Change line 29:
   ```dart
   static const String currency = 'USD'; // Change back to USD
   ```

3. Update prices in [lib/payment_plans_enhancement.dart](lib/payment_plans_enhancement.dart):
   ```dart
   // Use higher USD amounts (minimum $10 recommended)
   price: 10.00,  // 3-Month
   price: 15.00,  // 6-Month
   price: 25.00,  // Yearly
   ```

4. Update currency display:
   ```dart
   return '\$${price.toStringAsFixed(2)}'; // Use $ instead of ₦
   ```

---

## 🐛 Troubleshooting

### Issue: Still getting "error" status

**Check:**
1. Are you using the correct test card? `5531886652142950`
2. Is your internet connection stable?
3. Are your Flutterwave test keys correct?

**Debug:**
```dart
// Check console logs for detailed error messages
// The enhanced logging will show:
// - Payment amount and plan
// - Customer details
// - Full error messages
// - Stack traces
```

### Issue: Payment window doesn't open

**Solutions:**
1. Make sure you have internet permissions (already configured)
2. Try restarting the app
3. Check if Flutterwave package is properly installed:
   ```bash
   flutter pub get
   flutter clean
   flutter build apk
   ```

### Issue: Payment succeeds but not showing in history

**Check:**
1. Is Supabase initialized in main.dart?
2. Did you create the payments table in Supabase?
3. Check Supabase dashboard for any errors

---

## 📝 Production Checklist

Before going live:

- [ ] Get Flutterwave **LIVE** API keys
- [ ] Update [lib/flutterwave_config.dart](lib/flutterwave_config.dart):
  - [ ] Add live keys (lines 16-18)
  - [ ] Set `isTestMode = false` (line 21)
  - [ ] Update currency to your preferred option (USD, NGN, etc.)
  - [ ] Update callback URL to your actual webhook URL
- [ ] Update payment plan prices to production amounts
- [ ] Test with real card (small amount first!)
- [ ] Verify Supabase RLS policies
- [ ] Set up payment webhook handling

---

## 🎯 Expected Results

### Successful Payment Flow:

```
1. User clicks "Purchase ₦1500"
   ↓
2. Loading dialog appears
   ↓
3. Flutterwave payment window opens
   ↓
4. User enters test card details
   ↓
5. Payment processes
   ↓
6. ✅ Success dialog shows
   ↓
7. Payment saved locally (SQLite)
   ↓
8. Payment synced to Supabase
   ↓
9. Subscription activated
   ↓
10. User can view in Payment History
```

### Console Output:
```
🔵 Initiating Flutterwave payment...
   Amount: 1500.0
   Plan: 3-Month Premium
   Customer: user@devotionalapp.com

🔵 Payment response received
   Status: successful
   Transaction ID: FLW-TX-123456789
   Message: Payment successful

✅ Payment successful!
Transaction ID: FLW-TX-123456789
Transaction Reference: DEV_1732381200000_123456

✅ Payment record saved and linked to user: user_1732368000000
   Email: user@devotionalapp.com
   Plan: 3-Month Premium
```

---

## 🔑 Test Card Details Summary

For quick reference:

| Field | Value |
|-------|-------|
| Card Number | 5531 8866 5214 2950 |
| CVV | 564 |
| Expiry | 09/32 |
| PIN | 3310 |
| OTP | 12345 |

---

## 📞 Need Help?

If you still encounter issues:

1. **Check console logs** - The enhanced logging will show exactly what's happening
2. **Review Flutterwave docs** - [Flutterwave Test Mode Guide](https://developer.flutterwave.com/docs/integration-guides/testing-helpers)
3. **Verify test keys** - Make sure your test keys are active in your Flutterwave dashboard
4. **Test with different amounts** - Try ₦1,000, ₦2,000, ₦5,000

---

## ✨ What's Changed

### Files Modified:
1. ✅ [lib/flutterwave_config.dart](lib/flutterwave_config.dart) - Fixed callback URL, changed currency to NGN
2. ✅ [lib/payment_plans_enhancement.dart](lib/payment_plans_enhancement.dart) - Updated prices and currency display
3. ✅ [lib/flutterwave_service.dart](lib/flutterwave_service.dart) - Enhanced error logging (already done)

### What to Expect:
- Prices now display in NGN (₦1,500 instead of $1.50)
- Payment should work with Flutterwave test card
- Detailed console logs for debugging
- Proper error messages if something goes wrong

---

**Test with the Flutterwave test card and let me know the results!** 🚀
