/// Feature Restrictions - Centralized premium feature control
/// This file contains all premium feature restriction logic

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'payment_plans_enhancement.dart';
import 'premium_feature_gate.dart';

class FeatureRestrictions {
  /// 1. CHECK IF DEVOTIONAL IS ACCESSIBLE
  /// Returns true if user can access this devotional
  static Future<bool> canAccessDevotional(DateTime devotionalDate) async {
    final isPremium = await SubscriptionManager.hasPremiumAccess();

    if (isPremium) {
      return true; // Premium users access all devotionals
    }

    // Free users: only Sunday devotionals
    final isSunday = devotionalDate.weekday == DateTime.sunday;
    return isSunday;
  }

  /// 2. SHOW UPGRADE DIALOG FOR WEEKDAY DEVOTIONALS
  /// Call this when free user tries to access weekday devotional
  static Future<void> showWeekdayDevotionalLock(BuildContext context) async {
    await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Weekday Devotionals',
      featureDescription: 'Access devotionals for all 7 days of the week, not just Sundays. '
          'Get daily spiritual guidance Monday through Saturday.',
    );
  }

  /// 3. CHECK IF DOWNLOADS ARE ALLOWED
  /// Returns true if user can download devotionals offline
  static Future<bool> canDownloadOffline(BuildContext context) async {
    return await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Offline Downloads',
      featureDescription: 'Download devotionals and Bible content to read offline without internet connection.',
    );
  }

  /// 4. CHECK IF BIBLE TRANSLATION IS ACCESSIBLE
  /// Returns true if user can access this translation
  static Future<bool> canAccessTranslation({
    required BuildContext context,
    required String translationCode,
    required String translationName,
  }) async {
    // ASV is always free
    if (translationCode.toUpperCase() == 'ASV') {
      return true;
    }

    // Other translations require premium
    return await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'All Bible Translations',
      featureDescription: 'Access $translationName and 20+ other Bible translations beyond ASV.',
    );
  }

  /// 5. CHECK IF SCREENSHOTS ARE ALLOWED
  /// Returns true if user can take screenshots
  static Future<bool> canTakeScreenshots() async {
    return await SubscriptionManager.hasPremiumAccess();
  }

  /// 6. SETUP SCREENSHOT PROTECTION
  /// Call this in initState of screens you want to protect
  static Future<void> setupScreenshotProtection(BuildContext context) async {
    final isPremium = await SubscriptionManager.hasPremiumAccess();

    if (!isPremium) {
      // Show warning that screenshots require premium
      // Note: Actually blocking screenshots is platform-specific and complex
      // For now, we'll just track attempts
      print('⚠️ Screenshot protection active for free user');
    }
  }

  /// 7. SHOW SCREENSHOT WARNING
  /// Call this when screenshot attempt is detected
  static Future<void> showScreenshotWarning(BuildContext context) async {
    await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Screenshot Permission',
      featureDescription: 'Save and share devotionals as images with premium access.',
    );
  }

  /// 8. CHECK IF PRIORITY SUPPORT IS ACCESSIBLE
  static Future<bool> canAccessPrioritySupport(BuildContext context) async {
    return await PremiumFeatureGate.checkAccess(
      context: context,
      featureName: 'Priority Support',
      featureDescription: 'Get faster response times and dedicated support from our team.',
    );
  }

  /// 9. CHECK IF ADS SHOULD BE SHOWN
  /// Returns true if ads should be displayed (free users)
  static Future<bool> shouldShowAds() async {
    final isPremium = await SubscriptionManager.hasPremiumAccess();
    return !isPremium; // Show ads only for free users
  }

  /// 10. GET ACCESSIBLE BIBLE TRANSLATIONS
  /// Returns list of translation codes the user can access
  static Future<List<String>> getAccessibleTranslations() async {
    final isPremium = await SubscriptionManager.hasPremiumAccess();

    if (isPremium) {
      // Premium: all translations
      return [
        'ASV', 'KJV', 'NIV', 'ESV', 'NKJV', 'NLT', 'NASB', 'CSB',
        'AMP', 'MSG', 'HCSB', 'RSV', 'CEV', 'GNT', 'WEB', 'YLT',
        // Add more translation codes as needed
      ];
    }

    // Free: ASV only
    return ['ASV'];
  }

  /// 11. FILTER DEVOTIONALS FOR FREE USERS
  /// Filters a list of devotionals to only include accessible ones
  static Future<List<dynamic>> filterAccessibleDevotionals(
    List<dynamic> allDevotionals,
  ) async {
    final isPremium = await SubscriptionManager.hasPremiumAccess();

    if (isPremium) {
      return allDevotionals; // Premium: all devotionals
    }

    // Free: only Sunday devotionals
    return allDevotionals.where((devotional) {
      final date = devotional is Map
          ? DateTime.parse(devotional['date'] ?? '')
          : (devotional as dynamic).date as DateTime;

      return date.weekday == DateTime.sunday;
    }).toList();
  }

  /// 12. BUILD PREMIUM BADGE WIDGET
  /// Shows a premium badge for locked content
  static Widget buildPremiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.lock, size: 12, color: Colors.black),
          SizedBox(width: 4),
          Text(
            'PREMIUM',
            style: TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 13. BUILD FREE BADGE WIDGET
  /// Shows a free badge for accessible content
  static Widget buildFreeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'FREE',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
