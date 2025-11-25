# Feature Restrictions Implementation Guide

This guide shows exactly how to implement the feature restrictions based on your subscription plans.

## 📋 Your Feature Breakdown

### ✅ Free Users Get:
- Sunday devotionals access
- ASV Bible translation only
- Basic Bible reading features
- Search functionality

### 🔒 Premium Users Get (in addition to free):
1. **Access to ALL devotionals** (weekday + Sunday)
2. **Offline devotional downloads**
3. **All Bible translations** (not just ASV)
4. **Priority support**
5. **Screenshot permission**
6. **Ad-free experience**

---

## 🚀 Implementation Steps

### 1. Restrict Weekday Devotionals (Allow Sunday Only for Free)

**Where:** In your devotional list/display code

```dart
import 'premium_feature_gate.dart';

// In your devotional list builder
Widget buildDevotionalItem(Devotional devotional) {
  final isSunday = devotional.day == 'Sunday'; // or however you track days

  if (!isSunday) {
    // Weekday devotional - check premium access
    return FutureBuilder<bool>(
      future: SubscriptionManager.hasPremiumAccess(),
      builder: (context, snapshot) {
        final isPremium = snapshot.data ?? false;

        if (isPremium) {
          // Premium user - show normally
          return DevotionalCard(devotional: devotional);
        }

        // Free user - show locked
        return PremiumFeatureGate.gate(
          context: context,
          featureName: 'Weekday Devotionals',
          featureDescription: 'Access devotionals for all 7 days of the week, not just Sundays.',
          showLockOverlay: true,
          child: DevotionalCard(devotional: devotional),
        );
      },
    );
  }

  // Sunday devotional - available to everyone
  return DevotionalCard(devotional: devotional);
}
```

**Alternative - Filter List Approach:**
```dart
// Filter devotionals based on subscription
Future<List<Devotional>> getAccessibleDevotionals() async {
  final allDevotionals = await loadAllDevotionals();
  final isPremium = await SubscriptionManager.hasPremiumAccess();

  if (isPremium) {
    return allDevotionals; // Premium: show all
  }

  // Free: show only Sunday
  return allDevotionals.where((d) => d.day == 'Sunday').toList();
}
```

---

### 2. Restrict Offline Devotional Downloads

**Where:** Download button/functionality

```dart
import 'premium_feature_gate.dart';

IconButton(
  icon: const Icon(Icons.download),
  onPressed: () async {
    // Check premium access
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Offline Downloads',
      featureDescription: 'Download devotionals to read offline without internet connection.',
    );

    if (!hasAccess) return;

    // Premium user - proceed with download
    await downloadDevotional();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Downloaded for offline reading!'),
        backgroundColor: Colors.green,
      ),
    );
  },
)
```

---

### 3. Restrict Bible Translations (ASV Only for Free)

**Where:** Bible translation selector/switcher

```dart
import 'premium_feature_gate.dart';

// In your translation selector
Future<void> selectTranslation(String translationCode) async {
  // ASV is always allowed
  if (translationCode == 'ASV') {
    await switchToTranslation(translationCode);
    return;
  }

  // Other translations require premium
  final hasAccess = await PremiumFeatureGate.checkAccess(
    context: context,
    featureName: 'All Bible Translations',
    featureDescription: 'Access KJV, NIV, ESV, and 20+ other Bible translations beyond ASV.',
  );

  if (!hasAccess) return;

  // Premium user - allow translation switch
  await switchToTranslation(translationCode);
}
```

**Alternative - Visual Lock in Translation List:**
```dart
// In translation list builder
Widget buildTranslationTile(Translation translation) {
  if (translation.code == 'ASV') {
    // ASV - always available
    return ListTile(
      title: Text(translation.name),
      subtitle: const Text('Free'),
      trailing: const Icon(Icons.check_circle, color: Colors.green),
      onTap: () => selectTranslation(translation.code),
    );
  }

  // Other translations - premium only
  return PremiumFeatureGate.gate(
    context: context,
    featureName: translation.name,
    featureDescription: 'Switch to ${translation.name} Bible translation.',
    showLockOverlay: true,
    child: ListTile(
      title: Text(translation.name),
      subtitle: const Text('Premium'),
      trailing: const Icon(Icons.lock, color: Colors.amber),
      onTap: () => selectTranslation(translation.code),
    ),
  );
}
```

---

### 4. Restrict Screenshot Functionality

**Where:** Screen setup or permission handling

**Option A: Disable Screenshots for Free Users**
```dart
import 'package:flutter/services.dart';
import 'premium_feature_gate.dart';

class DevotionalScreen extends StatefulWidget {
  @override
  State<DevotionalScreen> createState() => _DevotionalScreenState();
}

class _DevotionalScreenState extends State<DevotionalScreen> {
  @override
  void initState() {
    super.initState();
    _setupScreenshotProtection();
  }

  Future<void> _setupScreenshotProtection() async {
    final isPremium = await SubscriptionManager.hasPremiumAccess();

    if (!isPremium) {
      // Disable screenshots for free users
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Your devotional content
    );
  }
}
```

**Option B: Show Warning When Screenshot Detected**
```dart
import 'package:flutter/services.dart';

@override
void initState() {
  super.initState();
  _listenForScreenshots();
}

void _listenForScreenshots() {
  SystemChannels.lifecycle.setMessageHandler((msg) async {
    if (msg == AppLifecycleState.inactive.toString()) {
      final isPremium = await SubscriptionManager.hasPremiumAccess();

      if (!isPremium) {
        // Show upgrade prompt for screenshot
        if (mounted) {
          await PremiumFeatureGate.checkAccess(
            context: context,
            featureName: 'Screenshot Permission',
            featureDescription: 'Save and share devotionals as images.',
          );
        }
      }
    }
    return null;
  });
}
```

---

### 5. Priority Support Access

**Where:** Support/Help screen

```dart
import 'premium_feature_gate.dart';

// In your support/help menu
ListTile(
  leading: const Icon(Icons.support_agent),
  title: const Text('Priority Support'),
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
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Priority Support',
      featureDescription: 'Get faster response times and dedicated support from our team.',
    );

    if (!hasAccess) return;

    // Open priority support
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PrioritySupportPage()),
    );
  },
)
```

---

### 6. Ad-Free Experience

**Where:** Ad display logic

```dart
import 'premium_feature_gate.dart';

class AdService {
  static Future<void> showAd(BuildContext context) async {
    // Check if user has premium (ad-free)
    final isPremium = await SubscriptionManager.hasPremiumAccess();

    if (isPremium) {
      print('✅ Premium user - skipping ad');
      return; // No ads for premium users
    }

    // Free user - show ad
    print('📢 Showing ad to free user');
    await _displayAdvertisement();
  }

  static Future<void> _displayAdvertisement() async {
    // Your ad display logic here
    // Example: Google AdMob, Facebook Audience Network, etc.
  }
}

// Usage in your app
class DevotionalPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Devotional content
          DevotionalContent(),

          // Ad banner (only for free users)
          FutureBuilder<bool>(
            future: SubscriptionManager.hasPremiumAccess(),
            builder: (context, snapshot) {
              final isPremium = snapshot.data ?? false;

              if (isPremium) {
                return const SizedBox.shrink(); // No ad
              }

              return AdBanner(); // Show ad
            },
          ),
        ],
      ),
    );
  }
}
```

---

## 🎯 Complete Example: Devotional Screen with All Restrictions

```dart
import 'package:flutter/material.dart';
import 'premium_feature_gate.dart';
import 'payment_plans_enhancement.dart';

class DevotionalDetailScreen extends StatelessWidget {
  final Devotional devotional;

  const DevotionalDetailScreen({required this.devotional, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(devotional.title),
        actions: [
          // Download button - Premium only
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () async {
              final hasAccess = await PremiumFeatureGate.checkAccess(
                context: context,
                featureName: 'Offline Downloads',
                featureDescription: 'Download devotionals for offline reading.',
              );

              if (hasAccess) {
                await _downloadDevotional();
              }
            },
          ),

          // Share button - Always available
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareDevotional(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Devotional content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Text(devotional.content),
            ),
          ),

          // Ad banner - Free users only
          FutureBuilder<bool>(
            future: SubscriptionManager.hasPremiumAccess(),
            builder: (context, snapshot) {
              final isPremium = snapshot.data ?? false;

              if (isPremium) {
                return const SizedBox.shrink();
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

  Future<void> _downloadDevotional() async {
    // Download logic
  }

  void _shareDevotional() {
    // Share logic
  }
}
```

---

## 📱 Quick Implementation Checklist

- [ ] **Weekday Devotionals Locked** - Free users see only Sunday
- [ ] **Download Button Locked** - Premium feature gate on download
- [ ] **Bible Translations Locked** - Allow ASV only for free users
- [ ] **Screenshots Restricted** - Disable or warn free users
- [ ] **Ads Shown to Free Users** - Remove ads for premium
- [ ] **Priority Support Locked** - Gate support features

---

## 🧪 Testing Guide

### Test as Free User:
1. ✅ Can access Sunday devotionals
2. ✅ Can read ASV Bible
3. ✅ Can use basic search
4. ❌ Cannot access weekday devotionals (locked)
5. ❌ Cannot download for offline (locked)
6. ❌ Cannot switch to other translations (locked)
7. ❌ Cannot take screenshots (blocked or warned)
8. ✅ Sees ads

### Test as Premium User:
1. ✅ Can access ALL devotionals (7 days)
2. ✅ Can download for offline
3. ✅ Can access all Bible translations
4. ✅ Can take screenshots freely
5. ✅ Has priority support
6. ✅ No ads shown

---

## 🎨 Customization Tips

1. **Update Premium Benefits List** in `premium_feature_gate.dart`:
```dart
_buildFeatureItem('Access to ALL devotionals (7 days)'),
_buildFeatureItem('Offline devotional downloads'),
_buildFeatureItem('All Bible translations (20+)'),
_buildFeatureItem('Screenshot permission'),
_buildFeatureItem('Priority support'),
_buildFeatureItem('Ad-free experience'),
```

2. **Adjust Free User Messaging** - Be encouraging, not limiting:
   - Good: "Upgrade to access weekday devotionals"
   - Bad: "You can't access this feature"

3. **Test Edge Cases:**
   - User with expired subscription
   - User switching between free and premium
   - Offline behavior

---

## 💡 Pro Tips

1. **Always show value first** - Let users see what they're missing
2. **Use soft locks initially** - Show locked content with overlay
3. **Make upgrade obvious** - Clear "Upgrade" buttons
4. **Track analytics** - See which locked features users try to access most
5. **Be consistent** - Use same locking UI throughout app
