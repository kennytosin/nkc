# Paystack Integration Setup Guide

## ✅ What's Been Done

I've successfully integrated Paystack payment gateway into your devotional app!

### Changes Made:

1. ✅ **Replaced Flutterwave with Paystack**
   - Removed: `flutterwave_standard` package
   - Added: `flutter_paystack_plus` package

2. ✅ **Created Paystack Configuration**
   - File: [lib/paystack_config.dart](lib/paystack_config.dart)
   - Ready for your API keys

3. ✅ **Created Paystack Service**
   - File: [lib/paystack_service.dart](lib/paystack_service.dart)
   - Full payment processing implementation
   - Comprehensive logging for debugging
   - User profile linking
   - Payment history tracking

4. ✅ **Updated Pricing to NGN**
   - 3-Month Premium: **₦5,000** (~$3 USD)
   - 6-Month Premium: **₦8,000** (~$5 USD) - Best value!
   - Yearly Premium: **₦12,000** (~$7.50 USD) - Maximum savings

5. ✅ **Updated Payment Flow**
   - File: [lib/payment_plans_enhancement.dart](lib/payment_plans_enhancement.dart)
   - Now uses `PaystackService` instead of Flutterwave

6. ✅ **Updated Main App**
   - File: [lib/main.dart](lib/main.dart)
   - Initializes Paystack on app startup

---

## 🔑 Get Your Paystack API Keys

### Step 1: Create Paystack Account
1. Go to: https://dashboard.paystack.com/signup
2. Sign up with your email
3. Verify your email address
4. Complete your business profile

### Step 2: Get Test API Keys
1. Log in to: https://dashboard.paystack.com/
2. Click on **Settings** in the left sidebar
3. Click on **API Keys & Webhooks**
4. You'll see your **Test Keys**:
   - **Public Key**: Starts with `pk_test_...`
   - **Secret Key**: Starts with `sk_test_...`

### Step 3: Add Keys to Your App
Open [lib/paystack_config.dart](lib/paystack_config.dart:13-14) and update:

```dart
static const String testPublicKey = 'pk_test_YOUR_PUBLIC_KEY_HERE';
static const String testSecretKey = 'sk_test_YOUR_SECRET_KEY_HERE';
```

Replace `YOUR_PUBLIC_KEY_HERE` and `YOUR_SECRET_KEY_HERE` with your actual keys.

---

## 🧪 How to Test Payment

### Test Card Details

Paystack provides test cards for different scenarios:

#### ✅ Successful Payment
```
Card Number: 4084 0840 8408 4081
CVV: 408
Expiry: Any future date (e.g., 12/25)
PIN: 0000
OTP: 123456
```

#### ❌ Declined (Insufficient Funds)
```
Card Number: 5060 6666 6666 6666 6666
CVV: 123
Expiry: Any future date
```

#### ⏱️ Timeout
```
Card Number: 5078 5078 5078 5078
CVV: 081
Expiry: Any future date
```

### Testing Steps

1. **Add your API keys** to [lib/paystack_config.dart](lib/paystack_config.dart)

2. **Hot restart your app** (press `R` in terminal)

3. **Navigate to Payment Plans**:
   - Go to Settings → Payment Plans
   - Select any premium plan (e.g., "3-Month Premium - ₦5,000")

4. **Click "Purchase"** and confirm

5. **Enter test card details**:
   - Use the successful payment card above
   - Follow the prompts (PIN, OTP)

6. **Complete payment**

7. **Verify**:
   - Check console logs for detailed payment flow
   - Go to Settings → Payment History to see the record
   - Check your Supabase dashboard for cloud sync

---

## 📊 Console Logs

You'll see detailed logs like:

```
═══════════════════════════════════════════════════════
🔵 PAYSTACK PAYMENT CONFIGURATION
═══════════════════════════════════════════════════════
📌 Public Key: pk_test_3213556ac77bfe...
📌 Currency: NGN
📌 Amount: ₦5000.00
📌 Amount in kobo: 500000
📌 Test Mode: true
═══════════════════════════════════════════════════════
👤 CUSTOMER DETAILS
═══════════════════════════════════════════════════════
   Name: Test User
   Email: test.user@gmail.com
   TX Ref: DEV_1763930605308_647228
   Plan: 3-Month Premium
═══════════════════════════════════════════════════════
🚀 Initiating Paystack payment...
   Waiting for user interaction...
═══════════════════════════════════════════════════════
📥 PAYMENT RESPONSE RECEIVED
═══════════════════════════════════════════════════════
   Status: true
   Message: Approved
   Reference: DEV_1763930605308_647228
═══════════════════════════════════════════════════════
✅ PAYMENT SUCCESSFUL!
═══════════════════════════════════════════════════════
   Transaction Reference: DEV_1763930605308_647228
   Amount: ₦5000.00
   Plan: 3-Month Premium
═══════════════════════════════════════════════════════
```

---

## 🇳🇬 Why Paystack?

Paystack is the **best choice for Nigerian apps** because:

1. ✅ **Built for Africa** - Specifically designed for African markets
2. ✅ **Better NGN Support** - Native Nigerian Naira processing
3. ✅ **Local Payment Methods**:
   - Bank Transfer
   - USSD
   - Mobile Money
   - QR Code payments
   - Bank Account
   - Cards (Mastercard, Visa, Verve)
4. ✅ **Lower Fees** - Competitive rates for Nigerian transactions
5. ✅ **Instant Settlement** - Fast payout to your bank account
6. ✅ **Better Support** - African timezone customer support
7. ✅ **Easy Testing** - Simple test cards and environment
8. ✅ **No Complex Setup** - No business verification required for test mode

---

## 🚀 Going Live (Production)

When you're ready to accept real payments:

### Step 1: Complete Business Verification
1. Go to Paystack Dashboard → Settings
2. Complete all required business information
3. Upload required documents (CAC, ID, etc.)
4. Wait for verification (usually 1-3 business days)

### Step 2: Get Live API Keys
1. After verification, go to Settings → API Keys
2. Switch to **Live Keys**
3. Copy your **Live Public Key** and **Live Secret Key**

### Step 3: Update Your App
Open [lib/paystack_config.dart](lib/paystack_config.dart:16-17) and update:

```dart
static const String livePublicKey = 'pk_live_YOUR_LIVE_PUBLIC_KEY';
static const String liveSecretKey = 'sk_live_YOUR_LIVE_SECRET_KEY';
```

Then set test mode to false:

```dart
static const bool isTestMode = false; // Set to false for production
```

### Step 4: Test with Real Money
- Start with small amounts (₦100-500)
- Test all payment flows
- Verify payments appear in your Paystack dashboard
- Check settlements to your bank account

---

## 🎯 Next Steps

1. **Get Paystack API keys** from the dashboard
2. **Add them to** [lib/paystack_config.dart](lib/paystack_config.dart)
3. **Hot restart** the app
4. **Test payment** with the test card
5. **Check Payment History** to verify it worked
6. **Verify Supabase sync** in your Supabase dashboard

---

## 🆘 Troubleshooting

### Payment Fails Immediately

**Check:**
- Are your API keys correct?
- Did you add them to [lib/paystack_config.dart](lib/paystack_config.dart)?
- Did you hot restart the app after adding keys?

**Solution:**
```dart
// In lib/paystack_config.dart
static const String testPublicKey = 'pk_test_YOUR_ACTUAL_KEY'; // Must start with pk_test_
```

### Payment UI Doesn't Open

**Check:**
- Is the app connected to the internet?
- Are there any errors in the console?
- Did Paystack initialize successfully?

**Look for this in console:**
```
✅ Paystack initialized successfully
   Public Key: pk_test_...
   Test Mode: true
```

### Payment Succeeds but Doesn't Save

**Check:**
- Is Supabase initialized?
- Did you create the payments table in Supabase?
- Check console for database errors

**Solution:**
Follow instructions in [SUPABASE_SETUP_INSTRUCTIONS.md](SUPABASE_SETUP_INSTRUCTIONS.md)

---

## 📝 File Locations

All Paystack-related files:

- Configuration: [lib/paystack_config.dart](lib/paystack_config.dart)
- Service: [lib/paystack_service.dart](lib/paystack_service.dart)
- Payment Flow: [lib/payment_plans_enhancement.dart](lib/payment_plans_enhancement.dart)
- Initialization: [lib/main.dart](lib/main.dart:3544)

---

## ✨ Features Included

- ✅ Secure payment processing
- ✅ User profile linking
- ✅ Payment history tracking
- ✅ Local SQLite storage
- ✅ Cloud sync with Supabase
- ✅ Comprehensive error logging
- ✅ Test mode for safe testing
- ✅ Multiple payment methods support
- ✅ Subscription management

---

**Ready to test!** 🚀

Just add your Paystack API keys and you're good to go!
