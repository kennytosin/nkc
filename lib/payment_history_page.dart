import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'payment_database.dart';
import 'paystack_service.dart';

class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  List<PaymentRecord> payments = [];
  bool isLoading = true;
  String userEmail = '';
  double totalSpent = 0.0;
  int paymentCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPaymentHistory();
  }

  Future<void> _loadPaymentHistory() async {
    setState(() => isLoading = true);

    try {
      // Get user info
      final profile = await UserManager.instance.getUserProfile();
      userEmail = profile['email'] ?? '';

      // Get payment history
      final history = await PaystackService.instance.getUserPaymentHistory();
      // Only count successful payments for total spent
      final total = history.fold(0.0, (sum, payment) {
        return sum + (payment.status == 'successful' ? payment.amount : 0.0);
      });
      final count = history.length;

      setState(() {
        payments = history;
        totalSpent = total;
        paymentCount = count;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error loading payment history: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💳 Payment History'),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPaymentHistory,
            tooltip: 'Refresh',
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.amber),
            )
          : Column(
              children: [
                // Summary Card
                _buildSummaryCard(),

                const SizedBox(height: 16),

                // Payments List
                Expanded(
                  child: payments.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: payments.length,
                          itemBuilder: (context, index) {
                            return _buildPaymentCard(payments[index]);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber[700]!, Colors.amber[900]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Account Summary',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$paymentCount ${paymentCount == 1 ? 'payment' : 'payments'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            userEmail,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Spent',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '₦${totalSpent.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.receipt_long,
              size: 80,
              color: Colors.white30,
            ),
            const SizedBox(height: 24),
            const Text(
              'No Payment History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your payment history will appear here',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(PaymentRecord payment) {
    // Determine color and icon based on status
    Color statusColor;
    IconData statusIcon;

    if (payment.status == 'successful') {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (payment.status == 'cancelled') {
      statusColor = Colors.orange;
      statusIcon = Icons.cancel;
    } else {
      // Failed or any other status
      statusColor = Colors.red;
      statusIcon = Icons.error;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF2D2D2D),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: statusColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPaymentDetails(payment),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      payment.planName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusColor.withOpacity(0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: statusColor, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          payment.status.toUpperCase(),
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Amount
              Row(
                children: [
                  Text(
                    '₦ ${payment.amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')} ${payment.currency}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Details
              Row(
                children: [
                  const Icon(
                    Icons.calendar_today,
                    color: Colors.white54,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('MMM dd, yyyy • HH:mm').format(payment.createdAt),
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              Row(
                children: [
                  const Icon(
                    Icons.access_time,
                    color: Colors.white54,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${payment.planDurationMonths} month${payment.planDurationMonths != 1 ? 's' : ''} subscription',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Transaction ID
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tag,
                      color: Colors.white38,
                      size: 12,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'TX: ${payment.transactionId}',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPaymentDetails(PaymentRecord payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Row(
          children: [
            Icon(
              payment.status == 'successful'
                  ? Icons.check_circle
                  : Icons.error,
              color: payment.status == 'successful'
                  ? Colors.green
                  : Colors.red,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Payment Details',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Plan', payment.planName),
              _buildDetailRow('Amount', '₦${payment.amount.toStringAsFixed(0)} ${payment.currency}'),
              _buildDetailRow('Duration', '${payment.planDurationMonths} months'),
              _buildDetailRow('Status', payment.status.toUpperCase()),
              _buildDetailRow('Transaction ID', payment.transactionId),
              _buildDetailRow('Reference', payment.txRef),
              _buildDetailRow('Date', DateFormat('MMM dd, yyyy HH:mm:ss').format(payment.createdAt)),
              if (payment.verifiedAt != null)
                _buildDetailRow('Verified', DateFormat('MMM dd, yyyy HH:mm:ss').format(payment.verifiedAt!)),
              _buildDetailRow('User', payment.userEmail),
              if (payment.metadata?['test_mode'] == true)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Test Payment',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
