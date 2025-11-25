# Premium Feature Gate - Usage Examples

This guide shows how to restrict features from free users and show upgrade prompts.

## 📋 Table of Contents
1. [Method 1: Check Before Action](#method-1-check-before-action)
2. [Method 2: Widget Wrapper with Lock Overlay](#method-2-widget-wrapper-with-lock-overlay)
3. [Method 3: Conditional UI](#method-3-conditional-ui)
4. [Common Use Cases](#common-use-cases)

---

## Method 1: Check Before Action

**Best for:** Button clicks, menu items, feature triggers

### Example: Lock a "Download Bible" button for free users

```dart
import 'premium_feature_gate.dart';

ElevatedButton(
  onPressed: () async {
    // Check premium access before allowing download
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Offline Bible Download',
      featureDescription: 'Download Bible translations for offline reading without internet connection.',
    );

    if (hasAccess) {
      // User has premium - proceed with download
      await _downloadBible();
    }
    // If no access, upgrade dialog is shown automatically
  },
  child: const Text('Download for Offline'),
);
```

### Example: Lock "Export Notes" feature

```dart
IconButton(
  icon: const Icon(Icons.file_download),
  onPressed: () async {
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Export Notes',
      featureDescription: 'Export your devotional notes and highlights to PDF or text files.',
    );

    if (hasAccess) {
      await _exportNotes();
    }
  },
);
```

---

## Method 2: Widget Wrapper with Lock Overlay

**Best for:** Full screens, cards, sections that should be visually locked

### Example: Lock entire devotional categories

```dart
import 'premium_feature_gate.dart';

// Wrap premium content with gate widget
PremiumFeatureGate.gate(
  context: context,
  featureName: 'Premium Devotionals',
  featureDescription: 'Access exclusive devotional content from renowned Christian authors.',
  showLockOverlay: true,
  child: DevotionalCategoryCard(
    title: 'Premium Daily Devotions',
    icon: Icons.auto_awesome,
    onTap: () => _openPremiumDevotionals(),
  ),
);
```

### Example: Lock advanced search

```dart
// In your search screen
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: const Text('Search')),
    body: Column(
      children: [
        // Basic search - available to all
        BasicSearchField(),

        const SizedBox(height: 20),

        // Advanced filters - premium only
        PremiumFeatureGate.gate(
          context: context,
          featureName: 'Advanced Search Filters',
          featureDescription: 'Filter by Testament, book, topic, date range, and more.',
          showLockOverlay: true,
          child: AdvancedFilterSection(),
        ),
      ],
    ),
  );
}
```

---

## Method 3: Conditional UI

**Best for:** Showing different UI based on subscription status

### Example: Show different buttons for free vs premium

```dart
FutureBuilder<bool>(
  future: SubscriptionManager.hasPremiumAccess(),
  builder: (context, snapshot) {
    final isPremium = snapshot.data ?? false;

    return ListTile(
      title: const Text('Ad-Free Experience'),
      trailing: isPremium
          ? const Icon(Icons.check_circle, color: Colors.green)
          : ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const EnhancedPaymentPlansPage(),
                  ),
                );
              },
              child: const Text('Upgrade'),
            ),
    );
  },
);
```

### Example: Hide premium features from menu

```dart
FutureBuilder<bool>(
  future: SubscriptionManager.hasPremiumAccess(),
  builder: (context, snapshot) {
    final isPremium = snapshot.data ?? false;

    return Column(
      children: [
        // Always visible
        MenuTile(title: 'Daily Devotional', icon: Icons.book),
        MenuTile(title: 'Bible', icon: Icons.menu_book),

        // Premium only - hidden for free users
        if (isPremium) ...[
          MenuTile(title: 'Premium Library', icon: Icons.library_books),
          MenuTile(title: 'Custom Plans', icon: Icons.edit_calendar),
        ] else
          // Show upgrade prompt instead
          UpgradePromptTile(),
      ],
    );
  },
);
```

---

## Common Use Cases

### 1. Lock Bible Translation Downloads

```dart
// In BibleTranslationManager or download screen
Future<void> downloadTranslation(String translationId) async {
  final hasAccess = await PremiumFeatureGate.checkAccess(
    context: context,
    featureName: 'Bible Translation Download',
    featureDescription: 'Download multiple Bible translations for offline study.',
  );

  if (!hasAccess) return;

  // Proceed with download
  await _performDownload(translationId);
}
```

### 2. Lock Custom Reading Plans

```dart
FloatingActionButton(
  onPressed: () async {
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Custom Reading Plans',
      featureDescription: 'Create personalized Bible reading plans tailored to your schedule.',
    );

    if (hasAccess) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CreateReadingPlanPage()),
      );
    }
  },
  child: const Icon(Icons.add),
);
```

### 3. Lock Note Export/Backup

```dart
// In settings or notes screen
ListTile(
  leading: const Icon(Icons.backup),
  title: const Text('Backup & Export Notes'),
  onTap: () async {
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Notes Backup & Export',
      featureDescription: 'Export and backup your devotional notes, highlights, and bookmarks.',
    );

    if (hasAccess) {
      await _showBackupOptions();
    }
  },
);
```

### 4. Lock Advanced Bookmarks

```dart
// Allow basic bookmarks (up to 10), require premium for unlimited
Future<void> addBookmark(String verse) async {
  final bookmarkCount = await _getBookmarkCount();

  if (bookmarkCount >= 10) {
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Unlimited Bookmarks',
      featureDescription: 'Save unlimited Bible verses, devotionals, and study notes. Free users are limited to 10 bookmarks.',
    );

    if (!hasAccess) return;
  }

  // Proceed with adding bookmark
  await _saveBookmark(verse);
}
```

### 5. Lock Premium Devotional Content

```dart
// In devotional list screen
Widget buildDevotionalCard(Devotional devotional) {
  if (devotional.isPremium) {
    return PremiumFeatureGate.gate(
      context: context,
      featureName: devotional.title,
      featureDescription: 'This is premium devotional content available only to subscribers.',
      showLockOverlay: true,
      child: DevotionalCard(devotional: devotional),
    );
  }

  // Free content - show normally
  return DevotionalCard(devotional: devotional);
}
```

### 6. Lock Ad-Free Experience

```dart
// In your ad display logic
Future<void> showAd() async {
  final hasPremium = await SubscriptionManager.hasPremiumAccess();

  if (hasPremium) {
    // Premium users don't see ads
    return;
  }

  // Show ad to free users
  await _displayAdvertisement();
}
```

### 7. Lock Theme Customization

```dart
// In settings/appearance screen
ListTile(
  leading: const Icon(Icons.palette),
  title: const Text('Custom Themes'),
  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
  onTap: () async {
    final hasAccess = await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Custom Themes',
      featureDescription: 'Customize app colors, fonts, and appearance settings.',
    );

    if (hasAccess) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ThemeCustomizationPage()),
      );
    }
  },
);
```

---

## 🎨 Customizing the Upgrade Dialog

You can customize which features appear in the upgrade dialog by modifying the list in `premium_feature_gate.dart`:

```dart
// In _showUpgradeDialog method, update these items:
_buildFeatureItem('Your custom feature 1'),
_buildFeatureItem('Your custom feature 2'),
_buildFeatureItem('Your custom feature 3'),
```

---

## ✅ Best Practices

1. **Be Clear:** Always provide a descriptive feature name and explanation
2. **Be Consistent:** Use the same restriction method throughout your app
3. **Test Both States:** Test your app as both free and premium user
4. **Graceful Degradation:** Offer limited functionality to free users when possible
5. **Clear Value:** Make it obvious why upgrading is beneficial

---

## 🔐 Quick Reference

| Use Case | Best Method |
|----------|-------------|
| Button/Menu Action | `checkAccess()` |
| Visual Lock (Screen/Card) | `gate()` widget |
| Conditional UI | `FutureBuilder` + `hasPremiumAccess()` |
| Limit Feature Usage | Custom logic + `checkAccess()` |

---

## Example: Complete Feature Lock Implementation

Here's a complete example of locking a "Bible Study Notes" feature:

```dart
import 'package:flutter/material.dart';
import 'premium_feature_gate.dart';
import 'payment_plans_enhancement.dart';

class BibleStudyNotesPage extends StatelessWidget {
  const BibleStudyNotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bible Study Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () async {
              // Lock export feature
              final hasAccess = await PremiumFeatureGate.checkAccess(
                context: context,
                featureName: 'Export Study Notes',
                featureDescription: 'Export your Bible study notes to PDF, Word, or text files.',
              );

              if (hasAccess) {
                await _exportNotes();
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Basic notes - available to all users
          Expanded(
            child: NotesList(),
          ),

          // Advanced formatting - premium only
          PremiumFeatureGate.gate(
            context: context,
            featureName: 'Advanced Formatting',
            featureDescription: 'Use rich text formatting, colors, and custom fonts in your notes.',
            showLockOverlay: true,
            child: FormattingToolbar(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final noteCount = await _getNoteCount();

          // Limit free users to 20 notes
          if (noteCount >= 20) {
            final hasAccess = await PremiumFeatureGate.checkAccess(
              context: context,
              featureName: 'Unlimited Notes',
              featureDescription: 'Create unlimited Bible study notes. Free users are limited to 20 notes.',
            );

            if (!hasAccess) return;
          }

          // Create new note
          await _createNote();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _exportNotes() async {
    // Export logic here
  }

  Future<int> _getNoteCount() async {
    // Get note count from database
    return 0;
  }

  Future<void> _createNote() async {
    // Create note logic
  }
}
```

---

## 📱 Testing

To test premium features:

1. **As Free User:**
   - Don't purchase any subscription
   - Try accessing locked features
   - Verify upgrade dialog appears

2. **As Premium User:**
   - Purchase any subscription plan
   - Verify all features are unlocked
   - No upgrade prompts should appear

3. **Test Expiration:**
   - Wait for subscription to expire
   - Verify features lock again
   - Check that extension works correctly
