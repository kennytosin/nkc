import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  // Your Supabase Credentials
  static const String supabaseUrl = 'https://mmwxmkenjsojevilyxyx.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1td3hta2VuanNvamV2aWx5eHl4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTIwOTkwNTcsImV4cCI6MjA2NzY3NTA1N30.W7uO_wePLk9y8-8nqj3aT9KZFABjFVouiS4ixVFu9Pw';

  // Initialize Supabase
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    // Also store in SharedPreferences for the payment database
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('supabase_url', supabaseUrl);
    await prefs.setString('supabase_anon_key', supabaseAnonKey);

    print('✅ Supabase initialized');
    print('   URL: $supabaseUrl');
  }

  // Get Supabase client
  static SupabaseClient get client => Supabase.instance.client;

  // Check if Supabase is configured
  static Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('supabase_url') != null &&
           prefs.getString('supabase_anon_key') != null;
  }

  // Sync payment history from Supabase
  static Future<List<Map<String, dynamic>>> fetchPaymentHistory(
    String userEmail,
  ) async {
    try {
      final response = await client
          .from('payments')
          .select()
          .eq('user_email', userEmail)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching payment history from Supabase: $e');
      return [];
    }
  }

  // Manually sync a payment to Supabase
  static Future<bool> syncPayment(Map<String, dynamic> payment) async {
    try {
      await client.from('payments').insert(payment);
      print('✅ Payment synced to Supabase');
      return true;
    } catch (e) {
      print('❌ Error syncing payment to Supabase: $e');
      return false;
    }
  }

  // Create payments table in Supabase
  static const String createTableSQL = '''
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id TEXT NOT NULL,
  user_email TEXT NOT NULL,
  user_name TEXT NOT NULL,
  transaction_id TEXT UNIQUE NOT NULL,
  tx_ref TEXT NOT NULL,
  amount DECIMAL(10, 2) NOT NULL,
  currency TEXT NOT NULL,
  plan_id TEXT NOT NULL,
  plan_name TEXT NOT NULL,
  plan_duration_months INTEGER NOT NULL,
  status TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  verified_at TIMESTAMPTZ,
  metadata JSONB
);

-- Create indexes
CREATE INDEX idx_payments_user_id ON payments(user_id);
CREATE INDEX idx_payments_user_email ON payments(user_email);
CREATE INDEX idx_payments_transaction_id ON payments(transaction_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_created_at ON payments(created_at DESC);

-- Enable Row Level Security
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;

-- Policy: Users can view their own payments
CREATE POLICY "Users can view their own payments"
  ON payments FOR SELECT
  USING (user_email = auth.email() OR user_id = auth.uid()::text);

-- Policy: Anyone can insert payments (for anonymous users)
CREATE POLICY "Allow insert payments"
  ON payments FOR INSERT
  WITH CHECK (true);

-- Policy: Users can update their own payments
CREATE POLICY "Users can update their own payments"
  ON payments FOR UPDATE
  USING (user_email = auth.email() OR user_id = auth.uid()::text);
''';
}
