import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

// ------------------------- SUBSCRIPTION MODELS -------------------------

enum SubscriptionTier { free, threeMonths, sixMonths, yearly }

class SubscriptionPlan {
  final SubscriptionTier tier;
  final String name;
  final double price;
  final int durationMonths;
  final List<String> features;
  final List<String> limitations;

  const SubscriptionPlan({
    required this.tier,
    required this.name,
    required this.price,
    required this.durationMonths,
    required this.features,
    required this.limitations,
  });

  static const List<SubscriptionPlan> allPlans = [
    SubscriptionPlan(
      tier: SubscriptionTier.free,
      name: 'Free Plan',
      price: 0.00,
      durationMonths: 0,
      features: [
        'Sunday devotionals access',
        'ASV Bible translation only',
        'Basic Bible reading features',
        'Search functionality',
      ],
      limitations: [
        '❌ No offline devotional downloads',
        '❌ Limited to Sunday devotionals only',
        '❌ Only one Bible translation (ASV)',
        '❌ No access to weekday devotionals',
        '❌ Inability to screenshot devotionals',
      ],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.threeMonths,
      name: '3-Month Premium',
      price: 1.50,
      durationMonths: 3,
      features: [
        '✅ Access to ALL devotionals',
        '✅ Offline devotional downloads',
        '✅ All Bible translations',
        '✅ Priority support',
        '✅ Screenshot permission',
        '✅ Ad-free experience',
      ],
      limitations: [],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.sixMonths,
      name: '6-Month Premium',
      price: 2.00,
      durationMonths: 6,
      features: [
        '✅ Access to ALL devotionals',
        '✅ Offline devotional downloads',
        '✅ All Bible translations',
        '✅ Priority support',
        '✅ Screenshot permission',
        '✅ Ad-free experience',
        '💎 Best value per month',
      ],
      limitations: [],
    ),
    SubscriptionPlan(
      tier: SubscriptionTier.yearly,
      name: 'Yearly Premium',
      price: 3.00,
      durationMonths: 12,
      features: [
        '✅ Access to ALL devotionals',
        '✅ Offline devotional downloads',
        '✅ All Bible translations',
        '✅ Priority support',
        '✅ Screenshot permission',
        '✅ Ad-free experience',
        '💎 Maximum savings',
        '🎁 Bonus features',
      ],
      limitations: [],
    ),
  ];

  String get priceDisplay {
    return price == 0 ? 'Free' : '\$${price.toStringAsFixed(2)}';
  }

  String get durationDisplay {
    if (durationMonths == 0) return 'Forever';
    if (durationMonths == 3) return '3 Months';
    if (durationMonths == 6) return '6 Months';
    if (durationMonths == 12) return '1 Year';
    return '$durationMonths Months';
  }

  double get pricePerMonth {
    return durationMonths == 0 ? 0 : price / durationMonths;
  }
}

// ------------------------- SUBSCRIPTION MANAGER -------------------------

class SubscriptionManager {
  static const String _tierKey = 'subscription_tier';
  static const String _expiryKey = 'subscription_expiry';
  static const String _purchaseDateKey = 'subscription_purchase_date';

  // Check if user has premium access
  static Future<bool> hasPremiumAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final tierIndex = prefs.getInt(_tierKey) ?? 0;

    if (tierIndex == 0) return false; // Free tier

    final expiryString = prefs.getString(_expiryKey);
    if (expiryString == null) return false;

    final expiryDate = DateTime.parse(expiryString);
    return DateTime.now().isBefore(expiryDate);
  }

  // Get current subscription tier
  static Future<SubscriptionTier> getCurrentTier() async {
    final hasPremium = await hasPremiumAccess();
    if (!hasPremium) return SubscriptionTier.free;

    final prefs = await SharedPreferences.getInstance();
    final tierIndex = prefs.getInt(_tierKey) ?? 0;
    return SubscriptionTier.values[tierIndex];
  }

  // Get subscription expiry date
  static Future<DateTime?> getExpiryDate() async {
    final prefs = await SharedPreferences.getInstance();
    final expiryString = prefs.getString(_expiryKey);
    return expiryString != null ? DateTime.parse(expiryString) : null;
  }

  // Get purchase date
  static Future<DateTime?> getPurchaseDate() async {
    final prefs = await SharedPreferences.getInstance();
    final purchaseString = prefs.getString(_purchaseDateKey);
    return purchaseString != null ? DateTime.parse(purchaseString) : null;
  }

  // Activate subscription
  static Future<void> activateSubscription(SubscriptionPlan plan) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final expiry = now.add(Duration(days: plan.durationMonths * 30));

    await prefs.setInt(_tierKey, plan.tier.index);
    await prefs.setString(_expiryKey, expiry.toIso8601String());
    await prefs.setString(_purchaseDateKey, now.toIso8601String());
  }

  // Cancel subscription (revert to free)
  static Future<void> cancelSubscription() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tierKey, 0);
    await prefs.remove(_expiryKey);
    await prefs.remove(_purchaseDateKey);
  }

  // Check if today is Sunday (for free tier access)
  static bool isSunday() {
    return DateTime.now().weekday == DateTime.sunday;
  }

  // Check if user can access devotionals
  static Future<bool> canAccessDevotionals() async {
    final hasPremium = await hasPremiumAccess();
    if (hasPremium) return true;

    // Free users can only access on Sunday
    return isSunday();
  }

  // Check if user can download devotionals
  static Future<bool> canDownloadDevotionals() async {
    return await hasPremiumAccess();
  }

  // Check if user can access additional Bible translations
  static Future<bool> canAccessTranslation(String translationId) async {
    // ASV is always available for free users
    if (translationId.toLowerCase() == 'asv') return true;

    // Other translations require premium
    return await hasPremiumAccess();
  }

  // Get days remaining in subscription
  static Future<int> getDaysRemaining() async {
    final expiryDate = await getExpiryDate();
    if (expiryDate == null) return 0;

    final difference = expiryDate.difference(DateTime.now());
    return difference.inDays.clamp(0, 999);
  }
}

// ------------------------- PAYMENT PLANS PAGE -------------------------

class EnhancedPaymentPlansPage extends StatefulWidget {
  const EnhancedPaymentPlansPage({super.key});

  @override
  State<EnhancedPaymentPlansPage> createState() =>
      _EnhancedPaymentPlansPageState();
}

class _EnhancedPaymentPlansPageState extends State<EnhancedPaymentPlansPage> {
  SubscriptionTier? currentTier;
  DateTime? expiryDate;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSubscriptionStatus();
  }

  Future<void> _loadSubscriptionStatus() async {
    setState(() => isLoading = true);

    try {
      final tier = await SubscriptionManager.getCurrentTier();
      final expiry = await SubscriptionManager.getExpiryDate();

      setState(() {
        currentTier = tier;
        expiryDate = expiry;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        currentTier = SubscriptionTier.free;
        isLoading = false;
      });
    }
  }

  Future<void> _selectPlan(SubscriptionPlan plan) async {
    if (plan.tier == SubscriptionTier.free) {
      _showInfoDialog('You are already on the free plan');
      return;
    }

    // Show plan confirmation
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _buildPlanConfirmationDialog(plan),
    );

    if (confirmed == true) {
      // Simulate payment processing
      await _processPurchase(plan);
    }
  }

  Widget _buildPlanConfirmationDialog(SubscriptionPlan plan) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: Text(
        'Upgrade to ${plan.name}',
        style: const TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'You are about to purchase:',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  plan.name,
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${plan.priceDisplay} for ${plan.durationDisplay}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  '\$${plan.pricePerMonth.toStringAsFixed(2)}/month',
                  style: const TextStyle(color: Colors.green, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'You will get access to:',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 8),
          ...plan.features.map(
            (feature) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                feature,
                style: const TextStyle(color: Colors.green, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          child: Text(
            'Purchase ${plan.priceDisplay}',
            style: const TextStyle(color: Colors.black),
          ),
        ),
      ],
    );
  }

  Future<void> _processPurchase(SubscriptionPlan plan) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          color: Color(0xFF1E1E1E),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.amber),
                SizedBox(height: 16),
                Text(
                  'Processing payment...',
                  style: TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // Simulate payment processing delay
    await Future.delayed(const Duration(seconds: 2));

    // Activate subscription
    await SubscriptionManager.activateSubscription(plan);

    // Reload status
    await _loadSubscriptionStatus();

    // Close loading dialog
    if (mounted) Navigator.pop(context);

    // Show success message
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 32),
              const SizedBox(width: 12),
              const Text('Success!', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have successfully upgraded to ${plan.name}!',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Your premium features are now active:',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...plan.features.map(
                      (feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          feature,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text(
                'Great!',
                style: TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showInfoDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Info', style: TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  Future<void> _manageSub() async {
    if (currentTier == SubscriptionTier.free) {
      _showInfoDialog(
        'You are currently on the free plan. Select a premium plan above to upgrade.',
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Manage Subscription',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Current Plan:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              SubscriptionPlan.allPlans
                  .firstWhere((p) => p.tier == currentTier)
                  .name,
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (expiryDate != null) ...[
              const SizedBox(height: 16),
              Text(
                'Expires: ${DateFormat('MMM dd, yyyy').format(expiryDate!)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 4),
              FutureBuilder<int>(
                future: SubscriptionManager.getDaysRemaining(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  return Text(
                    '${snapshot.data} days remaining',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  );
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  title: const Text(
                    'Cancel Subscription',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: const Text(
                    'Are you sure you want to cancel your subscription? You will lose access to premium features.',
                    style: TextStyle(color: Colors.white70),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(
                        'No, Keep It',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      child: const Text(
                        'Yes, Cancel',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await SubscriptionManager.cancelSubscription();
                await _loadSubscriptionStatus();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Subscription cancelled'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Cancel Subscription',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1E1E1E),
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("💳 Subscription Plans"),
        backgroundColor: Colors.black,
        actions: [
          if (currentTier != SubscriptionTier.free)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _manageSub,
              tooltip: 'Manage Subscription',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Current Status Banner
            _buildStatusBanner(),

            const SizedBox(height: 24),

            // Plans List
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose Your Plan',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Unlock premium features and support our mission',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),

                  ...SubscriptionPlan.allPlans.map((plan) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildPlanCard(plan),
                    );
                  }),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // FAQ Section
            _buildFAQSection(),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBanner() {
    final isFreeTier = currentTier == SubscriptionTier.free;
    final isPremium = !isFreeTier;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isFreeTier
              ? [Colors.grey[800]!, Colors.grey[900]!]
              : [Colors.amber[700]!, Colors.amber[900]!],
        ),
      ),
      child: Column(
        children: [
          Icon(
            isPremium ? Icons.workspace_premium : Icons.person,
            size: 48,
            color: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            isPremium ? 'Premium Member' : 'Free Member',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (isPremium && expiryDate != null) ...[
            Text(
              'Active until ${DateFormat('MMM dd, yyyy').format(expiryDate!)}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            FutureBuilder<int>(
              future: SubscriptionManager.getDaysRemaining(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                return Text(
                  '${snapshot.data} days remaining',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                );
              },
            ),
          ] else ...[
            const Text(
              'Limited access to devotionals',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            FutureBuilder<bool>(
              future: SubscriptionManager.canAccessDevotionals(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: snapshot.data! ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    snapshot.data!
                        ? '✅ Today is Sunday - Access granted!'
                        : '🔒 Devotionals available on Sunday only',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan) {
    final isCurrentPlan = plan.tier == currentTier;
    final isBestValue = plan.tier == SubscriptionTier.sixMonths;
    final isPremiumPlan = plan.tier != SubscriptionTier.free;

    return GestureDetector(
      onTap: isCurrentPlan ? null : () => _selectPlan(plan),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isCurrentPlan
                    ? Colors.amber
                    : isBestValue
                    ? Colors.green
                    : Colors.white24,
                width: isCurrentPlan || isBestValue ? 2 : 1,
              ),
              boxShadow: isCurrentPlan || isBestValue
                  ? [
                      BoxShadow(
                        color: (isCurrentPlan ? Colors.amber : Colors.green)
                            .withOpacity(0.3),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plan Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.name,
                          style: TextStyle(
                            color: isCurrentPlan ? Colors.amber : Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          plan.durationDisplay,
                          style: TextStyle(
                            color: isCurrentPlan
                                ? Colors.amber[300]
                                : Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          plan.priceDisplay,
                          style: TextStyle(
                            color: isCurrentPlan ? Colors.amber : Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isPremiumPlan)
                          Text(
                            '\$${plan.pricePerMonth.toStringAsFixed(2)}/mo',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Features
                ...plan.features.map(
                  (feature) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feature,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Limitations (for free plan)
                if (plan.limitations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 12),
                  ...plan.limitations.map(
                    (limitation) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        limitation,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Action Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isCurrentPlan ? null : () => _selectPlan(plan),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isCurrentPlan
                          ? Colors.grey[700]
                          : Colors.amber,
                      foregroundColor: isCurrentPlan
                          ? Colors.white
                          : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isCurrentPlan
                          ? 'Current Plan'
                          : plan.tier == SubscriptionTier.free
                          ? 'Free Forever'
                          : 'Select Plan',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Best Value Badge
          if (isBestValue)
            Positioned(
              top: -12,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Text(
                  '💎 BEST VALUE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          // Current Plan Badge
          if (isCurrentPlan)
            Positioned(
              top: -12,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.amber.withOpacity(0.5),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const Text(
                  '✨ ACTIVE',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFAQSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.help_outline, color: Colors.amber),
              SizedBox(width: 8),
              Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFAQItem(
            'Can I change my plan later?',
            'Yes! You can upgrade or downgrade your plan at any time.',
          ),
          _buildFAQItem(
            'What happens when my subscription expires?',
            'You will automatically revert to the free plan with limited access.',
          ),
          _buildFAQItem(
            'Are payments secure?',
            'Yes, all payments are processed securely through our payment provider.',
          ),
          _buildFAQItem(
            'Can I get a refund?',
            'Refunds are available within 7 days of purchase. Contact support for assistance.',
          ),
        ],
      ),
    );
  }

  Widget _buildFAQItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            answer,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
