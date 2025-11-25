# Feature Restrictions Integration Guide

This guide shows exactly how to integrate the premium feature restrictions into your app.

## ✅ What's Already Done

- ✅ `premium_feature_gate.dart` - Core restriction system
- ✅ `feature_restrictions.dart` - Helper methods for all restrictions
- ✅ `payment_plans_enhancement.dart` - Subscription management

## 🚀 Integration Steps

### Step 1: Add Import to main.dart

At the top of your `lib/main.dart` file, add:

```dart
import 'feature_restrictions.dart';
import 'premium_feature_gate.dart';
```

---

## 1️⃣ Lock Weekday Devotionals (Sunday Only for Free)

### Where: Devotional Display/List

Find where devotionals are displayed in cards/lists and wrap weekday devotionals:

```dart
// Example: In your devotional list builder
Widget buildDevotionalCard(Devotional devotional) {
  final isSunday = devotional.date.weekday == DateTime.sunday;

  return FutureBuilder<bool>(
    future: SubscriptionManager.hasPremiumAccess(),
    builder: (context, snapshot) {
      final isPremium = snapshot.data ?? false;

      // Build the card
      Widget devotionalCard = Card(
        child: ListTile(
          title: Text(devotional.title),
          subtitle: Text(DateFormat('EEEE, MMM d').format(devotional.date)),
          trailing: !isSunday && !isPremium
              ? FeatureRestrictions.buildPremiumBadge()
              : null,
          onTap: () async {
            // Check if accessible
            if (!isSunday && !isPremium) {
              // Show upgrade dialog
              await FeatureRestrictions.showWeekdayDevotionalLock(context);
              return;
            }

            // Open devotional
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DevotionalDetailPage(devotional: devotional),
              ),
            );
          },
        ),
      );

      // If weekday and not premium, show locked overlay
      if (!isSunday && !isPremium) {
        return PremiumFeatureGate.gate(
          context: context,
          featureName: 'Weekday Devotionals',
          featureDescription: 'Access devotionals for Monday-Saturday.',
          showLockOverlay: true,
          child: devotionalCard,
        );
      }

      return devotionalCard;
    },
  );
}
```

### Alternative: Filter Devotionals Before Display

```dart
// In your devotional loading method
Future<List<Devotional>> loadDevotionals() async {
  // Load all devotionals from database/API
  final allDevotionals = await fetchAllDevotionals();

  // Filter for free users
  final accessibleDevotionals = await FeatureRestrictions.filterAccessibleDevotionals(
    allDevotionals,
  );

  return accessibleDevotionals as List<Devotional>;
}
```

---

## 2️⃣ Lock Offline Downloads

### Where: Download Button

Find download buttons/icons and add restriction:

```dart
// In your devotional detail page or wherever downloads happen
IconButton(
  icon: const Icon(Icons.download),
  tooltip: 'Download for offline',
  onPressed: () async {
    // Check if downloads are allowed
    final canDownload = await FeatureRestrictions.canDownloadOffline(context);

    if (!canDownload) {
      return; // Upgrade dialog already shown
    }

    // Proceed with download
    await _downloadDevotionalForOffline();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Downloaded for offline reading!'),
        backgroundColor: Colors.green,
      ),
    );
  },
)
```

### If You Have a Download Menu Item:

```dart
ListTile(
  leading: const Icon(Icons.download),
  title: const Text('Download for Offline'),
  trailing: FutureBuilder<bool>(
    future: SubscriptionManager.hasPremiumAccess(),
    builder: (context, snapshot) {
      final isPremium = snapshot.data ?? false;
      return Icon(
        isPremium ? Icons.check_circle : Icons.lock,
        color: isPremium ? Colors.green : Colors.amber,
      );
    },
  ),
  onTap: () async {
    final canDownload = await FeatureRestrictions.canDownloadOffline(context);
    if (canDownload) {
      await _downloadDevotionalForOffline();
    }
  },
)
```

---

## 3️⃣ Lock Bible Translations (ASV Only for Free)

### Where: Translation Selector/Switcher

Find where Bible translations are selected:

```dart
// Example: Translation dropdown or list
Future<void> selectTranslation(String translationCode, String translationName) async {
  // Check if translation is accessible
  final canAccess = await FeatureRestrictions.canAccessTranslation(
    context: context,
    translationCode: translationCode,
    translationName: translationName,
  );

  if (!canAccess) {
    return; // Upgrade dialog shown
  }

  // Switch to the translation
  await _switchToTranslation(translationCode);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Switched to $translationName'),
      backgroundColor: Colors.green,
    ),
  );
}
```

### Build Translation List with Locks:

```dart
// In your translation selection screen
Widget buildTranslationList() {
  return FutureBuilder<List<String>>(
    future: FeatureRestrictions.getAccessibleTranslations(),
    builder: (context, snapshot) {
      final accessibleTranslations = snapshot.data ?? ['ASV'];

      return ListView(
        children: [
          // ASV - Always available
          ListTile(
            title: const Text('ASV (American Standard Version)'),
            trailing: FeatureRestrictions.buildFreeBadge(),
            onTap: () => selectTranslation('ASV', 'ASV'),
          ),

          // KJV - Premium
          ListTile(
            title: const Text('KJV (King James Version)'),
            trailing: accessibleTranslations.contains('KJV')
                ? null
                : FeatureRestrictions.buildPremiumBadge(),
            onTap: () => selectTranslation('KJV', 'KJV'),
          ),

          // NIV - Premium
          ListTile(
            title: const Text('NIV (New International Version)'),
            trailing: accessibleTranslations.contains('NIV')
                ? null
                : FeatureRestrictions.buildPremiumBadge(),
            onTap: () => selectTranslation('NIV', 'NIV'),
          ),

          // Add more translations...
        ],
      );
    },
  );
}
```

---

## 4️⃣ Disable Screenshots for Free Users

### Where: Devotional Detail Screens

In screens where you want to restrict screenshots:

```dart
class DevotionalDetailPage extends StatefulWidget {
  final Devotional devotional;
  const DevotionalDetailPage({required this.devotional, super.key});

  @override
  State<DevotionalDetailPage> createState() => _DevotionalDetailPageState();
}

class _DevotionalDetailPageState extends State<DevotionalDetailPage>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setupScreenshotProtection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _setupScreenshotProtection() async {
    await FeatureRestrictions.setupScreenshotProtection(context);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Detect screenshot attempts
    if (state == AppLifecycleState.inactive) {
      _onPossibleScreenshot();
    }
  }

  Future<void> _onPossibleScreenshot() async {
    final canScreenshot = await FeatureRestrictions.canTakeScreenshots();

    if (!canScreenshot && mounted) {
      // Show warning after short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          FeatureRestrictions.showScreenshotWarning(context);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.devotional.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Text(widget.devotional.content),
      ),
    );
  }
}
```

---

## 5️⃣ Lock Priority Support

### Where: Support/Help Menu

In your settings or help menu:

```dart
ListTile(
  leading: const Icon(Icons.support_agent),
  title: const Text('Priority Support'),
  subtitle: const Text('Get faster response times'),
  trailing: FutureBuilder<bool>(
    future: SubscriptionManager.hasPremiumAccess(),
    builder: (context, snapshot) {
      final isPremium = snapshot.data ?? false;
      return Icon(
        isPremium ? Icons.check_circle : Icons.lock,
        color: isPremium ? Colors.green : Colors.amber,
      );
    },
  ),
  onTap: () async {
    final canAccess = await FeatureRestrictions.canAccessPrioritySupport(context);

    if (!canAccess) {
      return; // Upgrade dialog shown
    }

    // Open priority support
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PrioritySupportPage()),
    );
  },
)
```

---

## 6️⃣ Show Ads to Free Users Only

### Where: Wherever Ads Are Displayed

Add this check before showing any ads:

```dart
// Example: In your home screen or devotional page
class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Your main content
          Expanded(
            child: DevotionalContent(),
          ),

          // Ad banner - Only for free users
          FutureBuilder<bool>(
            future: FeatureRestrictions.shouldShowAds(),
            builder: (context, snapshot) {
              final showAds = snapshot.data ?? true;

              if (!showAds) {
                return const SizedBox.shrink(); // No ad for premium
              }

              // Show ad for free users
              return Container(
                height: 60,
                color: Colors.grey[300],
                child: const Center(
                  child: Text('Advertisement'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
```

### For Google AdMob or Other Ad Services:

```dart
class AdService {
  static Future<void> showInterstitialAd() async {
    final shouldShow = await FeatureRestrictions.shouldShowAds();

    if (!shouldShow) {
      print('✅ Premium user - skipping ad');
      return;
    }

    // Show ad to free users
    print('📢 Showing ad to free user');
    // Your ad display code here
    // Example: await InterstitialAd.show();
  }
}
```

---

## 🧪 Testing Checklist

### Test as Free User:
- [ ] Can only see Sunday devotionals
- [ ] Download button shows upgrade dialog
- [ ] Can only use ASV Bible translation
- [ ] Screenshot shows warning dialog
- [ ] Priority support shows upgrade dialog
- [ ] Ads are visible

### Test as Premium User:
- [ ] Can see all devotionals (7 days)
- [ ] Can download for offline
- [ ] Can access all Bible translations
- [ ] Can take screenshots freely
- [ ] Can access priority support
- [ ] No ads shown

---

## 🎯 Quick Reference

| Feature | Free Users | Premium Users |
|---------|------------|---------------|
| **Devotionals** | Sunday only | All 7 days |
| **Downloads** | ❌ Blocked | ✅ Allowed |
| **Translations** | ASV only | All 20+ |
| **Screenshots** | ⚠️ Warning | ✅ Allowed |
| **Support** | Basic | Priority |
| **Ads** | ✅ Shown | ❌ Hidden |

---

## 💡 Pro Tips

1. **Import once at top of main.dart:**
   ```dart
   import 'feature_restrictions.dart';
   import 'premium_feature_gate.dart';
   ```

2. **Use FutureBuilder for UI state:**
   ```dart
   FutureBuilder<bool>(
     future: SubscriptionManager.hasPremiumAccess(),
     builder: (context, snapshot) {
       final isPremium = snapshot.data ?? false;
       // Build UI based on isPremium
     },
   )
   ```

3. **Always check before action:**
   ```dart
   final canAccess = await FeatureRestrictions.canXXX(context);
   if (!canAccess) return;
   // Proceed with action
   ```

4. **Test subscription expiration:**
   - Make sure features lock again after subscription expires
   - Test subscription extension

---

## 🔥 Next Steps

1. Add imports to main.dart
2. Start with easiest: Ads and Downloads
3. Move to translations
4. Implement devotional restrictions
5. Add screenshot protection
6. Lock priority support
7. Test thoroughly as both free and premium user

Need help with a specific integration? Check the examples above or refer to `FEATURE_RESTRICTIONS_IMPLEMENTATION.md` for more details!
