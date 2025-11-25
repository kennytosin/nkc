import 'package:flutter/material.dart';
import 'payment_plans_enhancement.dart';

/// Premium Feature Gate - Controls access to premium features
class PremiumFeatureGate {
  /// Check if user has premium access and show upgrade dialog if not
  /// Returns true if user has access, false if blocked
  static Future<bool> checkAccess({
    required BuildContext context,
    required String featureName,
    String? featureDescription,
  }) async {
    final hasPremium = await SubscriptionManager.hasPremiumAccess();

    if (hasPremium) {
      return true; // User has premium, allow access
    }

    // User is on free tier - show upgrade dialog
    if (context.mounted) {
      await _showUpgradeDialog(
        context: context,
        featureName: featureName,
        featureDescription: featureDescription,
      );
    }

    return false; // Block access
  }

  /// Show upgrade dialog when free user tries to access premium feature
  static Future<void> _showUpgradeDialog({
    required BuildContext context,
    required String featureName,
    String? featureDescription,
  }) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.amber.withOpacity(0.3), width: 2),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.lock,
                color: Colors.amber,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Premium Feature',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"$featureName" is a premium feature',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (featureDescription != null) ...[
              const SizedBox(height: 12),
              Text(
                featureDescription,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.withOpacity(0.2),
                    Colors.orange.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.amber.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Upgrade to Premium to unlock:',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem('Ad-free experience'),
                  _buildFeatureItem('Offline access to all content'),
                  _buildFeatureItem('Premium devotionals & Bible studies'),
                  _buildFeatureItem('Advanced search & bookmarks'),
                  _buildFeatureItem('Custom reading plans'),
                  _buildFeatureItem('Cross-device sync'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Maybe Later',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Navigate to payment plans page
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EnhancedPaymentPlansPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Upgrade Now',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Helper to build feature list items
  static Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: Colors.green,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Widget wrapper for premium features
  /// Wraps any widget and shows upgrade overlay for free users
  static Widget gate({
    required BuildContext context,
    required Widget child,
    required String featureName,
    String? featureDescription,
    bool showLockOverlay = true,
  }) {
    return FutureBuilder<bool>(
      future: SubscriptionManager.hasPremiumAccess(),
      builder: (context, snapshot) {
        final hasPremium = snapshot.data ?? false;

        if (hasPremium) {
          return child; // Show feature normally
        }

        // Free user - show locked overlay
        if (showLockOverlay) {
          return Stack(
            children: [
              // Blurred/grayed out content
              Opacity(
                opacity: 0.3,
                child: AbsorbPointer(child: child),
              ),
              // Lock overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.3),
                        Colors.black.withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock,
                            color: Colors.black,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          featureName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Premium Feature',
                          style: TextStyle(
                            color: Colors.amber,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final shouldUpgrade = await checkAccess(
                              context: context,
                              featureName: featureName,
                              featureDescription: featureDescription,
                            );
                          },
                          icon: const Icon(Icons.upgrade),
                          label: const Text('Upgrade Now'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return child;
      },
    );
  }
}
