# Multi-Currency Payment System Guide

## Overview

Your app now supports **dynamic currency detection** based on user region! Users will automatically see prices in their local currency.

## Supported Currencies

| Currency | Code | Symbol | Countries |
|----------|------|--------|-----------|
| Nigerian Naira | NGN | ₦ | Nigeria |
| US Dollar | USD | $ | United States |
| British Pound | GBP | £ | United Kingdom |
| Euro | EUR | € | Germany, France, Italy, Spain, Netherlands |
| Ghanaian Cedi | GHS | GH₵ | Ghana |
| Kenyan Shilling | KES | KSh | Kenya |
| South African Rand | ZAR | R | South Africa |

## Pricing Structure

### 3-Month Premium
- NGN: ₦1,000
- USD: $3.00
- GBP: £2.50
- EUR: €2.80
- GHS: GH₵40
- KES: KSh400
- ZAR: R50

### 6-Month Premium
- NGN: ₦1,500
- USD: $4.50
- GBP: £3.50
- EUR: €4.00
- GHS: GH₵60
- KES: KSh600
- ZAR: R75

### Yearly Premium
- NGN: ₦2,500
- USD: $7.00
- GBP: £5.50
- EUR: €6.50
- GHS: GH₵95
- KES: KSh950
- ZAR: R120

## How It Works

### 1. Automatic Currency Detection

When a user opens the app, the system automatically:
1. Checks device locale (e.g., `en_US`, `en_NG`)
2. Extracts country code
3. Maps to appropriate currency
4. Saves preference for future use

```dart
// Automatic detection in CurrencyManager
final currency = await CurrencyManager.getCurrentCurrency();
```

### 2. Display Prices

The UI automatically shows prices in the detected currency:

```dart
// In payment plans page
Text('${plan.getPriceDisplay(userCurrency)}')
// Shows: "₦1,000" for NGN users
// Shows: "$3.00" for USD users
```

### 3. Process Payment

When user initiates payment, Paystack receives:
- Correct amount in their currency
- Currency code (NGN, USD, etc.)
- Amount in smallest unit (kobo, cents, etc.)

## For Users

### Changing Currency Manually

Users can manually change their currency (future feature):

```dart
// Allow manual currency selection
await CurrencyManager.changeCurrency(Currency.USD);
```

### Supported Regions

- **Nigeria** → NGN (₦)
- **United States** → USD ($)
- **United Kingdom** → GBP (£)
- **Ghana** → GHS (GH₵)
- **Kenya** → KES (KSh)
- **South Africa** → ZAR (R)
- **European Union** → EUR (€)
- **Other regions** → USD ($ - default)

## Technical Details

### Currency Detection Flow

```
App Launch
    ↓
CurrencyManager.detectCurrency()
    ↓
Read Platform.localeName (e.g., "en_NG")
    ↓
Extract country code ("NG")
    ↓
Map to Currency.NGN
    ↓
Save to SharedPreferences
    ↓
Use throughout app
```

### Payment Flow

```
User selects plan
    ↓
Get price for user's currency
plan.getPrice(userCurrency) → ₦1,000
    ↓
Display price
plan.getPriceDisplay(userCurrency) → "₦1,000"
    ↓
User confirms
    ↓
Pass to Paystack
amount: 1000.00, currency: "NGN"
    ↓
Convert to smallest unit
1000 * 100 = 100,000 kobo
    ↓
Paystack processes payment
    ↓
Success!
```

## Paystack Currency Support

**Important**: Paystack supports multiple currencies, but availability depends on your account:

### Currently Supported by Paystack:
- ✅ NGN (Nigerian Naira) - Primary
- ✅ USD (US Dollar)
- ✅ GHS (Ghanaian Cedi)
- ✅ KES (Kenyan Shilling)
- ✅ ZAR (South African Rand)

### Might require special setup:
- ⚠️ GBP (British Pound)
- ⚠️ EUR (Euro)

**Note**: If Paystack doesn't support a currency in your account, it will convert to NGN at current exchange rate.

## Testing

### Test on Different Locales

1. **Android**:
   - Settings → System → Languages → Add language
   - Or use emulator with different locale

2. **iOS**:
   - Settings → General → Language & Region
   - Add preferred language/region

### Test Currency Detection

```dart
// Check detected currency
final currency = await CurrencyManager.getCurrentCurrency();
print('Detected currency: ${currency.code}');
```

### Verify Prices

```dart
// Check prices for all currencies
for (var currency in Currency.values) {
  print('${currency.code}: ${plan.getPriceDisplay(currency)}');
}
```

## Updating Prices

To change prices, edit `lib/payment_plans_enhancement.dart`:

```dart
SubscriptionPlan(
  tier: SubscriptionTier.threeMonths,
  name: '3-Month Premium',
  prices: {
    Currency.NGN: 1000.00,  // Update here
    Currency.USD: 3.00,     // Update here
    // ...
  },
  // ...
)
```

## Adding New Currencies

To add a new currency:

### 1. Add to Currency enum

```dart
enum Currency {
  NGN,
  USD,
  // ... existing
  INR, // New: Indian Rupee
}
```

### 2. Add symbol

```dart
extension CurrencyExtension on Currency {
  String get symbol {
    switch (this) {
      // ... existing
      case Currency.INR:
        return '₹';
    }
  }
}
```

### 3. Add country mapping

```dart
static Future<Currency> detectCurrency() async {
  switch (countryCode) {
    // ... existing
    case 'IN': // India
      detected = Currency.INR;
      break;
  }
}
```

### 4. Add prices

```dart
prices: {
  // ... existing
  Currency.INR: 250.00, // Add price
}
```

## Best Practices

1. **Keep exchange rates updated**: Review prices quarterly
2. **Round to local conventions**:
   - NGN: No decimals (₦1,000)
   - USD: 2 decimals ($3.00)
3. **Test payment flow**: Test each currency with Paystack
4. **Monitor conversions**: Check Paystack dashboard for currency conversions

## Troubleshooting

### Currency not detecting

**Issue**: App shows wrong currency

**Solution**:
```dart
// Clear saved currency
final prefs = await SharedPreferences.getInstance();
await prefs.remove('user_preferred_currency');
// Restart app
```

### Paystack currency error

**Issue**: "Currency not supported"

**Solution**:
- Check your Paystack account settings
- Contact Paystack to enable additional currencies
- Or allow fallback to NGN

### Wrong price displayed

**Issue**: Price shows in wrong currency

**Solution**:
```dart
// Verify currency detection
final currency = await CurrencyManager.getCurrentCurrency();
print('Currency: ${currency.code}');

// Check prices map
print('Price: ${plan.getPrice(currency)}');
```

## Support

For issues or questions:
- Check Paystack documentation: https://paystack.com/docs
- Review currency support: https://paystack.com/docs/payments/multi-currency-payments
- Test with Paystack test cards

---

**Last Updated**: 2025-11-25
**Version**: 1.0.0
