import 'dart:math';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'devotional_enhancements.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'payment_plans_enhancement.dart';
import 'package:device_preview/device_preview.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

// 1. User Profile Manager
class UserProfileManager {
  static const String _bucketName = 'profile-images';
  static const String _localCacheKey = 'cached_profile_image_';

  // ✅ Upload profile image to Supabase Storage
  static Future<String> uploadProfileImage({
    required String userId,
    required String imagePath,
  }) async {
    try {
      final file = File(imagePath);
      final fileExtension = p.extension(imagePath);

      // ✅ Add timestamp to filename to force new URL
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$userId/profile_$timestamp$fileExtension';

      print('📤 Uploading image: $fileName');

      // Read file as bytes
      final bytes = await file.readAsBytes();

      // Upload to Supabase Storage
      await Supabase.instance.client.storage
          .from(_bucketName)
          .uploadBinary(
            fileName,
            bytes,
            fileOptions: FileOptions(
              contentType: 'image/jpeg',
              cacheControl: '0', // ✅ Disable browser caching
              upsert: false, // ✅ Don't upsert, create new file
            ),
          );

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from(_bucketName)
          .getPublicUrl(fileName);

      print('✅ Image uploaded: $publicUrl');

      // Update user record in database
      await Supabase.instance.client
          .from('users')
          .update({'profile_image_url': publicUrl})
          .eq('id', userId)
          .select();

      // ✅ Clear old cache to force refresh
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_localCacheKey$userId');
      await prefs.remove('cached_url_$userId');

      // Cache the new image locally
      await prefs.setString('$_localCacheKey$userId', imagePath);
      await prefs.setString('cached_url_$userId', publicUrl);

      return publicUrl;
    } catch (e) {
      print('❌ Error uploading profile image: $e');
      rethrow;
    }
  }

  // ✅ Get profile image URL from Supabase
  static Future<String?> getProfileImageUrl(String userId) async {
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('profile_image_url')
          .eq('id', userId)
          .single();

      return response['profile_image_url'] as String?;
    } catch (e) {
      print('❌ Error fetching profile image URL: $e');
      return null;
    }
  }

  // ✅ Get cached local image path (for offline use)
  static Future<String?> getCachedImagePath(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_localCacheKey$userId');
  }

  // ✅ Download and cache profile image locally
  // ✅ Download and cache profile image locally
  static Future<String?> downloadAndCacheImage({
    required String userId,
    required String imageUrl,
  }) async {
    try {
      print('📥 Downloading image from: $imageUrl');

      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image: ${response.statusCode}');
      }

      // Save to app's document directory
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'profile_$userId.jpg';
      final localPath = p.join(appDir.path, fileName);

      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);

      // Cache the path and URL
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_localCacheKey$userId', localPath);
      await prefs.setString(
        'cached_url_$userId',
        imageUrl,
      ); // ✅ Save URL for comparison

      print('✅ Image cached locally: $localPath');
      return localPath;
    } catch (e) {
      print('❌ Error downloading image: $e');
      return null;
    }
  }

  // ✅ Remove profile image from Supabase and locally
  static Future<void> removeProfileImage(String userId) async {
    try {
      // Remove from Supabase Storage
      try {
        await Supabase.instance.client.storage.from(_bucketName).remove([
          '$userId/profile.jpg',
          '$userId/profile.png',
          '$userId/profile.jpeg',
        ]);
      } catch (e) {
        print('ℹ️ No cloud image to delete: $e');
      }

      // Update database
      await Supabase.instance.client
          .from('users')
          .update({'profile_image_url': null})
          .eq('id', userId)
          .select();

      // Remove local cache
      final prefs = await SharedPreferences.getInstance();
      final cachedPath = prefs.getString('$_localCacheKey$userId');

      if (cachedPath != null) {
        final file = File(cachedPath);
        if (await file.exists()) {
          await file.delete();
        }
        await prefs.remove('$_localCacheKey$userId');
      }

      print('✅ Profile image removed');
    } catch (e) {
      print('❌ Error removing profile image: $e');
      rethrow;
    }
  }

  // ✅ Get profile image (tries cloud first, then local cache)
  // ✅ Get profile image (checks for updates from cloud)
  static Future<String?> getProfileImage(
    String userId, {
    bool forceRefresh = false,
  }) async {
    try {
      // Get the cloud URL
      final cloudUrl = await getProfileImageUrl(userId);

      if (cloudUrl != null && cloudUrl.isNotEmpty) {
        final cachedPath = await getCachedImagePath(userId);

        // If force refresh or no cache, download new image
        if (forceRefresh ||
            cachedPath == null ||
            !await File(cachedPath).exists()) {
          print('☁️ Downloading fresh image from cloud');
          return await downloadAndCacheImage(
            userId: userId,
            imageUrl: cloudUrl,
          );
        }

        // ✅ Check if cached image is outdated by comparing with cloud version
        // Add timestamp to check when cache was last updated
        final prefs = await SharedPreferences.getInstance();
        final lastUpdateKey = 'last_update_$userId';
        final lastUpdate = prefs.getString(lastUpdateKey);

        // Extract timestamp from cloud URL (Supabase adds timestamps to URLs)
        // If URL has changed, it means image was updated
        final cachedUrlKey = 'cached_url_$userId';
        final cachedUrl = prefs.getString(cachedUrlKey);

        if (cachedUrl != cloudUrl) {
          // URL changed = image was updated, download new version
          print('🔄 Image was updated, downloading new version');
          final newPath = await downloadAndCacheImage(
            userId: userId,
            imageUrl: cloudUrl,
          );

          // Save the new URL
          await prefs.setString(cachedUrlKey, cloudUrl);
          return newPath;
        }

        // Use cached version
        print('📱 Using cached image (up to date)');
        return cachedPath;
      }

      // Fallback to local cache only (offline mode)
      print('💾 Using local cache only');
      return await getCachedImagePath(userId);
    } catch (e) {
      print('❌ Error getting profile image: $e');
      return await getCachedImagePath(userId);
    }
  }
}

// ------------------------- CLOUD SYNC MANAGER -------------------------
class CloudSyncManager {
  static final CloudSyncManager instance = CloudSyncManager._init();
  CloudSyncManager._init();

  // Sync favorites to cloud
  Future<void> syncFavoritesToCloud(String userId) async {
    try {
      print('☁️ Syncing favorites to cloud for user: $userId');

      // Get all local favorites
      final localFavorites = await UnifiedFavoritesDatabase.instance
          .getAllFavorites();

      // Upload each favorite to Supabase
      for (var favorite in localFavorites) {
        await Supabase.instance.client.from('user_favorites').upsert({
          'user_id': userId,
          'type': favorite['type'],
          'reference_id': favorite['reference_id'],
          'title': favorite['title'],
          'content': favorite['content'],
          'subtitle': favorite['subtitle'],
          'book_id': favorite['book_id'],
          'chapter': favorite['chapter'],
          'verse': favorite['verse'],
          'translation_id': favorite['translation_id'],
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,type,reference_id');
      }

      print(
        '✅ Successfully synced ${localFavorites.length} favorites to cloud',
      );
    } catch (e) {
      print('❌ Error syncing favorites to cloud: $e');
      rethrow;
    }
  }

  // Download favorites from cloud and merge with local
  Future<void> downloadFavoritesFromCloud(String userId) async {
    try {
      print('📥 Downloading favorites from cloud for user: $userId');

      // Get cloud favorites - filter by user_id manually
      final response = await Supabase.instance.client
          .from('user_favorites')
          .select()
          .eq('user_id', userId);

      final cloudFavorites = response as List<dynamic>;

      print('📦 Found ${cloudFavorites.length} favorites in cloud');

      // Merge with local favorites
      for (var cloudFav in cloudFavorites) {
        // Verify ownership
        if (cloudFav['user_id'] != userId) {
          print('⚠️ Skipping favorite - user mismatch');
          continue;
        }

        final referenceId = cloudFav['reference_id'] as String;
        final type = cloudFav['type'] as String;

        // Check if exists locally
        final existsLocally = await UnifiedFavoritesDatabase.instance
            .isFavorite(type: type, referenceId: referenceId);

        if (!existsLocally) {
          // Add to local database
          await UnifiedFavoritesDatabase.instance.addFavorite(
            type: type,
            referenceId: referenceId,
            title: cloudFav['title'] as String,
            content: cloudFav['content'] as String?,
            subtitle: cloudFav['subtitle'] as String?,
            bookId: cloudFav['book_id'] as int?,
            chapter: cloudFav['chapter'] as int?,
            verse: cloudFav['verse'] as int?,
            translationId: cloudFav['translation_id'] as String?,
          );
        }
      }

      print('✅ Successfully downloaded and merged favorites from cloud');
    } catch (e) {
      print('❌ Error downloading favorites from cloud: $e');
      rethrow;
    }
  }

  // Full sync: upload local favorites, then download cloud favorites
  Future<void> fullFavoritesSync(String userId) async {
    try {
      print('🔄 Starting full favorites sync...');
      await syncFavoritesToCloud(userId);
      await downloadFavoritesFromCloud(userId);
      print('✅ Full favorites sync completed');
    } catch (e) {
      print('❌ Error during full favorites sync: $e');
      rethrow;
    }
  }

  // Sync notification settings to cloud
  Future<void> syncNotificationSettingsToCloud(String userId) async {
    try {
      print('☁️ Syncing notification settings to cloud');

      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('notifications_enabled') ?? false;
      final hour = prefs.getInt('notification_hour') ?? 0;
      final minute = prefs.getInt('notification_minute') ?? 0;

      // Upload to Supabase
      await Supabase.instance.client.from('user_settings').upsert({
        'user_id': userId,
        'setting_key': 'notifications_enabled',
        'setting_value': isEnabled.toString(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,setting_key');

      await Supabase.instance.client.from('user_settings').upsert({
        'user_id': userId,
        'setting_key': 'notification_time',
        'setting_value': '$hour:$minute',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,setting_key');

      print('✅ Notification settings synced to cloud');
    } catch (e) {
      print('❌ Error syncing notification settings: $e');
      rethrow;
    }
  }

  // Download notification settings from cloud
  Future<void> downloadNotificationSettingsFromCloud(String userId) async {
    try {
      print('📥 Downloading notification settings from cloud');

      final response = await Supabase.instance.client
          .from('user_settings')
          .select()
          .eq('user_id', userId)
          .inFilter('setting_key', [
            'notifications_enabled',
            'notification_time',
          ]);

      final settings = response as List<dynamic>;

      if (settings.isEmpty) {
        print('ℹ️ No cloud settings found, using local settings');
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      for (var setting in settings) {
        // Verify ownership
        if (setting['user_id'] != userId) {
          print('⚠️ Skipping setting - user mismatch');
          continue;
        }

        final key = setting['setting_key'] as String;
        final value = setting['setting_value'] as String;

        if (key == 'notifications_enabled') {
          final isEnabled = value == 'true';
          await prefs.setBool('notifications_enabled', isEnabled);
          print('📲 Cloud notifications enabled: $isEnabled');
        } else if (key == 'notification_time') {
          final parts = value.split(':');
          if (parts.length == 2) {
            final hour = int.parse(parts[0]);
            final minute = int.parse(parts[1]);
            await prefs.setInt('notification_hour', hour);
            await prefs.setInt('notification_minute', minute);
            print('⏰ Cloud notification time: $hour:$minute');

            // Apply the notification settings
            final isEnabled = prefs.getBool('notifications_enabled') ?? false;
            if (isEnabled) {
              await NotificationService.enableDailyNotifications(
                hour: hour,
                minute: minute,
              );
            }
          }
        }
      }

      print('✅ Notification settings downloaded from cloud');
    } catch (e) {
      print('❌ Error downloading notification settings: $e');
      rethrow;
    }
  }

  // Full sync: upload local settings, then download cloud settings
  Future<void> fullSettingsSync(String userId) async {
    try {
      print('🔄 Starting full settings sync...');
      await syncNotificationSettingsToCloud(userId);
      await downloadNotificationSettingsFromCloud(userId);
      print('✅ Full settings sync completed');
    } catch (e) {
      print('❌ Error during full settings sync: $e');
      rethrow;
    }
  }

  // Master sync function: sync everything
  Future<void> syncAll(String userId) async {
    try {
      print('🌐 Starting full cloud sync...');
      await fullFavoritesSync(userId);
      await fullSettingsSync(userId);
      print('✅ All data synced successfully');
    } catch (e) {
      print('❌ Error during full sync: $e');
      rethrow;
    }
  }

  // Remove a favorite from cloud
  Future<void> removeFavoriteFromCloud({
    required String userId,
    required String type,
    required String referenceId,
  }) async {
    try {
      await Supabase.instance.client
          .from('user_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('type', type)
          .eq('reference_id', referenceId);

      print('✅ Favorite removed from cloud');
    } catch (e) {
      print('❌ Error removing favorite from cloud: $e');
      rethrow;
    }
  }
}

// 2. User Profile Page
class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage>
    with WidgetsBindingObserver {
  String? userName;
  String? profileImagePath;
  String? profileImageUrl;
  bool isLoading = true;
  bool isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    WidgetsBinding.instance.addObserver(this); // ✅ Add observer
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // ✅ Remove observer
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshProfileImage();
    }
  }

  Future<void> _loadUserData() async {
    final name = await getLoggedInUserName();

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null) {
      setState(() {
        userName = name;
        isLoading = false;
      });
      return;
    }

    // ✅ Get profile image (cloud or cached)
    final imagePath = await UserProfileManager.getProfileImage(userId);
    final imageUrl = await UserProfileManager.getProfileImageUrl(userId);

    setState(() {
      userName = name;
      profileImagePath = imagePath;
      profileImageUrl = imageUrl;
      isLoading = false;
    });
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (image != null) {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id');

        if (userId == null) {
          throw Exception('User ID not found');
        }

        setState(() => isUploading = true);

        // ✅ FIXED: Remove onProgress parameter
        final publicUrl = await UserProfileManager.uploadProfileImage(
          userId: userId,
          imagePath: image.path,
        );

        setState(() {
          profileImagePath = image.path;
          profileImageUrl = publicUrl;
          isUploading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Profile image updated and synced!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => isUploading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to update image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeImage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Remove Profile Picture',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to remove your profile picture? This will remove it from all your devices.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id');

        if (userId != null) {
          setState(() => isUploading = true);

          await UserProfileManager.removeProfileImage(userId);

          setState(() {
            profileImagePath = null;
            profileImageUrl = null;
            isUploading = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Profile picture removed from all devices'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        setState(() => isUploading = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed to remove image: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
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
        title: const Text('👤 My Profile'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Profile Picture with upload indicator
                Stack(
                  children: [
                    GestureDetector(
                      onTap: isUploading ? null : () => _pickImage(),
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.amber, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withOpacity(0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: profileImagePath != null
                              ? Image.file(
                                  File(profileImagePath!),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return _buildDefaultAvatar();
                                  },
                                )
                              : _buildDefaultAvatar(),
                        ),
                      ),
                    ),

                    // Upload indicator
                    if (isUploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black.withOpacity(0.7),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ),

                    if (!isUploading)
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: Colors.amber,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            color: Colors.black,
                            size: 20,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 24),

                // User Name
                Text(
                  userName ?? 'User',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: 8),

                const Text(
                  'NKC Devotional Member',
                  style: TextStyle(fontSize: 16, color: Colors.white54),
                ),

                const SizedBox(height: 40),

                // Action Buttons
                _buildActionButton(
                  icon: Icons.photo_library,
                  label: 'Change Profile Picture',
                  onTap: isUploading ? null : () => _pickImage(),
                  color: Colors.amber,
                ),

                const SizedBox(height: 12),

                if (profileImagePath != null || profileImageUrl != null)
                  _buildActionButton(
                    icon: Icons.delete,
                    label: 'Remove Profile Picture',
                    onTap: isUploading ? null : () => _removeImage(),
                    color: Colors.red,
                  ),

                const SizedBox(height: 12),

                _buildActionButton(
                  icon: Icons.edit,
                  label: 'Change Username',
                  onTap: () => _changeUsername(),
                  color: Colors.blue,
                ),

                const SizedBox(height: 12),

                _buildActionButton(
                  icon: Icons.lock_reset,
                  label: 'Change PIN',
                  onTap: () => _changePassword(),
                  color: Colors.green,
                ),

                const SizedBox(height: 40),

                // User Info Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      _buildInfoRow(
                        Icons.person,
                        'Username',
                        userName ?? 'N/A',
                      ),
                      const Divider(color: Colors.white24, height: 32),
                      _buildInfoRow(
                        Icons.calendar_today,
                        'Member Since',
                        DateTime.now().toString().substring(0, 10),
                      ),
                      if (profileImageUrl != null) ...[
                        const Divider(color: Colors.white24, height: 32),
                        _buildInfoRow(Icons.cloud_done, 'Synced', 'Yes'),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Tips Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[900]?.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_upload, color: Colors.blue[300]),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Your profile picture is synced across all devices. Changes will appear everywhere you log in!',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Loading overlay
          if (isUploading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 16),
                    Text(
                      'Uploading...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: Colors.grey[800],
      child: const Icon(Icons.person, size: 80, color: Colors.white54),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: color == Colors.amber ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.amber, size: 20),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<void> _changeUsername() async {
    final TextEditingController controller = TextEditingController(
      text: userName,
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Change Username',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter new username',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != userName) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id');

        if (userId != null) {
          // Update in Supabase
          await Supabase.instance.client
              .from('users')
              .update({'name': newName.toLowerCase()})
              .eq('id', userId)
              .select();

          // Update locally
          await prefs.setString('user_name', newName);

          setState(() {
            userName = newName;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Username updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed to update username: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _refreshProfileImage() async {
    try {
      setState(() => isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');

      if (userId == null) {
        throw Exception('User ID not found');
      }

      // ✅ Force refresh from cloud
      final imagePath = await UserProfileManager.getProfileImage(
        userId,
        forceRefresh: true,
      );
      final imageUrl = await UserProfileManager.getProfileImageUrl(userId);

      setState(() {
        profileImagePath = imagePath;
        profileImageUrl = imageUrl;
        isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile picture refreshed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to refresh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _changePassword() async {
    final TextEditingController oldPinController = TextEditingController();
    final TextEditingController newPinController = TextEditingController();
    final TextEditingController confirmPinController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Change PIN', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: oldPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Current PIN',
                labelStyle: TextStyle(color: Colors.white70),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: newPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'New PIN',
                labelStyle: TextStyle(color: Colors.white70),
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Confirm New PIN',
                labelStyle: TextStyle(color: Colors.white70),
                counterText: '',
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
            onPressed: () {
              final oldPin = oldPinController.text.trim();
              final newPin = newPinController.text.trim();
              final confirmPin = confirmPinController.text.trim();

              if (oldPin.isEmpty || newPin.isEmpty || confirmPin.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('❌ All fields are required')),
                );
                return;
              }

              if (newPin.length < 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ PIN must be at least 4 digits'),
                  ),
                );
                return;
              }

              if (newPin != confirmPin) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('❌ New PINs do not match')),
                );
                return;
              }

              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text(
              'Change PIN',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id');
        final oldPin = oldPinController.text.trim();
        final newPin = newPinController.text.trim();

        if (userId != null) {
          // Verify old PIN
          final user = await Supabase.instance.client
              .from('users')
              .select('pin')
              .eq('id', userId)
              .single();

          if (user['pin'] != oldPin) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Current PIN is incorrect'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          // Update PIN in Supabase
          await Supabase.instance.client
              .from('users')
              .update({'pin': newPin})
              .eq('id', userId)
              .select();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ PIN changed successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Failed to change PIN: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

// ------------------------- DEVOTIONAL MODEL -------------------------
class Devotional {
  final String id;
  final String title;
  final String content;
  final DateTime date;

  Devotional({
    required this.id,
    required this.title,
    required this.content,
    required this.date,
  });

  factory Devotional.fromJson(Map<String, dynamic> json) {
    return Devotional(
      id: json['id'].toString(),
      title: json['title'],
      content: json['content'],
      date: DateTime.parse(json['date']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'date': date.toIso8601String(),
    };
  }

  factory Devotional.fromMap(Map<String, dynamic> map) {
    return Devotional(
      id: map['id'],
      title: map['title'],
      content: map['content'],
      date: DateTime.parse(map['date']),
    );
  }
}

// ------------------------- SUPABASE FUNCTIONS -------------------------
Future<String?> fetchAdminPassword() async {
  final response = await Supabase.instance.client
      .from('admin_settings')
      .select('value')
      .eq('key', 'admin_password')
      .limit(1)
      .single();

  return response['value'] as String?;
}

// Fetch Verse of the Month
Future<Map<String, String>> fetchVerseOfTheMonth() async {
  try {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;

    final response = await Supabase.instance.client
        .from('monthly_verses')
        .select('verse_text, verse_reference')
        .eq('year', year)
        .eq('month', month)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      return {
        'text': response['verse_text'] as String,
        'reference': response['verse_reference'] as String,
      };
    }

    // Fallback verse if no verse for this month
    return {
      'text': 'I can do all things through Christ who strengthens me.',
      'reference': 'Philippians 4:13',
    };
  } catch (e) {
    print('❌ Error fetching verse of the month: $e');
    return {
      'text': 'I can do all things through Christ who strengthens me.',
      'reference': 'Philippians 4:13',
    };
  }
}

// Fetch Theme of the Month
Future<String> fetchThemeOfTheMonth() async {
  try {
    final now = DateTime.now();
    final year = now.year;
    final month = now.month;

    final response = await Supabase.instance.client
        .from('monthly_themes')
        .select('theme_text')
        .eq('year', year)
        .eq('month', month)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      return response['theme_text'] as String;
    }

    // Fallback theme if no theme for this month
    return 'Walking in Faith and Victory';
  } catch (e) {
    print('❌ Error fetching theme of the month: $e');
    return 'Walking in Faith and Victory';
  }
}

Future<Map<String, String>> fetchVerseOfTheDay() async {
  try {
    final today = DateTime.now().toIso8601String().split('T')[0];

    final response = await Supabase.instance.client
        .from('daily_verses')
        .select('verse_text, verse_reference')
        .eq('date', today)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      return {
        'text': response['verse_text'] as String,
        'reference': response['verse_reference'] as String,
      };
    }

    return {
      'text': 'I can do all things through Christ who strengthens me.',
      'reference': 'Philippians 4:13',
    };
  } catch (e) {
    print('❌ Error fetching verse of the day: $e');
    return {
      'text': 'I can do all things through Christ who strengthens me.',
      'reference': 'Philippians 4:13',
    };
  }
}

Future<String> fetchConfessionOfTheDay() async {
  try {
    final today = DateTime.now().toIso8601String().split('T')[0];

    final response = await Supabase.instance.client
        .from('daily_confessions')
        .select('confession_text')
        .eq('date', today)
        .limit(1)
        .maybeSingle();

    if (response != null) {
      return response['confession_text'] as String;
    }

    return 'I am more than a conqueror through Christ!';
  } catch (e) {
    print('❌ Error fetching confession of the day: $e');
    return 'I am more than a conqueror through Christ!';
  }
}

Future<void> addDevotional({
  required String title,
  required String content,
  required DateTime date,
}) async {
  try {
    final response = await Supabase.instance.client.from('devotionals').insert({
      'title': title,
      'content': content,
      'date': date.toIso8601String(),
    });

    print('✅ Inserted: $response');
    print('Devotional added');
  } catch (error) {
    print('❌ Insert failed: $error');
  }
}

Future<List<Devotional>> fetchDevotionals() async {
  final response = await Supabase.instance.client
      .from('devotionals')
      .select()
      .order('date', ascending: false);

  return (response as List).map((json) => Devotional.fromJson(json)).toList();
}

// ------------------------- AUTHENTICATION FUNCTIONS -------------------------
Future<bool> registerUser({required String name, required String pin}) async {
  try {
    // Check if user already exists (case-insensitive)
    final existingUser = await Supabase.instance.client
        .from('users')
        .select()
        .eq('name', name.toLowerCase()) // ✅ Convert to lowercase
        .limit(1)
        .maybeSingle();

    if (existingUser != null) {
      throw Exception('User with this name already exists');
    }

    // Insert new user with lowercase username
    await Supabase.instance.client.from('users').insert({
      'name': name.toLowerCase(), // ✅ Store as lowercase
      'pin': pin,
      'created_at': DateTime.now().toIso8601String(),
    });

    return true;
  } catch (error) {
    print('❌ Registration failed: $error');
    rethrow;
  }
}

Future<Map<String, dynamic>?> loginUser({
  required String name,
  required String pin,
}) async {
  try {
    // ✅ Convert username to lowercase before querying
    final response = await Supabase.instance.client
        .from('users')
        .select('id, name, pin, created_at')
        .eq('name', name.toLowerCase()) // ✅ Convert to lowercase
        .eq('pin', pin)
        .limit(1)
        .maybeSingle();

    return response;
  } catch (error) {
    print('❌ Login failed: $error');
    return null;
  }
}

// ------------------------- AUTHENTICATION PAGE -------------------------
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  bool isLogin = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final _nameController = TextEditingController();
  final _pinController = TextEditingController();

  bool _isPinVisible = false;
  bool _isLoading = false;
  bool _isOnline = true;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
    _checkInternetConnectivity();
  }

  Future<void> _checkInternetConnectivity() async {
    try {
      final connectivityResult = await Connectivity().checkConnectivity();

      if (connectivityResult == ConnectivityResult.none) {
        if (mounted) setState(() => _isOnline = false);
        return;
      }

      final result = await InternetAddress.lookup(
        'youtube.com',
      ).timeout(const Duration(seconds: 5));

      if (mounted) {
        setState(() {
          _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isOnline = false);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _nameController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _toggleAuthMode() {
    setState(() {
      isLogin = !isLogin;
    });
    _animationController.reset();
    _animationController.forward();
  }

  Future<void> _handleAuth() async {
    if (!_isOnline) {
      _showErrorSnackBar(
        'No internet connection. Please check your connection and try again.',
      );
      return;
    }

    final name = _nameController.text.trim();
    final pin = _pinController.text.trim();

    if (name.isEmpty || pin.isEmpty) {
      _showErrorSnackBar('Please enter both name and PIN');
      return;
    }

    if (pin.length < 4) {
      _showErrorSnackBar('PIN must be at least 4 digits');
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (isLogin) {
        final user = await loginUser(name: name, pin: pin);

        if (user != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('user_name', name);
          await prefs.setBool('is_logged_in', true);

          final userId = user['id'] as String;
          await prefs.setString('user_id', userId);

          // ✅ FIXED: Initialize notifications BEFORE syncing settings
          // This ensures the notification service is ready to schedule notifications
          try {
            await NotificationService.initialize();
            print('🔔 Notification service initialized for new login');
          } catch (e) {
            print('⚠️ Could not initialize notifications: $e');
          }

          // ✅ Sync data from cloud after login
          try {
            await CloudSyncManager.instance.syncAll(userId);
            print('✅ All data synced from cloud after login');
          } catch (e) {
            print('⚠️ Could not sync data from cloud: $e');
          }

          if (mounted) {
            _showSuccessSnackBar('Welcome back, $name!');
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const DailyDevotionalApp()),
            );
          }
        } else {
          _showErrorSnackBar('Invalid name or PIN');
        }
      } else {
        await registerUser(name: name, pin: pin);

        final user = await loginUser(name: name, pin: pin);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', name);
        await prefs.setBool('is_logged_in', true);

        if (user != null) {
          final userId = user['id'] as String;
          await prefs.setString('user_id', userId);
        }

        if (mounted) {
          _showSuccessSnackBar('Account created successfully!');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DailyDevotionalApp()),
          );
        }
      }
    } catch (e) {
      _showErrorSnackBar(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      body: Stack(
        children: [
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        _buildAppHeader(),
                        const SizedBox(height: 48),
                        if (!_isOnline) _buildOfflineWarning(),
                        _buildAuthCard(),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildAppHeader() {
    return Column(
      children: [
        // App Icon - Just the image, no background or shadow
        SizedBox(
          width: 100,
          height: 100,
          child: Image.asset(
            'assets/images/iiii.png',
            fit: BoxFit.contain, // or BoxFit.cover depending on your preference
            errorBuilder: (context, error, stackTrace) {
              // Fallback icon if image fails to load
              return const Icon(Icons.menu_book, size: 80, color: Colors.amber);
            },
          ),
        ),
        const SizedBox(height: 24),

        // App Title
        const Text(
          'NKC DEVOTIONAL',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 8),

        // Subtitle
        const Text(
          'Your Daily Spiritual Companion',
          style: TextStyle(
            fontSize: 16,
            color: Colors.white70,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }

  Widget _buildOfflineWarning() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red, width: 2),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off, color: Colors.red, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No Internet Connection',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Please check your connection and try again',
                  style: TextStyle(color: Colors.red[200], fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Tab Header
          Text(
            isLogin ? 'Welcome Back' : 'Create Account',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isLogin
                ? 'Sign in to continue your devotional journey'
                : 'Start your spiritual journey with us',
            style: const TextStyle(fontSize: 14, color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Username Field
          _buildTextField(
            controller: _nameController,
            label: 'Username',
            hint: 'Enter your username',
            icon: Icons.person_outline,
          ),

          const SizedBox(height: 20),

          // PIN Field
          _buildTextField(
            controller: _pinController,
            label: 'PIN',
            hint: 'Enter your PIN',
            icon: Icons.lock_outline,
            isPassword: true,
            isVisible: _isPinVisible,
            keyboardType: TextInputType.number,
            maxLength: 6,
            onVisibilityToggle: () {
              setState(() {
                _isPinVisible = !_isPinVisible;
              });
            },
          ),

          const SizedBox(height: 32),

          // Auth Button
          _buildAuthButton(
            onPressed: _handleAuth,
            label: isLogin ? 'Login' : 'Sign Up',
          ),

          const SizedBox(height: 24),

          // Toggle Auth Mode
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isLogin
                    ? "Don't have an account? "
                    : 'Already have an account? ',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              TextButton(
                onPressed: _toggleAuthMode,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  isLogin ? 'Sign Up' : 'Login',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool isVisible = false,
    VoidCallback? onVisibilityToggle,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12, width: 1),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword && !isVisible,
            keyboardType: keyboardType,
            maxLength: maxLength,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 14),
              prefixIcon: Icon(icon, color: Colors.white54, size: 22),
              suffixIcon: isPassword
                  ? IconButton(
                      onPressed: onVisibilityToggle,
                      icon: Icon(
                        isVisible ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white54,
                        size: 22,
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              counterText: '',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthButton({
    required VoidCallback onPressed,
    required String label,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: (_isLoading || !_isOnline) ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isOnline ? Colors.amber : Colors.grey,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.grey[700],
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2.5,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.amber),
            SizedBox(height: 16),
            Text(
              'Please wait...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static const String _notificationChannelId = 'daily_devotional_channel';
  static const String _notificationChannelName = 'Daily Devotional';
  static const String _notificationChannelDescription =
      'Daily reminders for devotional reading';

  static const int _dailyNotificationId = 1000;

  static const String _enabledKey = 'notifications_enabled';
  static const String _hourKey = 'notification_hour';
  static const String _minuteKey = 'notification_minute';

  /// Initialize notifications with proper timezone handling
  static Future<void> initialize() async {
    // ✅ Initialize timezone database
    tz.initializeTimeZones();

    // ✅ FIXED: Get device timezone properly
    try {
      // Get the system timezone name (e.g., "Africa/Lagos" for WAT)
      final String timeZoneName = await _getDeviceTimeZone();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      print('🌍 Timezone set to: $timeZoneName');
    } catch (e) {
      print('⚠️ Could not set device timezone: $e, using UTC');
      tz.setLocalLocation(tz.getLocation('UTC'));
    }

    // Android settings
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      await _createNotificationChannel();

      print('✅ Notification service initialized successfully');
    } catch (e) {
      print('❌ Failed to initialize notifications: $e');
    }
  }

  /// Get device timezone name
  static Future<String> _getDeviceTimeZone() async {
    try {
      // Get timezone offset
      final now = DateTime.now();
      final offset = now.timeZoneOffset;

      // Map common offsets to timezone names
      // WAT (West Africa Time) is UTC+1
      if (offset.inHours == 1 && offset.inMinutes % 60 == 0) {
        return 'Africa/Lagos'; // WAT timezone
      }

      // Add more timezone mappings as needed
      final offsetHours = offset.inHours;
      final offsetMinutes = offset.inMinutes % 60;

      print(
        '⏰ Device offset: UTC${offsetHours >= 0 ? '+' : ''}$offsetHours:${offsetMinutes.abs().toString().padLeft(2, '0')}',
      );

      // Common timezone mappings based on offset
      switch (offsetHours) {
        case -8:
          return 'America/Los_Angeles';
        case -7:
          return 'America/Denver';
        case -6:
          return 'America/Chicago';
        case -5:
          return 'America/New_York';
        case 0:
          return 'Europe/London';
        case 1:
          return 'Africa/Lagos'; // WAT
        case 2:
          return 'Africa/Cairo';
        case 3:
          return 'Africa/Nairobi';
        case 5:
          return 'Asia/Karachi';
        case 6:
          return 'Asia/Dhaka';
        case 8:
          return 'Asia/Shanghai';
        case 9:
          return 'Asia/Tokyo';
        default:
          // Fallback to UTC if unknown
          return 'UTC';
      }
    } catch (e) {
      print('❌ Error getting device timezone: $e');
      return 'UTC';
    }
  }

  /// Create notification channel for Android
  static Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _notificationChannelId,
      _notificationChannelName,
      description: _notificationChannelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// Handle notification tap
  static void _onNotificationTapped(NotificationResponse response) {
    print('Notification tapped: ${response.payload}');
  }

  /// Enable daily notifications at specified time
  static Future<void> enableDailyNotifications({
    int hour = 0,
    int minute = 0,
  }) async {
    try {
      // Save user's selected time
      await _saveNotificationSettings(
        enabled: true,
        hour: hour,
        minute: minute,
      );

      // Schedule notification at the EXACT time user selected
      await _scheduleDailyNotification(hour, minute);

      print('✅ Daily notifications enabled');
      print('   User selected: ${_formatTime(hour, minute)}');
      print('   Device timezone: ${DateTime.now().timeZoneName}');
    } catch (e) {
      print('❌ Failed to enable daily notifications: $e');
      rethrow;
    }
  }

  /// Disable daily notifications
  static Future<void> disableDailyNotifications() async {
    try {
      await _notifications.cancel(_dailyNotificationId);
      await _saveNotificationSettings(enabled: false);
      print('✅ Daily notifications disabled');
    } catch (e) {
      print('❌ Failed to disable daily notifications: $e');
      rethrow;
    }
  }

  /// Update notification time
  static Future<void> updateNotificationTime(int hour, int minute) async {
    try {
      final isEnabled = await isNotificationsEnabled();

      if (isEnabled) {
        await _notifications.cancel(_dailyNotificationId);
        await _scheduleDailyNotification(hour, minute);
      }

      await _saveNotificationSettings(
        enabled: isEnabled,
        hour: hour,
        minute: minute,
      );

      print('✅ Notification time updated to ${_formatTime(hour, minute)}');
    } catch (e) {
      print('❌ Failed to update notification time: $e');
      rethrow;
    }
  }

  /// ✅ FIXED: Schedule daily recurring notification with proper timezone
  static Future<void> _scheduleDailyNotification(int hour, int minute) async {
    try {
      // Get current time in the device's timezone
      final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

      print('🕐 Current device time: $now');
      print('🌍 Device timezone: ${now.location.name}');
      print(
        '🎯 Scheduling for: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
      );

      // Create scheduled time in device's timezone
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      // If the time is in the past today, schedule for tomorrow
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
        print('⏭️ Time is in past, scheduling for tomorrow');
      }

      print('📅 Will trigger at: $scheduledDate');

      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            _notificationChannelId,
            _notificationChannelName,
            channelDescription: _notificationChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            icon: '@mipmap/ic_launcher',
            largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
          );

      const NotificationDetails notificationDetails = NotificationDetails(
        android: androidDetails,
      );

      await _notifications.zonedSchedule(
        _dailyNotificationId,
        '📖 Daily Devotional',
        'Your daily devotional is ready! Tap to read today\'s message 🙏',
        scheduledDate,
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: 'daily_devotional',
      );

      print('✅ Notification scheduled successfully');

      // Calculate hours until notification
      final difference = scheduledDate.difference(now);
      final hoursUntil = difference.inHours;
      final minutesUntil = difference.inMinutes % 60;
      print('⏰ Next notification in: ${hoursUntil}h ${minutesUntil}m');
    } catch (e) {
      print('❌ Error scheduling notification: $e');
      rethrow;
    }
  }

  /// Send a test notification immediately
  static Future<void> sendTestNotification() async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'test_channel',
          'Test Notifications',
          channelDescription: 'Channel for test notifications',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidDetails,
    );

    try {
      await _notifications.show(
        999,
        '🧪 Test Notification',
        'This is a test notification. Your daily reminders will look like this!',
        notificationDetails,
        payload: 'test_notification',
      );

      print('✅ Test notification sent');
    } catch (e) {
      print('❌ Failed to send test notification: $e');
      rethrow;
    }
  }

  /// Save notification settings to SharedPreferences
  static Future<void> _saveNotificationSettings({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_enabledKey, enabled);

    if (hour != null) {
      await prefs.setInt(_hourKey, hour);
    }

    if (minute != null) {
      await prefs.setInt(_minuteKey, minute);
    }
  }

  /// Check if notifications are enabled
  static Future<bool> isNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// Get saved notification time
  static Future<TimeOfDay> getNotificationTime() async {
    final prefs = await SharedPreferences.getInstance();
    final hour = prefs.getInt(_hourKey) ?? 0;
    final minute = prefs.getInt(_minuteKey) ?? 0;

    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Load and apply saved notification settings
  static Future<void> loadAndApplySettings() async {
    try {
      final isEnabled = await isNotificationsEnabled();

      if (isEnabled) {
        final time = await getNotificationTime();
        await _scheduleDailyNotification(time.hour, time.minute);

        print('📱 Restored daily notifications');
        print('   Time: ${_formatTime(time.hour, time.minute)}');
        print('   Timezone: ${DateTime.now().timeZoneName}');
      }
    } catch (e) {
      print('❌ Failed to load notification settings: $e');
    }
  }

  /// Get pending notifications
  static Future<List<PendingNotificationRequest>>
  getPendingNotifications() async {
    return await _notifications.pendingNotificationRequests();
  }

  /// Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    await _notifications.cancelAll();
    print('🗑️ All notifications cancelled');
  }

  /// Format time for display
  static String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');

    return '$displayHour:$displayMinute $period';
  }

  /// ✅ NEW: Debug method to check notification status
  static Future<void> printDebugInfo() async {
    print('=== NOTIFICATION DEBUG INFO ===');

    // Device timezone
    final now = DateTime.now();
    final tzNow = tz.TZDateTime.now(tz.local);
    print('📍 System timezone: ${now.timeZoneName}');
    print('📍 TZ timezone: ${tzNow.location.name}');
    print('🕐 Current time: $now');
    print('🕐 TZ current time: $tzNow');

    // Saved settings
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_enabledKey) ?? false;
    final hour = prefs.getInt(_hourKey) ?? 0;
    final minute = prefs.getInt(_minuteKey) ?? 0;
    print('⚙️ Enabled: $enabled');
    print(
      '⚙️ Scheduled time: ${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
    );

    // Pending notifications
    final pending = await getPendingNotifications();
    print('📋 Pending notifications: ${pending.length}');
    for (var notif in pending) {
      print('   - ID: ${notif.id}, Title: ${notif.title}');
    }

    print('===========================');
  }
}

// Extension to make TimeOfDay formatting easier
extension TimeOfDayExtension on TimeOfDay {
  String get formatted {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final displayMinute = minute.toString().padLeft(2, '0');

    return '$displayHour:$displayMinute $period';
  }
}

Future checkLoginStatus() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('is_logged_in') ?? false;
}

Future getLoggedInUserName() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('user_name');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notifications FIRST
  await NotificationService.initialize();

  await UnifiedFavoritesDatabase.instance.database;

  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  await Supabase.initialize(
    url: 'https://mmwxmkenjsojevilyxyx.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1td3hta2VuanNvamV2aWx5eHl4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTIwOTkwNTcsImV4cCI6MjA2NzY3NTA1N30.W7uO_wePLk9y8-8nqj3aT9KZFABjFVouiS4ixVFu9Pw',
  );

  // Load and apply saved notification settings
  await NotificationService.loadAndApplySettings();

  // Initialize Bible database with sample data
  await SimpleBibleDatabase.addSampleData();

  // Initialize Bible Translation Manager
  await BibleTranslationManager.instance.initializeTranslations();

  // 🔑 Check if user is already logged in
  final isLoggedIn = await checkLoginStatus();

  // ✅ NEW: Clean up any incomplete downloads from previous session
  await BibleTranslationManager.instance.cleanupIncompleteDownloads();

  runApp(
    DevicePreview(
      enabled: !kReleaseMode, // ✅ Only enabled in debug mode
      builder: (context) => ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return DevotionalApp(isLoggedIn: isLoggedIn);
        },
      ),
    ),
  );
}

class DownloadsDatabase {
  static final DownloadsDatabase instance = DownloadsDatabase._init();
  static Database? _database;
  static bool _isInitialized = false;

  DownloadsDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('downloads.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    // Only delete on first initialization
    if (!_isInitialized && await databaseExists(path)) {
      print('🔍 Checking existing database...');

      try {
        final testDb = await openDatabase(path, readOnly: true);
        final tables = await testDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='downloads'",
        );
        await testDb.close();

        if (tables.isEmpty) {
          print('⚠️ Downloads table missing - deleting database');
          await deleteDatabase(path);
        } else {
          print('✅ Database is valid');
        }
      } catch (e) {
        print('⚠️ Error checking database: $e - deleting');
        await deleteDatabase(path);
      }
    }

    _isInitialized = true;

    print('🔨 Opening downloads database...');
    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    print('📝 Creating downloads table...');
    await db.execute('''
      CREATE TABLE downloads (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');
    print('✅ Downloads table created');
  }

  // Insert devotional
  Future<void> insertDevotional(Devotional devotional) async {
    try {
      print('💾 Saving devotional: ${devotional.title}');
      final db = await instance.database;

      await db.insert('downloads', {
        'id': devotional.id,
        'title': devotional.title,
        'content': devotional.content,
        'date': devotional.date.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      print('✅ Devotional saved successfully');
    } catch (e) {
      print('❌ Error saving devotional: $e');
      rethrow;
    }
  }

  // Get all devotionals
  Future<List<Devotional>> getAllDevotionals() async {
    try {
      final db = await instance.database;
      print('📖 Fetching all downloads...');

      final result = await db.query('downloads', orderBy: 'date DESC');
      print('✅ Found ${result.length} downloaded devotional(s)');

      return result
          .map(
            (json) => Devotional(
              id: json['id'] as String,
              title: json['title'] as String,
              content: json['content'] as String,
              date: DateTime.parse(json['date'] as String),
            ),
          )
          .toList();
    } catch (e) {
      print('❌ Error fetching downloads: $e');
      rethrow;
    }
  }

  // Get devotional by ID
  Future<Devotional?> getDevotionalById(String id) async {
    try {
      final db = await instance.database;
      final maps = await db.query(
        'downloads',
        where: 'id = ?',
        whereArgs: [id],
      );

      if (maps.isNotEmpty) {
        final json = maps.first;
        return Devotional(
          id: json['id'] as String,
          title: json['title'] as String,
          content: json['content'] as String,
          date: DateTime.parse(json['date'] as String),
        );
      }
      return null;
    } catch (e) {
      print('❌ Error fetching devotional by ID: $e');
      return null;
    }
  }

  // Check if devotional is downloaded
  Future<bool> isDownloaded(String id) async {
    try {
      final devotional = await getDevotionalById(id);
      return devotional != null;
    } catch (e) {
      print('❌ Error checking download status: $e');
      return false;
    }
  }

  // Delete devotional
  Future<void> deleteDevotional(String id) async {
    try {
      final db = await instance.database;
      await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
      print('✅ Devotional $id deleted');
    } catch (e) {
      print('❌ Error deleting devotional: $e');
      rethrow;
    }
  }

  // DON'T close the database - keep it open for the app lifetime
  // Only close when absolutely necessary (app termination)
}

class DevotionalDatabase {
  static Database? _database;

  static Future<Database> getDatabase() async {
    if (_database != null) return _database!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'devotionals.db');

    _database = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute('''
          CREATE TABLE downloads (
            id TEXT PRIMARY KEY,
            title TEXT,
            content TEXT,
            date TEXT
          )
        ''');
      },
    );
    return _database!;
  }

  static Future<void> insertDevotional(Devotional devotional) async {
    final db = await getDatabase();
    await db.insert(
      'downloads',
      devotional.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<List<Devotional>> getAllDownloads() async {
    final db = await getDatabase();
    final List<Map<String, dynamic>> maps = await db.query('downloads');
    return maps.map((map) => Devotional.fromMap(map)).toList();
  }

  static Future<void> deleteDevotional(String id) async {
    final db = await getDatabase();
    await db.delete('downloads', where: 'id = ?', whereArgs: [id]);
  }

  static Future<bool> isDownloaded(String id) async {
    final db = await getDatabase();
    final List<Map<String, dynamic>> maps = await db.query(
      'downloads',
      where: 'id = ?',
      whereArgs: [id],
    );
    return maps.isNotEmpty;
  }
}

class BibleFavoritesDatabase {
  static final BibleFavoritesDatabase instance = BibleFavoritesDatabase._init();
  static Database? _database;

  BibleFavoritesDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('bible_favorites.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE favorite_verses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL,
        book_name TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        text TEXT NOT NULL,
        translation_id TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Create index for faster queries
    await db.execute('''
      CREATE INDEX idx_book_chapter_verse 
      ON favorite_verses(book_id, chapter, verse)
    ''');
  }

  // Add verse to favorites
  Future<void> addFavoriteVerse({
    required int bookId,
    required String bookName,
    required int chapter,
    required int verse,
    required String text,
    required String translationId,
  }) async {
    final db = await instance.database;

    await db.insert('favorite_verses', {
      'book_id': bookId,
      'book_name': bookName,
      'chapter': chapter,
      'verse': verse,
      'text': text,
      'translation_id': translationId,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Remove verse from favorites
  Future<void> removeFavoriteVerse({
    required int bookId,
    required int chapter,
    required int verse,
  }) async {
    final db = await instance.database;

    await db.delete(
      'favorite_verses',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
    );
  }

  // Check if verse is favorited
  Future<bool> isFavorite({
    required int bookId,
    required int chapter,
    required int verse,
  }) async {
    final db = await instance.database;

    final result = await db.query(
      'favorite_verses',
      where: 'book_id = ? AND chapter = ? AND verse = ?',
      whereArgs: [bookId, chapter, verse],
      limit: 1,
    );

    return result.isNotEmpty;
  }

  // Get all favorite verses
  Future<List<Map<String, dynamic>>> getAllFavorites() async {
    final db = await instance.database;
    return await db.query('favorite_verses', orderBy: 'created_at DESC');
  }

  // Get favorite verses by book
  Future<List<Map<String, dynamic>>> getFavoritesByBook(int bookId) async {
    final db = await instance.database;
    return await db.query(
      'favorite_verses',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'chapter, verse',
    );
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}

// ------------------------- BIBLE SEARCH PAGE -------------------------

class BibleSearchPage extends StatefulWidget {
  const BibleSearchPage({super.key});

  @override
  State<BibleSearchPage> createState() => _BibleSearchPageState();
}

class _BibleSearchPageState extends State<BibleSearchPage> {
  final TextEditingController _searchController = TextEditingController();
  List<BibleSearchResult> searchResults = [];
  bool isSearching = false;
  String currentTranslationId = 'kjv';
  String currentTranslationName = 'KJV';

  @override
  void initState() {
    super.initState();
    _loadCurrentTranslation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentTranslation() async {
    try {
      final translationId = await BibleTranslationManager.instance
          .getCurrentTranslation();
      final translations = await BibleTranslationManager.instance
          .getAllTranslations();
      final currentTranslation = translations.firstWhere(
        (t) => t.id == translationId,
        orElse: () => translations.first,
      );

      setState(() {
        currentTranslationId = translationId;
        currentTranslationName = currentTranslation.abbreviation;
      });
    } catch (e) {
      setState(() {
        currentTranslationId = 'kjv';
        currentTranslationName = 'KJV';
      });
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        searchResults = [];
      });
      return;
    }

    setState(() {
      isSearching = true;
      searchResults = [];
    });

    try {
      final results = await BibleTranslationManager.instance
          .searchInTranslation(
            translationId: currentTranslationId,
            query: query,
            limit: 100,
          );

      final List<BibleSearchResult> searchResultsList = [];

      for (var result in results) {
        // Get book name from translation database
        final bookName = await BibleTranslationManager.instance.getBookName(
          currentTranslationId,
          result['book_id'] as int,
        );

        searchResultsList.add(
          BibleSearchResult(
            bookId: result['book_id'] as int,
            bookName: bookName ?? 'Unknown',
            chapter: result['chapter'] as int,
            verse: result['verse'] as int,
            text: result['text'] as String,
          ),
        );
      }

      setState(() {
        searchResults = searchResultsList;
        isSearching = false;
      });
    } catch (e) {
      setState(() {
        isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Search failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToVerse(BibleSearchResult result) {
    // Find the book from the standard Bible books list
    final book = _findBookById(result.bookId);

    if (book != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EnhancedBibleChapterPage(
            book: book,
            chapter: result.chapter,
            highlightVerse: result.verse,
          ),
        ),
      );
    }
  }

  SimpleBibleBook? _findBookById(int bookId) {
    const allBooks = [
      // Old Testament
      SimpleBibleBook(id: 1, name: "Genesis", testament: "Old", chapters: 50),
      SimpleBibleBook(id: 2, name: "Exodus", testament: "Old", chapters: 40),
      SimpleBibleBook(id: 3, name: "Leviticus", testament: "Old", chapters: 27),
      SimpleBibleBook(id: 4, name: "Numbers", testament: "Old", chapters: 36),
      SimpleBibleBook(
        id: 5,
        name: "Deuteronomy",
        testament: "Old",
        chapters: 34,
      ),
      SimpleBibleBook(id: 6, name: "Joshua", testament: "Old", chapters: 24),
      SimpleBibleBook(id: 7, name: "Judges", testament: "Old", chapters: 21),
      SimpleBibleBook(id: 8, name: "Ruth", testament: "Old", chapters: 4),
      SimpleBibleBook(id: 9, name: "1 Samuel", testament: "Old", chapters: 31),
      SimpleBibleBook(id: 10, name: "2 Samuel", testament: "Old", chapters: 24),
      SimpleBibleBook(id: 11, name: "1 Kings", testament: "Old", chapters: 22),
      SimpleBibleBook(id: 12, name: "2 Kings", testament: "Old", chapters: 25),
      SimpleBibleBook(
        id: 13,
        name: "1 Chronicles",
        testament: "Old",
        chapters: 29,
      ),
      SimpleBibleBook(
        id: 14,
        name: "2 Chronicles",
        testament: "Old",
        chapters: 36,
      ),
      SimpleBibleBook(id: 15, name: "Ezra", testament: "Old", chapters: 10),
      SimpleBibleBook(id: 16, name: "Nehemiah", testament: "Old", chapters: 13),
      SimpleBibleBook(id: 17, name: "Esther", testament: "Old", chapters: 10),
      SimpleBibleBook(id: 18, name: "Job", testament: "Old", chapters: 42),
      SimpleBibleBook(id: 19, name: "Psalms", testament: "Old", chapters: 150),
      SimpleBibleBook(id: 20, name: "Proverbs", testament: "Old", chapters: 31),
      SimpleBibleBook(
        id: 21,
        name: "Ecclesiastes",
        testament: "Old",
        chapters: 12,
      ),
      SimpleBibleBook(
        id: 22,
        name: "Song of Solomon",
        testament: "Old",
        chapters: 8,
      ),
      SimpleBibleBook(id: 23, name: "Isaiah", testament: "Old", chapters: 66),
      SimpleBibleBook(id: 24, name: "Jeremiah", testament: "Old", chapters: 52),
      SimpleBibleBook(
        id: 25,
        name: "Lamentations",
        testament: "Old",
        chapters: 5,
      ),
      SimpleBibleBook(id: 26, name: "Ezekiel", testament: "Old", chapters: 48),
      SimpleBibleBook(id: 27, name: "Daniel", testament: "Old", chapters: 12),
      SimpleBibleBook(id: 28, name: "Hosea", testament: "Old", chapters: 14),
      SimpleBibleBook(id: 29, name: "Joel", testament: "Old", chapters: 3),
      SimpleBibleBook(id: 30, name: "Amos", testament: "Old", chapters: 9),
      SimpleBibleBook(id: 31, name: "Obadiah", testament: "Old", chapters: 1),
      SimpleBibleBook(id: 32, name: "Jonah", testament: "Old", chapters: 4),
      SimpleBibleBook(id: 33, name: "Micah", testament: "Old", chapters: 7),
      SimpleBibleBook(id: 34, name: "Nahum", testament: "Old", chapters: 3),
      SimpleBibleBook(id: 35, name: "Habakkuk", testament: "Old", chapters: 3),
      SimpleBibleBook(id: 36, name: "Zephaniah", testament: "Old", chapters: 3),
      SimpleBibleBook(id: 37, name: "Haggai", testament: "Old", chapters: 2),
      SimpleBibleBook(
        id: 38,
        name: "Zechariah",
        testament: "Old",
        chapters: 14,
      ),
      SimpleBibleBook(id: 39, name: "Malachi", testament: "Old", chapters: 4),
      // New Testament
      SimpleBibleBook(id: 40, name: "Matthew", testament: "New", chapters: 28),
      SimpleBibleBook(id: 41, name: "Mark", testament: "New", chapters: 16),
      SimpleBibleBook(id: 42, name: "Luke", testament: "New", chapters: 24),
      SimpleBibleBook(id: 43, name: "John", testament: "New", chapters: 21),
      SimpleBibleBook(id: 44, name: "Acts", testament: "New", chapters: 28),
      SimpleBibleBook(id: 45, name: "Romans", testament: "New", chapters: 16),
      SimpleBibleBook(
        id: 46,
        name: "1 Corinthians",
        testament: "New",
        chapters: 16,
      ),
      SimpleBibleBook(
        id: 47,
        name: "2 Corinthians",
        testament: "New",
        chapters: 13,
      ),
      SimpleBibleBook(id: 48, name: "Galatians", testament: "New", chapters: 6),
      SimpleBibleBook(id: 49, name: "Ephesians", testament: "New", chapters: 6),
      SimpleBibleBook(
        id: 50,
        name: "Philippians",
        testament: "New",
        chapters: 4,
      ),
      SimpleBibleBook(
        id: 51,
        name: "Colossians",
        testament: "New",
        chapters: 4,
      ),
      SimpleBibleBook(
        id: 52,
        name: "1 Thessalonians",
        testament: "New",
        chapters: 5,
      ),
      SimpleBibleBook(
        id: 53,
        name: "2 Thessalonians",
        testament: "New",
        chapters: 3,
      ),
      SimpleBibleBook(id: 54, name: "1 Timothy", testament: "New", chapters: 6),
      SimpleBibleBook(id: 55, name: "2 Timothy", testament: "New", chapters: 4),
      SimpleBibleBook(id: 56, name: "Titus", testament: "New", chapters: 3),
      SimpleBibleBook(id: 57, name: "Philemon", testament: "New", chapters: 1),
      SimpleBibleBook(id: 58, name: "Hebrews", testament: "New", chapters: 13),
      SimpleBibleBook(id: 59, name: "James", testament: "New", chapters: 5),
      SimpleBibleBook(id: 60, name: "1 Peter", testament: "New", chapters: 5),
      SimpleBibleBook(id: 61, name: "2 Peter", testament: "New", chapters: 3),
      SimpleBibleBook(id: 62, name: "1 John", testament: "New", chapters: 5),
      SimpleBibleBook(id: 63, name: "2 John", testament: "New", chapters: 1),
      SimpleBibleBook(id: 64, name: "3 John", testament: "New", chapters: 1),
      SimpleBibleBook(id: 65, name: "Jude", testament: "New", chapters: 1),
      SimpleBibleBook(
        id: 66,
        name: "Revelation",
        testament: "New",
        chapters: 22,
      ),
    ];

    try {
      return allBooks.firstWhere((book) => book.id == bookId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🔍 Search Bible', style: TextStyle(fontSize: 18)),
            Text(
              currentTranslationName,
              style: const TextStyle(fontSize: 12, color: Colors.amber),
            ),
          ],
        ),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF2D2D2D),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search for words or phrases...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                searchResults = [];
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _performSearch,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      searchResults.isEmpty && !isSearching
                          ? 'Enter search term above'
                          : '${searchResults.length} result${searchResults.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _performSearch(_searchController.text),
                      icon: const Icon(Icons.search, size: 16),
                      label: const Text('Search'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search Results
          Expanded(
            child: isSearching
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.amber),
                        SizedBox(height: 16),
                        Text(
                          'Searching...',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  )
                : searchResults.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: searchResults.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final result = searchResults[index];
                      return _buildSearchResultCard(result);
                    },
                  ),
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
            const Icon(Icons.search, size: 80, color: Colors.white30),
            const SizedBox(height: 24),
            const Text(
              'Search the Bible',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Enter a word or phrase to find verses',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            const Card(
              color: Color(0xFF2D2D2D),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '💡 Search Tips:',
                      style: TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 12),
                    Text(
                      '• Search for single words: "faith", "love"\n'
                      '• Search for phrases: "for God so loved"\n'
                      '• Results are limited to 100 verses\n'
                      '• Tap any result to view the full chapter',
                      style: TextStyle(color: Colors.white70, height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResultCard(BibleSearchResult result) {
    return GestureDetector(
      onTap: () => _navigateToVerse(result),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Reference
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${result.bookName} ${result.chapter}:${result.verse}',
                    style: const TextStyle(
                      color: Colors.amber,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Verse Text with search term highlighted
            Text(
              result.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 8),

            // Action hint
            const Text(
              'Tap to view full chapter',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Bible Search Result Model
class BibleSearchResult {
  final int bookId;
  final String bookName;
  final int chapter;
  final int verse;
  final String text;

  BibleSearchResult({
    required this.bookId,
    required this.bookName,
    required this.chapter,
    required this.verse,
    required this.text,
  });
}

class DevotionalApp extends StatelessWidget {
  final bool isLoggedIn;

  const DevotionalApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // ✅ Add these three lines for Device Preview
      useInheritedMediaQuery: true,
      locale: DevicePreview.locale(context),
      builder: DevicePreview.appBuilder,

      debugShowCheckedModeBanner: false,
      title: 'NKC Devotional',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xff262626),
        primarySwatch: Colors.amber,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      ),
      // 🔑 Check login status and navigate accordingly
      home: isLoggedIn ? const DailyDevotionalApp() : const AuthPage(),
    );
  }
}

class DailyDevotionalApp extends StatefulWidget {
  const DailyDevotionalApp({super.key});

  @override
  State<DailyDevotionalApp> createState() => _DailyDevotionalAppState();
}

class MorePage extends StatelessWidget {
  const MorePage({super.key});

  Future _handleLogout(BuildContext context) async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Logout', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Logout', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 🔑 Clear login session
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('is_logged_in');
      await prefs.remove('user_name');
      await prefs.remove('user_id'); // ✅ Clear user ID

      if (context.mounted) {
        // Navigate back to auth page and clear all previous routes
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AuthPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      {
        "title": "Payment Plans",
        "icon": Icons.payment,
        "page": const EnhancedPaymentPlansPage(),
      },
      {
        "title": "Notifications",
        "icon": Icons.notifications,
        "page": const NotificationSettingsPage(),
      },
      {"title": "Logout", "icon": Icons.logout, "page": null},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text("SETTINGS")),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final item = items[index];
          return ListTile(
            leading: Icon(item["icon"] as IconData, color: Colors.amber),
            title: Text(item["title"] as String),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {
              if (item["title"] == "Logout") {
                _handleLogout(context);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => item["page"] as Widget),
                );
              }
            },
          );
        },
      ),
    );
  }
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _notificationsEnabled = false;
  TimeOfDay _notificationTime = const TimeOfDay(hour: 0, minute: 0);
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      setState(() => _isLoading = true);

      final isEnabled = await NotificationService.isNotificationsEnabled();
      final time = await NotificationService.getNotificationTime();

      setState(() {
        _notificationsEnabled = isEnabled;
        _notificationTime = time;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load settings: $e');
    }
  }

  Future<void> _toggleNotifications(bool enabled) async {
    try {
      setState(() => _notificationsEnabled = enabled);

      if (enabled) {
        await NotificationService.enableDailyNotifications(
          hour: _notificationTime.hour,
          minute: _notificationTime.minute,
        );
        _showSuccessSnackBar(
          'Daily notifications enabled at ${_notificationTime.formatted}',
        );
      } else {
        await NotificationService.disableDailyNotifications();
        _showSuccessSnackBar('Daily notifications disabled');
      }

      // ✅ NEW: Sync to cloud
      try {
        final prefs = await SharedPreferences.getInstance();
        final userId = prefs.getString('user_id');
        if (userId != null) {
          await CloudSyncManager.instance.syncNotificationSettingsToCloud(
            userId,
          );
          print('☁️ Notification settings synced to cloud');
        }
      } catch (e) {
        print('⚠️ Could not sync notification settings to cloud: $e');
      }
    } catch (e) {
      setState(() => _notificationsEnabled = !enabled);
      _showErrorSnackBar(
        'Failed to ${enabled ? 'enable' : 'disable'} notifications: $e',
      );
    }
  }

  // Update _pickNotificationTime:
  Future<void> _pickNotificationTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _notificationTime,
      helpText: 'Select daily notification time',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            timePickerTheme: TimePickerThemeData(
              backgroundColor: const Color(0xFF1E1E1E),
              hourMinuteTextColor: Colors.white,
              dayPeriodTextColor: Colors.white,
              dialHandColor: Colors.amber,
              dialBackgroundColor: Colors.grey[800],
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _notificationTime) {
      try {
        setState(() => _notificationTime = picked);

        await NotificationService.updateNotificationTime(
          picked.hour,
          picked.minute,
        );

        if (_notificationsEnabled) {
          _showSuccessSnackBar(
            'Notification time updated to ${picked.formatted}',
          );
        } else {
          _showInfoSnackBar(
            'Time saved. Enable notifications to receive daily reminders.',
          );
        }

        // ✅ NEW: Sync to cloud
        try {
          final prefs = await SharedPreferences.getInstance();
          final userId = prefs.getString('user_id');
          if (userId != null) {
            await CloudSyncManager.instance.syncNotificationSettingsToCloud(
              userId,
            );
            print('☁️ Notification time synced to cloud');
          }
        } catch (e) {
          print('⚠️ Could not sync notification time to cloud: $e');
        }
      } catch (e) {
        _showErrorSnackBar('Failed to update notification time: $e');
      }
    }
  }

  Future<void> _sendTestNotification() async {
    try {
      await NotificationService.sendTestNotification();
      _showSuccessSnackBar(
        'Test notification sent! Check your notification panel.',
      );
    } catch (e) {
      _showErrorSnackBar('Failed to send test notification: $e');
    }
  }

  Future<void> _resetToDefault() async {
    const defaultTime = TimeOfDay(hour: 0, minute: 0);

    try {
      setState(() => _notificationTime = defaultTime);
      await NotificationService.updateNotificationTime(0, 0);
      _showSuccessSnackBar('Reset to default time (12:00 AM)');
    } catch (e) {
      _showErrorSnackBar('Failed to reset time: $e');
    }
  }

  Future<void> _showPendingNotifications() async {
    try {
      final pending = await NotificationService.getPendingNotifications();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Pending Notifications',
            style: TextStyle(color: Colors.white),
          ),
          content: pending.isEmpty
              ? const Text(
                  'No pending notifications',
                  style: TextStyle(color: Colors.white70),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: pending
                      .map(
                        (notification) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            'ID: ${notification.id}\nTitle: ${notification.title}\nBody: ${notification.body}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close', style: TextStyle(color: Colors.amber)),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Failed to get pending notifications: $e');
    }
  }

  // ✅ NEW: Show debug information
  Future<void> _showDebugInfo() async {
    try {
      await NotificationService.printDebugInfo();
      _showSuccessSnackBar('Debug info printed to console');
    } catch (e) {
      _showErrorSnackBar('Failed to get debug info: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $message'),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $message'),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('ℹ️ $message'),
        backgroundColor: Colors.blue[600],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("🔔 Notification Settings"),
        backgroundColor: Colors.black,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              switch (value) {
                case 'reset':
                  _resetToDefault();
                  break;
                case 'debug':
                  _showDebugInfo();
                  break;
                case 'pending':
                  _showPendingNotifications();
                  break;
                case 'cancel_all':
                  NotificationService.cancelAllNotifications();
                  _showInfoSnackBar('All notifications cancelled');
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'reset',
                child: Text('Reset to 12 AM'),
              ),
              const PopupMenuItem(
                value: 'debug',
                child: Text('Show Debug Info'),
              ),
              const PopupMenuItem(
                value: 'pending',
                child: Text('Show Pending'),
              ),
              const PopupMenuItem(
                value: 'cancel_all',
                child: Text('Cancel All'),
              ),
            ],
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Enable/Disable Switch
                Card(
                  color: const Color(0xFF2D2D2D),
                  child: SwitchListTile(
                    title: const Text(
                      'Daily Notifications',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _notificationsEnabled
                          ? 'Receive daily devotional reminders'
                          : 'Notifications are disabled',
                      style: TextStyle(
                        color: _notificationsEnabled
                            ? Colors.green[300]
                            : Colors.red[300],
                      ),
                    ),
                    value: _notificationsEnabled,
                    onChanged: _toggleNotifications,
                    activeThumbColor: Colors.amber,
                    secondary: Icon(
                      _notificationsEnabled
                          ? Icons.notifications_active
                          : Icons.notifications_off,
                      color: _notificationsEnabled ? Colors.amber : Colors.grey,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Time Picker
                Card(
                  color: const Color(0xFF2D2D2D),
                  child: ListTile(
                    leading: const Icon(Icons.access_time, color: Colors.amber),
                    title: const Text(
                      'Notification Time',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _notificationTime.formatted,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.white54,
                    ),
                    onTap: _pickNotificationTime,
                  ),
                ),

                const SizedBox(height: 24),

                // Test Notification Button
                ElevatedButton.icon(
                  onPressed: _sendTestNotification,
                  icon: const Icon(Icons.send),
                  label: const Text('Send Test Notification'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),

                const SizedBox(height: 16),

                // ✅ NEW: Debug Button
                ElevatedButton.icon(
                  onPressed: _showDebugInfo,
                  icon: const Icon(Icons.bug_report),
                  label: const Text('Show Debug Info'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),

                const SizedBox(height: 16),

                // Info Card
                Card(
                  color: Colors.blue[900]?.withOpacity(0.3),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[300]),
                            const SizedBox(width: 8),
                            Text(
                              'How it works',
                              style: TextStyle(
                                color: Colors.blue[300],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Notifications are sent daily at your chosen time\n'
                          '• Default time is 12:00 AM (midnight)\n'
                          '• Make sure your device allows notifications\n'
                          '• Notifications work even when the app is closed\n'
                          '• Time is shown in your device\'s timezone (${DateTime.now().timeZoneName})',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),

                // Current Status
                if (_notificationsEnabled) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: Colors.green[900]?.withOpacity(0.3),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle, color: Colors.green[300]),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Daily reminders active at ${_notificationTime.formatted}',
                              style: TextStyle(
                                color: Colors.green[300],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class PaymentPlansPage extends StatelessWidget {
  const PaymentPlansPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text("Payment Plans")));
}

class LoginLogoutPage extends StatelessWidget {
  const LoginLogoutPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text("Login / Logout")));
}

class _DailyDevotionalAppState extends State<DailyDevotionalApp> {
  int _currentIndex = 0;
  bool _showBlurSheet = false;
  bool _hasShownWelcome = false;

  final List<Widget> _pages = [const DevotionalHomePage(), const MorePage()];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Check and request notification permissions if needed
    await _checkNotificationPermissions();

    // Set up default notifications if this is first launch
    await _setupDefaultNotifications();
  }

  Future<void> _checkNotificationPermissions() async {
    try {
      // Request notification permissions (especially important for Android 13+)
      if (await Permission.notification.isDenied) {
        final status = await Permission.notification.request();
        if (status.isDenied && mounted) {
          // Show dialog explaining why notifications are important
          _showPermissionDialog();
        }
      }
    } catch (e) {
      print('❌ Error checking notification permissions: $e');
    }
  }

  Future<void> _setupDefaultNotifications() async {
    try {
      final isEnabled = await NotificationService.isNotificationsEnabled();

      // If notifications haven't been configured yet, enable them by default at 12 AM
      if (!isEnabled) {
        final prefs = await SharedPreferences.getInstance();
        final hasSetupNotifications =
            prefs.getBool('has_setup_notifications') ?? false;

        if (!hasSetupNotifications) {
          // First launch - enable notifications at 12 AM by default
          await NotificationService.enableDailyNotifications(
            hour: 0,
            minute: 0,
          );
          await prefs.setBool('has_setup_notifications', true);

          print(
            '📱 Default notifications enabled at 12:00 AM for first launch',
          );

          // Show a brief welcome message about notifications if mounted
          if (mounted) {
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      "🔔 Daily devotional reminders enabled at 12:00 AM",
                    ),
                    duration: Duration(seconds: 3),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            });
          }
        }
      }
    } catch (e) {
      print('❌ Failed to setup default notifications: $e');
    }
  }

  void _showPermissionDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '🔔 Enable Notifications',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Get daily reminders for your devotional reading at 12:00 AM. You can customize the time in settings later.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Maybe Later',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Permission.notification.request();
              // Try to setup notifications again after permission granted
              await _setupDefaultNotifications();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Enable', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xff262626),
        primarySwatch: Colors.amber,
        fontFamily: 'Roboto',
        appBarTheme: const AppBarTheme(backgroundColor: Colors.black),
      ),
      home: Builder(
        // 👈 This gives us a context below MaterialApp
        builder: (innerContext) {
          // 👇 Safe to use ScaffoldMessenger here
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_hasShownWelcome) {
              _hasShownWelcome = true;
              ScaffoldMessenger.of(innerContext).showSnackBar(
                const SnackBar(
                  content: Text("👋 Welcome, God bless you!"),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          });

          return Container(
            color: const Color(0xff262626),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: Stack(
                children: [
                  _pages[_currentIndex],
                  if (_showBlurSheet)
                    BlurBottomSheet(
                      onDismiss: () => setState(() => _showBlurSheet = false),
                    ),
                ],
              ),
              floatingActionButton: FloatingActionButton(
                backgroundColor: Colors.amber,
                elevation: 0,
                shape: const CircleBorder(),
                onPressed: () {
                  setState(() {
                    _showBlurSheet = !_showBlurSheet;
                  });
                },
                child: const Icon(Icons.apps, color: Colors.black),
              ),
              floatingActionButtonLocation:
                  FloatingActionButtonLocation.centerDocked,
              bottomNavigationBar: BottomAppBar(
                shape: const CircularNotchedRectangle(),
                notchMargin: 11.0,
                color: Colors.black,
                elevation: 10,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.home,
                          color: _currentIndex == 0
                              ? Colors.amber
                              : Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _currentIndex = 0;
                          });
                        },
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.settings,
                          color: _currentIndex == 1
                              ? Colors.amber
                              : Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _currentIndex = 1;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class FeaturedDevotionalCard extends StatefulWidget {
  final String title;

  const FeaturedDevotionalCard({super.key, required this.title});

  @override
  State<FeaturedDevotionalCard> createState() => _FeaturedDevotionalCardState();
}

class _FeaturedDevotionalCardState extends State<FeaturedDevotionalCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _animation = Tween<double>(begin: 0, end: 2 * pi).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget buildAnimatedGlowBorder(Widget child) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        // Use full gradient cycle to interpolate glow color smoothly
        final List<Color> colors = [
          Colors.red,
          Colors.amber,
          Colors.yellow,
          Colors.red,
        ];
        final double t = (_animation.value / (2 * pi)) * (colors.length - 1);

        final int i = t.floor();
        final double localT = t - i;

        final Color startColor = colors[i % colors.length];
        final Color endColor = colors[(i + 1) % colors.length];
        final Color interpolatedGlowColor = Color.lerp(
          startColor,
          endColor,
          localT,
        )!;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: SweepGradient(
              colors: colors,
              startAngle: 0,
              endAngle: 2 * pi,
              transform: GradientRotation(_animation.value),
            ),
            boxShadow: [
              BoxShadow(
                color: interpolatedGlowColor.withOpacity(0.6),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(4), // thickness of glow border
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: interpolatedGlowColor.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    final String today = DateTime.now().toString().substring(0, 10);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          buildAnimatedGlowBorder(
            Container(
              height: screenHeight * 0.15,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          // child card widget
          Positioned(
            top: -20,
            left: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.amber,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withOpacity(0.5),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Text(
                today,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BlurBottomSheet extends StatefulWidget {
  final VoidCallback onDismiss;

  const BlurBottomSheet({super.key, required this.onDismiss});

  @override
  State<BlurBottomSheet> createState() => _BlurBottomSheetState();
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  List<Devotional> devotionals = [];
  bool isLoading = true;
  DateTime selectedDate = DateTime.now();
  PageController pageController = PageController();

  @override
  void initState() {
    super.initState();
    loadDevotionals();
  }

  Future<void> loadDevotionals() async {
    try {
      final result = await fetchDevotionals();
      setState(() {
        devotionals = result;
        isLoading = false;
      });
    } catch (e) {
      print("Error loading devotionals: $e");
      setState(() => isLoading = false);
    }
  }

  List<Devotional> getDevotionalsForMonth(DateTime month) {
    return devotionals.where((devotional) {
      return devotional.date.year == month.year &&
          devotional.date.month == month.month;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📅 Calendar"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : Column(
              children: [
                // Month Navigation
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: () {
                          setState(() {
                            selectedDate = DateTime(
                              selectedDate.year,
                              selectedDate.month - 1,
                            );
                          });
                        },
                        icon: const Icon(
                          Icons.chevron_left,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        DateFormat('MMMM yyyy').format(selectedDate),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() {
                            selectedDate = DateTime(
                              selectedDate.year,
                              selectedDate.month + 1,
                            );
                          });
                        },
                        icon: const Icon(
                          Icons.chevron_right,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                // Calendar Grid
                Expanded(child: _buildCalendarGrid()),
              ],
            ),
    );
  }

  Widget _buildCalendarGrid() {
    final monthDevotionals = getDevotionalsForMonth(selectedDate);
    final firstDayOfMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    final lastDayOfMonth = DateTime(
      selectedDate.year,
      selectedDate.month + 1,
      0,
    );
    final daysInMonth = lastDayOfMonth.day;
    final startingWeekday = firstDayOfMonth.weekday % 7;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Week headers
          Row(
            children: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                .map(
                  (day) => Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          // Calendar days
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 42, // 6 weeks * 7 days
              itemBuilder: (context, index) {
                final dayNumber = index - startingWeekday + 1;

                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return Container(); // Empty cell
                }

                final dayDate = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  dayNumber,
                );
                final hasDevotional = monthDevotionals.any(
                  (d) =>
                      d.date.day == dayNumber &&
                      d.date.month == selectedDate.month &&
                      d.date.year == selectedDate.year,
                );

                final devotionalForDay = monthDevotionals.firstWhere(
                  (d) =>
                      d.date.day == dayNumber &&
                      d.date.month == selectedDate.month &&
                      d.date.year == selectedDate.year,
                  orElse: () =>
                      Devotional(id: '', title: '', content: '', date: dayDate),
                );

                final isToday =
                    dayDate.day == DateTime.now().day &&
                    dayDate.month == DateTime.now().month &&
                    dayDate.year == DateTime.now().year;

                return GestureDetector(
                  onTap: hasDevotional
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EnhancedDevotionalDetailPage(
                                devotional: devotionalForDay,
                              ),
                            ),
                          );
                        }
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isToday
                          ? Colors.amber.withOpacity(0.3)
                          : hasDevotional
                          ? Colors.green.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: isToday
                          ? Border.all(color: Colors.amber, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dayNumber.toString(),
                            style: TextStyle(
                              color: hasDevotional
                                  ? Colors.white
                                  : Colors.white54,
                              fontWeight: hasDevotional
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          if (hasDevotional)
                            const Icon(
                              Icons.circle,
                              size: 6,
                              color: Colors.green,
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Legend
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegendItem(Colors.amber, "Today"),
                _buildLegendItem(Colors.green, "Has Devotional"),
                _buildLegendItem(Colors.grey, "No Devotional"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2),
            border: color == Colors.amber
                ? Border.all(color: color, width: 1)
                : null,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text("Favorites")));
}

class AddDevotionalPage extends StatefulWidget {
  const AddDevotionalPage({super.key});

  @override
  State<AddDevotionalPage> createState() => _AddDevotionalPageState();
}

class _AddDevotionalPageState extends State<AddDevotionalPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  DateTime _selectedDate = DateTime.now();

  Future<void> _submit() async {
    if (_formKey.currentState!.validate()) {
      await addDevotional(
        title: _titleController.text,
        content: _contentController.text,
        date: _selectedDate,
      );

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Devotional added!')));

      await Future.delayed(const Duration(milliseconds: 500));

      _titleController.clear();
      _contentController.clear();
      setState(() {
        _selectedDate = DateTime.now();
      });

      Navigator.pop(context);
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Devotional")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter a title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contentController,
                decoration: const InputDecoration(labelText: 'Content'),
                maxLines: 6,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter content' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _pickDate,
                    child: const Text('Pick Date'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _submit,
                child: const Text('Submit Devotional'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("❓ Help & FAQ"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHelpSection("Getting Started", [
            _buildFAQItem(
              "How do I read today's devotional?",
              "The featured devotional card on the home page shows today's message. "
                  "Tap on it to read the full content.",
            ),
            _buildFAQItem(
              "How do I enable notifications?",
              "Go to Settings > Notifications and toggle on 'Daily Notifications'. "
                  "You can also set your preferred time for reminders.",
            ),
          ]),

          _buildHelpSection("Navigation", [
            _buildFAQItem(
              "How do I access different features?",
              "Tap the floating action button (⊕) in the center of the bottom bar "
                  "to access Calendar, About, Add devotional, and Help pages.",
            ),
            _buildFAQItem(
              "How do I view past devotionals?",
              "Use the Archive section to browse all previous devotionals, "
                  "or use the Calendar to view devotionals by specific dates.",
            ),
          ]),

          _buildHelpSection("Downloads & Offline Reading", [
            _buildFAQItem(
              "How do I download devotionals?",
              "Open any devotional and tap the download icon in the top-right corner. "
                  "Downloaded devotionals can be accessed offline.",
            ),
            _buildFAQItem(
              "Where can I find my downloads?",
              "Tap on 'Downloads' from the home page categories to see all "
                  "your offline devotionals.",
            ),
          ]),

          _buildHelpSection("Search & Organization", [
            _buildFAQItem(
              "How do I search for specific devotionals?",
              "In the Archive page, use the search bar to find devotionals by title "
                  "or content, and use the date picker to filter by specific dates.",
            ),
            _buildFAQItem(
              "How do I sort devotionals?",
              "In the Archive page, tap the sort button to arrange devotionals "
                  "by date (newest first, oldest first) or alphabetically.",
            ),
          ]),

          _buildHelpSection("Notifications", [
            _buildFAQItem(
              "I'm not receiving notifications. What should I do?",
              "1. Check that notifications are enabled in the app settings\n"
                  "2. Ensure your device allows notifications for this app\n"
                  "3. Check your device's Do Not Disturb settings\n"
                  "4. Try sending a test notification from the settings page",
            ),
            _buildFAQItem(
              "How do I change the notification time?",
              "Go to Settings > Notifications and tap on 'Notification Time' "
                  "to select your preferred reminder time.",
            ),
          ]),

          _buildHelpSection("Troubleshooting", [
            _buildFAQItem(
              "The app is running slowly. What can I do?",
              "Try refreshing the content using the refresh button on the home page. "
                  "If issues persist, restart the app.",
            ),
            _buildFAQItem(
              "I can't connect to load new devotionals.",
              "Check your internet connection. The app shows your connection status "
                  "in the top-right corner of the home page.",
            ),
            _buildFAQItem(
              "How do I report a bug or issue?",
              "Please contact our support team at support@nkcdevotional.com "
                  "with details about the issue you're experiencing.",
            ),
          ]),

          const SizedBox(height: 24),

          // Contact Support Card
          Card(
            color: Colors.blue.withOpacity(0.1),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Icon(Icons.support_agent, color: Colors.blue, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    "Need More Help?",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Can't find what you're looking for? Our support team is here to help!",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      // You could implement email launching here
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Contact: support@nkcdevotional.com"),
                          backgroundColor: Colors.blue,
                        ),
                      );
                    },
                    icon: const Icon(Icons.email),
                    label: const Text("Contact Support"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpSection(String title, List<Widget> items) {
    return Card(
      color: const Color(0xFF2D2D2D),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 12),
            ...items,
          ],
        ),
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
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            answer,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ℹ️ About"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Logo/Header
            Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.menu_book,
                  size: 80,
                  color: Colors.amber,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // App Name and Version
            const Center(
              child: Column(
                children: [
                  Text(
                    "NKC DEVOTIONAL",
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Version 1.0.0",
                    style: TextStyle(fontSize: 16, color: Colors.white70),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Description
            _buildSection(
              "About This App",
              "NKC Devotional is your daily companion for spiritual growth and reflection. "
                  "Get inspired with daily devotional messages, manage your spiritual journey, "
                  "and stay connected with God through our carefully curated content.",
              Icons.info_outline,
            ),

            const SizedBox(height: 24),

            // Features
            _buildSection(
              "Features",
              "• Daily devotional messages\n"
                  "• Offline reading capability\n"
                  "• Search and archive functionality\n"
                  "• Calendar view of devotionals\n"
                  "• Daily notifications\n"
                  "• Download for offline access",
              Icons.star,
            ),

            const SizedBox(height: 24),

            // Contact/Support
            _buildSection(
              "Contact & Support",
              "For questions, feedback, or support, please reach out to us:\n\n"
                  "Email: support@nkcdevotional.com\n"
                  "Website: www.nkcdevotional.com\n\n"
                  "We'd love to hear from you!",
              Icons.contact_support,
            ),

            const SizedBox(height: 24),

            // Credits
            _buildSection(
              "Acknowledgments",
              "We thank God for His grace and guidance in creating this app. "
                  "Special thanks to all contributors and the community for their support.",
              Icons.favorite,
            ),

            const SizedBox(height: 32),

            // Copyright
            const Center(
              child: Text(
                "© 2024 NKC Devotional\nAll rights reserved",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content, IconData icon) {
    return Card(
      color: const Color(0xFF2D2D2D),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              content,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlurBottomSheetState extends State<BlurBottomSheet>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _scaleAnimation = Tween<double>(
      begin: 0.9,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  void _promptForPassword(BuildContext parentContext) {
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: parentContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text("Enter Admin Password"),
          content: TextField(
            controller: passwordController,
            obscureText: true,
            decoration: const InputDecoration(hintText: "Password"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                final enteredPassword = passwordController.text.trim();

                try {
                  final storedPassword = await fetchAdminPassword();
                  print("Entered: $enteredPassword");
                  print("Stored: $storedPassword");

                  Navigator.of(dialogContext).pop(); // close dialog
                  await Future.delayed(const Duration(milliseconds: 200));

                  if (enteredPassword == storedPassword) {
                    widget.onDismiss(); // close blur sheet
                    Navigator.of(parentContext).push(
                      MaterialPageRoute(
                        builder: (_) => const AddDevotionalPage(),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(parentContext).showSnackBar(
                      const SnackBar(content: Text("❌ Incorrect password")),
                    );
                  }
                } catch (e) {
                  Navigator.of(dialogContext).pop();
                  await Future.delayed(const Duration(milliseconds: 200));
                  ScaffoldMessenger.of(parentContext).showSnackBar(
                    const SnackBar(
                      content: Text("❗ Error validating password"),
                    ),
                  );
                }
              },
              child: const Text("Submit"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: _handleDismiss,
          child: FadeTransition(
            opacity: _opacityAnimation,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: Container(color: Colors.black.withOpacity(0.5)),
            ),
          ),
        ),
        Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: const Color(0xFF121212),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  children: [
                    _MenuItem(
                      icon: Icons.calendar_month,
                      label: "Calendar",
                      iconColor: Colors.deepOrange,
                      onTap: () {
                        widget.onDismiss();
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CalendarPage(),
                          ),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.info_outline,
                      label: "About",
                      iconColor: Colors.pink,
                      onTap: () {
                        widget.onDismiss();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AboutPage()),
                        );
                      },
                    ),
                    _MenuItem(
                      icon: Icons.add,
                      label: "Add",
                      iconColor: Colors.blue,
                      onTap: () {
                        _promptForPassword(
                          context,
                        ); // 👈 Trigger password check
                      },
                    ),
                    _MenuItem(
                      icon: Icons.help_outline,
                      label: "Help",
                      iconColor: Colors.green,
                      onTap: () {
                        widget.onDismiss();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const HelpPage()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 96,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: Colors.black87,
                child: Icon(icon, size: 28, color: iconColor),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DevotionalHomePage extends StatefulWidget {
  const DevotionalHomePage({super.key});

  @override
  State<DevotionalHomePage> createState() => _DevotionalHomePageState();
}

class _DevotionalHomePageState extends State<DevotionalHomePage>
    with TickerProviderStateMixin {
  List<Devotional> devotionals = [];
  bool isLoading = true;
  final bool _hasShownWelcome = false;
  bool _isOnline = true;
  String? userName; // NEW
  String? profileImagePath; // NEW

  Map<String, String> verseOfTheMonth = {'text': 'Loading...', 'reference': ''};
  String themeOfTheMonth = 'Loading...';
  bool isLoadingVerse = true;
  bool isLoadingTheme = true;

  late Stream<List<ConnectivityResult>> _connectivityStream =
      Connectivity().onConnectivityChanged;
  late AnimationController _pulseController;

  final List<Map<String, dynamic>> categories = const [
    {"title": "Archive", "icon": Icons.archive},
    {"title": "Favourites", "icon": Icons.favorite},
    {"title": "Bible", "icon": Icons.menu_book},
    {"title": "Downloads", "icon": Icons.download},
  ];

  // ✅ ADD THIS METHOD
  Future<void> _loadVerseOfTheMonth() async {
    final verse = await fetchVerseOfTheMonth();
    if (mounted) {
      setState(() {
        verseOfTheMonth = verse;
        isLoadingVerse = false;
      });
    }
  }

  // ✅ ADD THIS METHOD
  Future<void> _loadThemeOfTheMonth() async {
    final theme = await fetchThemeOfTheMonth();
    if (mounted) {
      setState(() {
        themeOfTheMonth = theme;
        isLoadingTheme = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    loadDevotionals();
    _loadUserData();

    _loadVerseOfTheMonth();
    _loadThemeOfTheMonth();

    Future<void> checkInternetConnectivity() async {
      try {
        // First check if connected to any network
        final connectivityResult = await Connectivity().checkConnectivity();

        if (connectivityResult == ConnectivityResult.none) {
          if (mounted) setState(() => _isOnline = false);
          return;
        }

        // Then verify actual internet access by making a lightweight request
        final result = await InternetAddress.lookup(
          'youtube.com',
        ).timeout(const Duration(seconds: 5));

        if (mounted) {
          setState(() {
            _isOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
          });
        }
      } catch (e) {
        // No internet access
        if (mounted) setState(() => _isOnline = false);
      }
    }

    // ✅ Initial check for actual internet connectivity
    checkInternetConnectivity();

    // ✅ Listen for future connectivity changes
    _connectivityStream = Connectivity().onConnectivityChanged;
    _connectivityStream.listen((result) {
      checkInternetConnectivity();
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  // mark point
  Future<void> _loadUserData() async {
    final name = await getLoggedInUserName();

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    String? imagePath;
    if (userId != null) {
      // ✅ Check for updates from cloud
      imagePath = await UserProfileManager.getProfileImage(userId);
    }

    setState(() {
      userName = name;
      profileImagePath = imagePath;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> loadDevotionals() async {
    try {
      final result = await fetchDevotionals();
      setState(() {
        devotionals = result;
        isLoading = false;
      });
    } catch (e) {
      print("Error fetching devotionals: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final todayDevotional = devotionals.firstWhere(
      (d) => DateFormat('yyyy-MM-dd').format(d.date) == todayStr,
      orElse: () => Devotional(
        id: '',
        title: 'No devotional for today.',
        content: '',
        date: DateTime.now(),
      ),
    );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            color: Colors.black,
            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 16.w),
            child: Row(
              children: [
                // NEW - User Profile Avatar
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const UserProfilePage(),
                      ),
                    ).then((_) {
                      // Reload user data when returning from profile page
                      _loadUserData();
                    });
                  },
                  child: Container(
                    width: 40.w,
                    height: 40.w,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.amber, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: profileImagePath != null
                          ? Image.file(
                              File(profileImagePath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return _buildDefaultAvatar();
                              },
                            )
                          : _buildDefaultAvatar(),
                    ),
                  ),
                ),

                SizedBox(width: 12.w),

                // ✅ UPDATED User Greeting
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'HELLO, ${(userName ?? 'USER').toUpperCase()}',
                        style: TextStyle(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Click to edit profile',
                        style: TextStyle(
                          fontSize: 10.sp,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),

                // Refresh Button
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Reload',
                  onPressed: () async {
                    setState(() => isLoading = true);
                    await loadDevotionals();
                  },
                ),

                // Connection Status
                ScaleTransition(
                  scale: Tween<double>(begin: 1.0, end: 1.3).animate(
                    CurvedAnimation(
                      parent: _pulseController,
                      curve: Curves.easeInOut,
                    ),
                  ),
                  child: Icon(
                    _isOnline ? Icons.wifi : Icons.wifi_off,
                    color: _isOnline ? Colors.greenAccent : Colors.redAccent,
                    size: 24.sp,
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Container(
              color: Colors.black12,
              child: SingleChildScrollView(
                padding: EdgeInsets.only(bottom: 20.h),
                child: Column(
                  children: [
                    SizedBox(height: 40.h),

                    GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EnhancedDevotionalDetailPage(
                              devotional: todayDevotional,
                            ),
                          ),
                        );
                      },
                      child: FeaturedDevotionalCard(
                        title: todayDevotional.title,
                      ),
                    ),

                    SizedBox(height: 30.h),

                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemCount: categories.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 2.2,
                          mainAxisSpacing: 16.h,
                          crossAxisSpacing: 16.w,
                        ),
                        itemBuilder: (context, index) {
                          final category = categories[index];

                          void handleTap() {
                            switch (category["title"]) {
                              case "Archive":
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const ArchivePage(),
                                  ),
                                );
                                break;
                              case "Favourites":
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const UnifiedFavoritesPage(),
                                  ),
                                );
                                break;
                              case "Bible":
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const EnhancedBiblePage(),
                                  ),
                                );
                                break;
                              case "Downloads":
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const DownloadsPage(),
                                  ),
                                );
                                break;
                            }
                          }

                          return GestureDetector(
                            onTap: handleTap,
                            child: Container(
                              padding: EdgeInsets.all(12.w),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12.r),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF292929),
                                    Color(0xFF1E1E1E),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 6.r,
                                    offset: Offset(0, 3.h),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    category["icon"],
                                    size: 30.sp,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 8.h),
                                  Text(
                                    category["title"],
                                    style: TextStyle(
                                      fontSize: 14.sp,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // Verse of the Month - Clickable
                    GestureDetector(
                      onTap: () {
                        if (!isLoadingVerse) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  VerseOfTheMonthPage(verse: verseOfTheMonth),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.amber.withOpacity(0.3),
                            ),
                          ),
                          child: InfoCardWidget(
                            title: 'Verse of the Month',
                            content: isLoadingVerse
                                ? 'Loading...'
                                : '${verseOfTheMonth['text']} - ${verseOfTheMonth['reference']}',
                            icon: Icons.menu_book,
                            isLoading: isLoadingVerse,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 10.h),

                    // Theme of the Month - Clickable
                    GestureDetector(
                      onTap: () {
                        if (!isLoadingTheme) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ThemeOfTheMonthPage(theme: themeOfTheMonth),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.w),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.amber.withOpacity(0.3),
                            ),
                          ),
                          child: InfoCardWidget(
                            title: 'Theme of the Month',
                            content: themeOfTheMonth,
                            icon: Icons.lightbulb_outline,
                            isLoading: isLoadingTheme,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: Colors.grey[800],
      child: const Icon(Icons.person, color: Colors.white54, size: 24),
    );
  }
}

class VerseOfTheDayWidget extends StatelessWidget {
  const VerseOfTheDayWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.menu_book, color: Colors.yellow[700]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Verse of the Day: "I can do all things through Christ..." - Philippians 4:13',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DevotionalDetailPage extends StatefulWidget {
  final Devotional devotional;

  const DevotionalDetailPage({super.key, required this.devotional});

  @override
  State<DevotionalDetailPage> createState() => _DevotionalDetailPageState();
}

class _DevotionalDetailPageState extends State<DevotionalDetailPage> {
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    _checkIfDownloaded();
  }

  Future<void> _checkIfDownloaded() async {
    final existing = await DownloadsDatabase.instance.getDevotionalById(
      widget.devotional.id,
    );
    setState(() {
      _isDownloaded = existing != null;
    });
  }

  Future<void> _downloadDevotional() async {
    if (widget.devotional.id.isEmpty ||
        widget.devotional.content.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ No devotional to download.")),
      );
      return;
    }

    await DownloadsDatabase.instance.insertDevotional(widget.devotional);
    setState(() {
      _isDownloaded = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("✅ Devotional downloaded for offline use")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.devotional.title),
        backgroundColor: Colors.black,
        actions: [
          if (widget.devotional.id.isNotEmpty &&
              widget.devotional.content.trim().isNotEmpty)
            IconButton(
              icon: Icon(
                _isDownloaded ? Icons.download_done : Icons.download,
                color: Colors.white,
              ),
              onPressed: _isDownloaded ? null : _downloadDevotional,
              tooltip: _isDownloaded ? 'Already downloaded' : 'Download',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.devotional.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.devotional.content,
              style: const TextStyle(fontSize: 16, color: Colors.white),
            ),
            const SizedBox(height: 20),
            Text(
              "Date: ${widget.devotional.date.toLocal().toString().split(' ')[0]}",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class InfoCardWidget extends StatelessWidget {
  final String title;
  final String content;
  final IconData icon;
  final bool isLoading; // ✅ NEW PARAMETER

  const InfoCardWidget({
    super.key,
    required this.title,
    required this.content,
    this.icon = Icons.menu_book,
    this.isLoading = false, // ✅ NEW PARAMETER WITH DEFAULT
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.yellow[700]),
          const SizedBox(width: 12),
          Expanded(
            child:
                isLoading // ✅ SHOW LOADING INDICATOR
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      color: Colors.amber,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    '$title: "$content"',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key});

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  List<Devotional> archiveDevotionals = [];
  List<Devotional> filteredDevotionals = [];
  bool isLoading = true;
  String searchQuery = '';
  DateTime? selectedDate;
  String sortOrder = 'newest'; // 'newest', 'oldest', 'alphabetical'

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadArchiveDevotionals();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      searchQuery = _searchController.text;
      _applyFiltersAndSort();
    });
  }

  Future<void> loadArchiveDevotionals() async {
    try {
      final result = await fetchDevotionals();
      setState(() {
        archiveDevotionals = result;
        filteredDevotionals = result;
        isLoading = false;
      });
      _applyFiltersAndSort();
    } catch (e) {
      print("❌ Error loading archive: $e");
      setState(() => isLoading = false);
    }
  }

  void _applyFiltersAndSort() {
    List<Devotional> filtered = List.from(archiveDevotionals);

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((devotional) {
        return devotional.title.toLowerCase().contains(
              searchQuery.toLowerCase(),
            ) ||
            devotional.content.toLowerCase().contains(
              searchQuery.toLowerCase(),
            );
      }).toList();
    }

    // Apply date filter
    if (selectedDate != null) {
      filtered = filtered.where((devotional) {
        return devotional.date.year == selectedDate!.year &&
            devotional.date.month == selectedDate!.month &&
            devotional.date.day == selectedDate!.day;
      }).toList();
    }

    // Apply sorting
    switch (sortOrder) {
      case 'newest':
        filtered.sort((a, b) => b.date.compareTo(a.date));
        break;
      case 'oldest':
        filtered.sort((a, b) => a.date.compareTo(b.date));
        break;
      case 'alphabetical':
        filtered.sort((a, b) => a.title.compareTo(b.title));
        break;
    }

    setState(() {
      filteredDevotionals = filtered;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.amber,
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        selectedDate = picked;
        _applyFiltersAndSort();
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      selectedDate = null;
      _applyFiltersAndSort();
    });
  }

  void _showSortOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Sort By',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(
                Icons.arrow_downward,
                color: sortOrder == 'newest' ? Colors.amber : Colors.white70,
              ),
              title: const Text(
                'Newest First',
                style: TextStyle(color: Colors.white),
              ),
              trailing: sortOrder == 'newest'
                  ? const Icon(Icons.check, color: Colors.amber)
                  : null,
              onTap: () {
                setState(() {
                  sortOrder = 'newest';
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.arrow_upward,
                color: sortOrder == 'oldest' ? Colors.amber : Colors.white70,
              ),
              title: const Text(
                'Oldest First',
                style: TextStyle(color: Colors.white),
              ),
              trailing: sortOrder == 'oldest'
                  ? const Icon(Icons.check, color: Colors.amber)
                  : null,
              onTap: () {
                setState(() {
                  sortOrder = 'oldest';
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(
                Icons.sort_by_alpha,
                color: sortOrder == 'alphabetical'
                    ? Colors.amber
                    : Colors.white70,
              ),
              title: const Text(
                'Alphabetical',
                style: TextStyle(color: Colors.white),
              ),
              trailing: sortOrder == 'alphabetical'
                  ? const Icon(Icons.check, color: Colors.amber)
                  : null,
              onTap: () {
                setState(() {
                  sortOrder = 'alphabetical';
                  _applyFiltersAndSort();
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📚 Devotional Archive"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
            tooltip: 'Sort Options',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              setState(() => isLoading = true);
              await loadArchiveDevotionals();
            },
            tooltip: 'Refresh',
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: Column(
        children: [
          // Search and Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF2D2D2D),
            child: Column(
              children: [
                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search devotionals...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),

                // Date Filter Row
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                            border: selectedDate != null
                                ? Border.all(color: Colors.amber, width: 1)
                                : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                color: selectedDate != null
                                    ? Colors.amber
                                    : Colors.white54,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                selectedDate != null
                                    ? DateFormat(
                                        'MMM dd, yyyy',
                                      ).format(selectedDate!)
                                    : 'Filter by date',
                                style: TextStyle(
                                  color: selectedDate != null
                                      ? Colors.amber
                                      : Colors.white54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (selectedDate != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _clearDateFilter,
                        icon: const Icon(Icons.clear, color: Colors.amber),
                        tooltip: 'Clear date filter',
                      ),
                    ],
                  ],
                ),

                // Results Count and Sort Info
                if (!isLoading) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${filteredDevotionals.length} result${filteredDevotionals.length != 1 ? 's' : ''}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'Sorted by: ${_getSortDisplayName()}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Results List
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.amber),
                  )
                : filteredDevotionals.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemCount: filteredDevotionals.length,
                    itemBuilder: (context, index) {
                      final devotional = filteredDevotionals[index];
                      return _buildDevotionalCard(devotional);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            searchQuery.isNotEmpty || selectedDate != null
                ? Icons.search_off
                : Icons.auto_stories,
            size: 64,
            color: Colors.white38,
          ),
          const SizedBox(height: 16),
          Text(
            searchQuery.isNotEmpty || selectedDate != null
                ? 'No devotionals found'
                : 'No devotionals available',
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          if (searchQuery.isNotEmpty || selectedDate != null)
            Text(
              'Try adjusting your search or date filter',
              style: const TextStyle(color: Colors.white38, fontSize: 14),
            ),
        ],
      ),
    );
  }

  Widget _buildDevotionalCard(Devotional devotional) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                EnhancedDevotionalDetailPage(devotional: devotional),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and actions row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    DateFormat('MMM dd, yyyy').format(devotional.date),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.amber,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                // Highlight search matches
                if (searchQuery.isNotEmpty && _isToday(devotional.date))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'TODAY',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Title with search highlighting
            Text(
              devotional.title,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),

            // Content preview with search highlighting
            Text(
              devotional.content.length > 150
                  ? "${devotional.content.substring(0, 150)}..."
                  : devotional.content,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white70,
                height: 1.4,
              ),
            ),

            const SizedBox(height: 12),

            // Read more indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${devotional.content.split(' ').length} words',
                  style: const TextStyle(fontSize: 12, color: Colors.white38),
                ),
                const Row(
                  children: [
                    Text(
                      'Read more',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(width: 4),
                    Icon(Icons.arrow_forward, size: 14, color: Colors.amber),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getSortDisplayName() {
    switch (sortOrder) {
      case 'newest':
        return 'Newest First';
      case 'oldest':
        return 'Oldest First';
      case 'alphabetical':
        return 'Alphabetical';
      default:
        return 'Newest First';
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});

  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage> {
  List<Devotional> _downloads = [];

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    final downloaded = await DownloadsDatabase.instance.getAllDevotionals();
    setState(() {
      _downloads = downloaded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("📥 Downloads"),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: _downloads.isEmpty
          ? const Center(
              child: Text(
                "No downloads yet",
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              itemCount: _downloads.length,
              itemBuilder: (context, index) {
                final devotional = _downloads[index];
                return ListTile(
                  title: Text(
                    devotional.title,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    devotional.date.toLocal().toString().split(' ')[0],
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.white54,
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => EnhancedDevotionalDetailPage(
                          devotional: devotional,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class EnhancedBiblePage extends StatefulWidget {
  const EnhancedBiblePage({super.key});

  @override
  State<EnhancedBiblePage> createState() => _EnhancedBiblePageState();
}

class _EnhancedBiblePageState extends State<EnhancedBiblePage> {
  String selectedTestament = 'All';
  final TextEditingController _searchController = TextEditingController();
  String searchQuery = '';

  final List<SimpleBibleBook> _allBooks = const [
    // Old Testament
    SimpleBibleBook(id: 1, name: "Genesis", testament: "Old", chapters: 50),
    SimpleBibleBook(id: 2, name: "Exodus", testament: "Old", chapters: 40),
    SimpleBibleBook(id: 3, name: "Leviticus", testament: "Old", chapters: 27),
    SimpleBibleBook(id: 4, name: "Numbers", testament: "Old", chapters: 36),
    SimpleBibleBook(id: 5, name: "Deuteronomy", testament: "Old", chapters: 34),
    SimpleBibleBook(id: 6, name: "Joshua", testament: "Old", chapters: 24),
    SimpleBibleBook(id: 7, name: "Judges", testament: "Old", chapters: 21),
    SimpleBibleBook(id: 8, name: "Ruth", testament: "Old", chapters: 4),
    SimpleBibleBook(id: 9, name: "1 Samuel", testament: "Old", chapters: 31),
    SimpleBibleBook(id: 10, name: "2 Samuel", testament: "Old", chapters: 24),
    SimpleBibleBook(id: 11, name: "1 Kings", testament: "Old", chapters: 22),
    SimpleBibleBook(id: 12, name: "2 Kings", testament: "Old", chapters: 25),
    SimpleBibleBook(
      id: 13,
      name: "1 Chronicles",
      testament: "Old",
      chapters: 29,
    ),
    SimpleBibleBook(
      id: 14,
      name: "2 Chronicles",
      testament: "Old",
      chapters: 36,
    ),
    SimpleBibleBook(id: 15, name: "Ezra", testament: "Old", chapters: 10),
    SimpleBibleBook(id: 16, name: "Nehemiah", testament: "Old", chapters: 13),
    SimpleBibleBook(id: 17, name: "Esther", testament: "Old", chapters: 10),
    SimpleBibleBook(id: 18, name: "Job", testament: "Old", chapters: 42),
    SimpleBibleBook(id: 19, name: "Psalms", testament: "Old", chapters: 150),
    SimpleBibleBook(id: 20, name: "Proverbs", testament: "Old", chapters: 31),
    SimpleBibleBook(
      id: 21,
      name: "Ecclesiastes",
      testament: "Old",
      chapters: 12,
    ),
    SimpleBibleBook(
      id: 22,
      name: "Song of Solomon",
      testament: "Old",
      chapters: 8,
    ),
    SimpleBibleBook(id: 23, name: "Isaiah", testament: "Old", chapters: 66),
    SimpleBibleBook(id: 24, name: "Jeremiah", testament: "Old", chapters: 52),
    SimpleBibleBook(
      id: 25,
      name: "Lamentations",
      testament: "Old",
      chapters: 5,
    ),
    SimpleBibleBook(id: 26, name: "Ezekiel", testament: "Old", chapters: 48),
    SimpleBibleBook(id: 27, name: "Daniel", testament: "Old", chapters: 12),
    SimpleBibleBook(id: 28, name: "Hosea", testament: "Old", chapters: 14),
    SimpleBibleBook(id: 29, name: "Joel", testament: "Old", chapters: 3),
    SimpleBibleBook(id: 30, name: "Amos", testament: "Old", chapters: 9),
    SimpleBibleBook(id: 31, name: "Obadiah", testament: "Old", chapters: 1),
    SimpleBibleBook(id: 32, name: "Jonah", testament: "Old", chapters: 4),
    SimpleBibleBook(id: 33, name: "Micah", testament: "Old", chapters: 7),
    SimpleBibleBook(id: 34, name: "Nahum", testament: "Old", chapters: 3),
    SimpleBibleBook(id: 35, name: "Habakkuk", testament: "Old", chapters: 3),
    SimpleBibleBook(id: 36, name: "Zephaniah", testament: "Old", chapters: 3),
    SimpleBibleBook(id: 37, name: "Haggai", testament: "Old", chapters: 2),
    SimpleBibleBook(id: 38, name: "Zechariah", testament: "Old", chapters: 14),
    SimpleBibleBook(id: 39, name: "Malachi", testament: "Old", chapters: 4),
    // New Testament
    SimpleBibleBook(id: 40, name: "Matthew", testament: "New", chapters: 28),
    SimpleBibleBook(id: 41, name: "Mark", testament: "New", chapters: 16),
    SimpleBibleBook(id: 42, name: "Luke", testament: "New", chapters: 24),
    SimpleBibleBook(id: 43, name: "John", testament: "New", chapters: 21),
    SimpleBibleBook(id: 44, name: "Acts", testament: "New", chapters: 28),
    SimpleBibleBook(id: 45, name: "Romans", testament: "New", chapters: 16),
    SimpleBibleBook(
      id: 46,
      name: "1 Corinthians",
      testament: "New",
      chapters: 16,
    ),
    SimpleBibleBook(
      id: 47,
      name: "2 Corinthians",
      testament: "New",
      chapters: 13,
    ),
    SimpleBibleBook(id: 48, name: "Galatians", testament: "New", chapters: 6),
    SimpleBibleBook(id: 49, name: "Ephesians", testament: "New", chapters: 6),
    SimpleBibleBook(id: 50, name: "Philippians", testament: "New", chapters: 4),
    SimpleBibleBook(id: 51, name: "Colossians", testament: "New", chapters: 4),
    SimpleBibleBook(
      id: 52,
      name: "1 Thessalonians",
      testament: "New",
      chapters: 5,
    ),
    SimpleBibleBook(
      id: 53,
      name: "2 Thessalonians",
      testament: "New",
      chapters: 3,
    ),
    SimpleBibleBook(id: 54, name: "1 Timothy", testament: "New", chapters: 6),
    SimpleBibleBook(id: 55, name: "2 Timothy", testament: "New", chapters: 4),
    SimpleBibleBook(id: 56, name: "Titus", testament: "New", chapters: 3),
    SimpleBibleBook(id: 57, name: "Philemon", testament: "New", chapters: 1),
    SimpleBibleBook(id: 58, name: "Hebrews", testament: "New", chapters: 13),
    SimpleBibleBook(id: 59, name: "James", testament: "New", chapters: 5),
    SimpleBibleBook(id: 60, name: "1 Peter", testament: "New", chapters: 5),
    SimpleBibleBook(id: 61, name: "2 Peter", testament: "New", chapters: 3),
    SimpleBibleBook(id: 62, name: "1 John", testament: "New", chapters: 5),
    SimpleBibleBook(id: 63, name: "2 John", testament: "New", chapters: 1),
    SimpleBibleBook(id: 64, name: "3 John", testament: "New", chapters: 1),
    SimpleBibleBook(id: 65, name: "Jude", testament: "New", chapters: 1),
    SimpleBibleBook(id: 66, name: "Revelation", testament: "New", chapters: 22),
  ];

  List<SimpleBibleBook> get filteredBooks {
    var books = _allBooks;

    if (selectedTestament != 'All') {
      books = books
          .where((book) => book.testament == selectedTestament)
          .toList();
    }

    if (searchQuery.isNotEmpty) {
      books = books
          .where(
            (book) =>
                book.name.toLowerCase().contains(searchQuery.toLowerCase()),
          )
          .toList();
    }

    return books;
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final books = filteredBooks;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Bible"),
        backgroundColor: Colors.black,
        actions: [
          // ✅ CHANGED: Search button with label
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BibleSearchPage()),
              );
            },
            icon: const Icon(Icons.search, color: Colors.white, size: 20),
            label: const Text(
              'Words',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),

          const SizedBox(width: 4), // ✅ Small spacing
          // ✅ CHANGED: Translations button with label
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const BibleTranslationsDownloadPage(),
                ),
              );
            },
            icon: const Icon(Icons.download, color: Colors.white, size: 20),
            label: const Text(
              'Translations',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),

          const SizedBox(width: 8), // ✅ Padding from edge
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF2D2D2D),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search books...',
                    hintStyle: const TextStyle(color: Colors.white54),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    suffixIcon: searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: Colors.white54,
                            ),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF1E1E1E),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(child: _buildFilterChip('All')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildFilterChip('Old')),
                    const SizedBox(width: 8),
                    Expanded(child: _buildFilterChip('New')),
                  ],
                ),

                const SizedBox(height: 12),
                Text(
                  '${books.length} book${books.length != 1 ? 's' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),

          Expanded(
            child: books.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.search_off,
                          size: 64,
                          color: Colors.white38,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No books found',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: books.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return _buildBookCard(book);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String testament) {
    final isSelected = selectedTestament == testament;

    return GestureDetector(
      onTap: () {
        setState(() {
          selectedTestament = testament;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.amber : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white24,
            width: 1,
          ),
        ),
        child: Text(
          testament == 'All' ? 'All Books' : '$testament Testament',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildBookCard(SimpleBibleBook book) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SimpleBibleBookPage(book: book)),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: book.testament == "Old"
                ? Colors.blue.withOpacity(0.3)
                : Colors.green.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: book.testament == "Old"
                    ? Colors.blue[700]
                    : Colors.green[700],
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  book.id.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${book.testament} Testament • ${book.chapters} chapter${book.chapters != 1 ? 's' : ''}',
                    style: TextStyle(
                      color: book.testament == "Old"
                          ? Colors.blue[300]
                          : Colors.green[300],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.chevron_right, color: Colors.white54),
          ],
        ),
      ),
    );
  }
}

// Simple Bible Book Model
class SimpleBibleBook {
  final int id;
  final String name;
  final String testament;
  final int chapters;

  const SimpleBibleBook({
    required this.id,
    required this.name,
    required this.testament,
    required this.chapters,
  });
}

// Bible Verse Model
class BibleVerse {
  final int id;
  final int bookId;
  final int chapter;
  final int verse;
  final String text;

  const BibleVerse({
    required this.id,
    required this.bookId,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'book_id': bookId,
      'chapter': chapter,
      'verse': verse,
      'text': text,
    };
  }

  factory BibleVerse.fromMap(Map<String, dynamic> map) {
    return BibleVerse(
      id: map['id'] as int,
      bookId: map['book_id'] as int,
      chapter: map['chapter'] as int,
      verse: map['verse'] as int,
      text: map['text'] as String,
    );
  }
}

// Simple Bible Database Service
class SimpleBibleDatabase {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, 'simple_bible.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE verses (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            book_id INTEGER NOT NULL,
            chapter INTEGER NOT NULL,
            verse INTEGER NOT NULL,
            text TEXT NOT NULL
          )
        ''');

        // Create index for faster queries
        await db.execute('''
          CREATE INDEX idx_book_chapter ON verses(book_id, chapter)
        ''');
      },
    );
  }

  // Insert a verse
  static Future<int> insertVerse(BibleVerse verse) async {
    final db = await database;
    return await db.insert('verses', verse.toMap());
  }

  // Insert multiple verses
  static Future<void> insertVerses(List<BibleVerse> verses) async {
    final db = await database;
    final batch = db.batch();
    for (var verse in verses) {
      batch.insert('verses', verse.toMap());
    }
    await batch.commit(noResult: true);
  }

  // Get all verses for a specific chapter
  static Future<List<BibleVerse>> getChapterVerses(
    int bookId,
    int chapter,
  ) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'verses',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
      orderBy: 'verse ASC',
    );
    return List.generate(maps.length, (i) => BibleVerse.fromMap(maps[i]));
  }

  // Search verses by text
  static Future<List<BibleVerse>> searchVerses(String query) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'verses',
      where: 'text LIKE ?',
      whereArgs: ['%$query%'],
      limit: 100,
    );
    return List.generate(maps.length, (i) => BibleVerse.fromMap(maps[i]));
  }

  // Check if verses exist for a chapter
  static Future<bool> hasChapterVerses(int bookId, int chapter) async {
    final db = await database;
    final result = await db.query(
      'verses',
      where: 'book_id = ? AND chapter = ?',
      whereArgs: [bookId, chapter],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // Delete all verses (for testing)
  static Future<void> deleteAllVerses() async {
    final db = await database;
    await db.delete('verses');
  }

  // Add sample Bible data for testing
  static Future<void> addSampleData() async {
    // Check if data already exists
    final hasData = await hasChapterVerses(1, 1);
    if (hasData) return;

    // Sample verses from Genesis Chapter 1
    final sampleVerses = [
      BibleVerse(
        id: 1,
        bookId: 1,
        chapter: 1,
        verse: 1,
        text: "In the beginning God created the heaven and the earth.",
      ),
      BibleVerse(
        id: 2,
        bookId: 1,
        chapter: 1,
        verse: 2,
        text:
            "And the earth was without form, and void; and darkness was upon the face of the deep. And the Spirit of God moved upon the face of the waters.",
      ),
      BibleVerse(
        id: 3,
        bookId: 1,
        chapter: 1,
        verse: 3,
        text: "And God said, Let there be light: and there was light.",
      ),
      BibleVerse(
        id: 4,
        bookId: 1,
        chapter: 1,
        verse: 4,
        text:
            "And God saw the light, that it was good: and God divided the light from the darkness.",
      ),
      BibleVerse(
        id: 5,
        bookId: 1,
        chapter: 1,
        verse: 5,
        text:
            "And God called the light Day, and the darkness he called Night. And the evening and the morning were the first day.",
      ),
      BibleVerse(
        id: 6,
        bookId: 1,
        chapter: 1,
        verse: 6,
        text:
            "And God said, Let there be a firmament in the midst of the waters, and let it divide the waters from the waters.",
      ),
      BibleVerse(
        id: 7,
        bookId: 1,
        chapter: 1,
        verse: 7,
        text:
            "And God made the firmament, and divided the waters which were under the firmament from the waters which were above the firmament: and it was so.",
      ),
      BibleVerse(
        id: 8,
        bookId: 1,
        chapter: 1,
        verse: 8,
        text:
            "And God called the firmament Heaven. And the evening and the morning were the second day.",
      ),
      BibleVerse(
        id: 9,
        bookId: 1,
        chapter: 1,
        verse: 9,
        text:
            "And God said, Let the waters under the heaven be gathered together unto one place, and let the dry land appear: and it was so.",
      ),
      BibleVerse(
        id: 10,
        bookId: 1,
        chapter: 1,
        verse: 10,
        text:
            "And God called the dry land Earth; and the gathering together of the waters called he Seas: and God saw that it was good.",
      ),
      BibleVerse(
        id: 11,
        bookId: 1,
        chapter: 1,
        verse: 11,
        text:
            "And God said, Let the earth bring forth grass, the herb yielding seed, and the fruit tree yielding fruit after his kind, whose seed is in itself, upon the earth: and it was so.",
      ),
      BibleVerse(
        id: 12,
        bookId: 1,
        chapter: 1,
        verse: 12,
        text:
            "And the earth brought forth grass, and herb yielding seed after his kind, and the tree yielding fruit, whose seed was in itself, after his kind: and God saw that it was good.",
      ),
      BibleVerse(
        id: 13,
        bookId: 1,
        chapter: 1,
        verse: 13,
        text: "And the evening and the morning were the third day.",
      ),
      BibleVerse(
        id: 14,
        bookId: 1,
        chapter: 1,
        verse: 14,
        text:
            "And God said, Let there be lights in the firmament of the heaven to divide the day from the night; and let them be for signs, and for seasons, and for days, and years:",
      ),
      BibleVerse(
        id: 15,
        bookId: 1,
        chapter: 1,
        verse: 15,
        text:
            "And let them be for lights in the firmament of the heaven to give light upon the earth: and it was so.",
      ),
      BibleVerse(
        id: 16,
        bookId: 1,
        chapter: 1,
        verse: 16,
        text:
            "And God made two great lights; the greater light to rule the day, and the lesser light to rule the night: he made the stars also.",
      ),
      BibleVerse(
        id: 17,
        bookId: 1,
        chapter: 1,
        verse: 17,
        text:
            "And God set them in the firmament of the heaven to give light upon the earth,",
      ),
      BibleVerse(
        id: 18,
        bookId: 1,
        chapter: 1,
        verse: 18,
        text:
            "And to rule over the day and over the night, and to divide the light from the darkness: and God saw that it was good.",
      ),
      BibleVerse(
        id: 19,
        bookId: 1,
        chapter: 1,
        verse: 19,
        text: "And the evening and the morning were the fourth day.",
      ),
      BibleVerse(
        id: 20,
        bookId: 1,
        chapter: 1,
        verse: 20,
        text:
            "And God said, Let the waters bring forth abundantly the moving creature that hath life, and fowl that may fly above the earth in the open firmament of heaven.",
      ),
      BibleVerse(
        id: 21,
        bookId: 1,
        chapter: 1,
        verse: 21,
        text:
            "And God created great whales, and every living creature that moveth, which the waters brought forth abundantly, after their kind, and every winged fowl after his kind: and God saw that it was good.",
      ),
      BibleVerse(
        id: 22,
        bookId: 1,
        chapter: 1,
        verse: 22,
        text:
            "And God blessed them, saying, Be fruitful, and multiply, and fill the waters in the seas, and let fowl multiply in the earth.",
      ),
      BibleVerse(
        id: 23,
        bookId: 1,
        chapter: 1,
        verse: 23,
        text: "And the evening and the morning were the fifth day.",
      ),
      BibleVerse(
        id: 24,
        bookId: 1,
        chapter: 1,
        verse: 24,
        text:
            "And God said, Let the earth bring forth the living creature after his kind, cattle, and creeping thing, and beast of the earth after his kind: and it was so.",
      ),
      BibleVerse(
        id: 25,
        bookId: 1,
        chapter: 1,
        verse: 25,
        text:
            "And God made the beast of the earth after his kind, and cattle after their kind, and every thing that creepeth upon the earth after his kind: and God saw that it was good.",
      ),
      BibleVerse(
        id: 26,
        bookId: 1,
        chapter: 1,
        verse: 26,
        text:
            "And God said, Let us make man in our image, after our likeness: and let them have dominion over the fish of the sea, and over the fowl of the air, and over the cattle, and over all the earth, and over every creeping thing that creepeth upon the earth.",
      ),
      BibleVerse(
        id: 27,
        bookId: 1,
        chapter: 1,
        verse: 27,
        text:
            "So God created man in his own image, in the image of God created he him; male and female created he them.",
      ),
      BibleVerse(
        id: 28,
        bookId: 1,
        chapter: 1,
        verse: 28,
        text:
            "And God blessed them, and God said unto them, Be fruitful, and multiply, and replenish the earth, and subdue it: and have dominion over the fish of the sea, and over the fowl of the air, and over every living thing that moveth upon the earth.",
      ),
      BibleVerse(
        id: 29,
        bookId: 1,
        chapter: 1,
        verse: 29,
        text:
            "And God said, Behold, I have given you every herb bearing seed, which is upon the face of all the earth, and every tree, in the which is the fruit of a tree yielding seed; to you it shall be for meat.",
      ),
      BibleVerse(
        id: 30,
        bookId: 1,
        chapter: 1,
        verse: 30,
        text:
            "And to every beast of the earth, and to every fowl of the air, and to every thing that creepeth upon the earth, wherein there is life, I have given every green herb for meat: and it was so.",
      ),
      BibleVerse(
        id: 31,
        bookId: 1,
        chapter: 1,
        verse: 31,
        text:
            "And God saw every thing that he had made, and, behold, it was very good. And the evening and the morning were the sixth day.",
      ),
    ];

    await insertVerses(sampleVerses);
  }
}

// ------------------------- BIBLE TRANSLATION SYSTEM -------------------------

// Bible Translation Model
class BibleTranslation {
  final String id;
  final String name;
  final String abbreviation;
  final String downloadUrl;
  final int sizeInMB;
  final String description;
  bool isDownloaded;
  bool isDownloading;
  double downloadProgress;

  BibleTranslation({
    required this.id,
    required this.name,
    required this.abbreviation,
    required this.downloadUrl,
    required this.sizeInMB,
    required this.description,
    this.isDownloaded = false,
    this.isDownloading = false,
    this.downloadProgress = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'abbreviation': abbreviation,
      'download_url': downloadUrl,
      'size_mb': sizeInMB,
      'description': description,
      'is_downloaded': isDownloaded ? 1 : 0,
    };
  }

  factory BibleTranslation.fromMap(Map<String, dynamic> map) {
    return BibleTranslation(
      id: map['id'],
      name: map['name'],
      abbreviation: map['abbreviation'],
      downloadUrl: map['download_url'],
      sizeInMB: map['size_mb'],
      description: map['description'],
      isDownloaded: map['is_downloaded'] == 1,
    );
  }
}

// Bible Translation Manager
class BibleTranslationManager {
  static final BibleTranslationManager instance =
      BibleTranslationManager._init();
  static Database? _metadataDb;

  BibleTranslationManager._init();

  // Available translations with Google Drive download links
  static final List<BibleTranslation> availableTranslations = [
    BibleTranslation(
      id: 'kjv',
      name: 'King James Version',
      abbreviation: 'KJV',
      downloadUrl:
          'https://drive.google.com/uc?export=download&id=1uANfbL-Hdv11L4_EBqn3W7YO6e6xLDeY',
      sizeInMB: 5,
      description:
          'The classic 1611 English translation, beloved for its literary beauty',
    ),
    BibleTranslation(
      id: 'asv',
      name: 'American Standard Version',
      abbreviation: 'ASV',
      downloadUrl:
          'https://drive.google.com/uc?export=download&id=1DWhhZfnl00USYG1w_0-wVUpfHmDmEMy9',
      sizeInMB: 5,
      description:
          'A revision of the KJV published in 1901, known for its accuracy',
    ),
    BibleTranslation(
      id: 'nheb',
      name: 'New Heart English Bible',
      abbreviation: 'NHEB',
      downloadUrl:
          'https://drive.google.com/uc?export=download&id=1ngZ3Lj7kDMU4EJQxc5sljHHX7clQTOCJ',
      sizeInMB: 5,
      description:
          'A modern English translation focused on accuracy and readability',
    ),
  ];

  // Get metadata database
  Future<Database> get metadataDatabase async {
    if (_metadataDb != null) return _metadataDb!;

    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'bible_translations_metadata.db');

    _metadataDb = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE translations (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            abbreviation TEXT NOT NULL,
            download_url TEXT NOT NULL,
            size_mb INTEGER NOT NULL,
            description TEXT NOT NULL,
            is_downloaded INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
    );

    return _metadataDb!;
  }

  // Initialize translations metadata
  Future<void> initializeTranslations() async {
    final db = await metadataDatabase;

    for (var translation in availableTranslations) {
      final existing = await db.query(
        'translations',
        where: 'id = ?',
        whereArgs: [translation.id],
      );

      if (existing.isEmpty) {
        await db.insert('translations', translation.toMap());
      }
    }
  }

  // Get all translations with download status
  Future<List<BibleTranslation>> getAllTranslations() async {
    final db = await metadataDatabase;
    final maps = await db.query('translations');

    final translations = maps
        .map((map) => BibleTranslation.fromMap(map))
        .toList();

    for (var translation in translations) {
      final exists = await _translationDatabaseExists(translation.id);
      translation.isDownloaded = exists;

      if (exists != (translation.isDownloaded)) {
        await db.update(
          'translations',
          {'is_downloaded': exists ? 1 : 0},
          where: 'id = ?',
          whereArgs: [translation.id],
        );
      }
    }

    return translations;
  }

  // Check if translation database file exists
  Future<bool> _translationDatabaseExists(String translationId) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, 'bible_$translationId.db');
      return await File(path).exists();
    } catch (e) {
      return false;
    }
  }

  // Download translation database
  Future<void> downloadTranslation(
    BibleTranslation translation,
    Function(double) onProgress,
  ) async {
    try {
      // Mark download as in progress
      await markDownloadInProgress(translation.id);

      final dbPath = await getDatabasesPath();
      final filePath = p.join(dbPath, 'bible_${translation.id}.db');

      // Delete any existing incomplete file
      final existingFile = File(filePath);
      if (await existingFile.exists()) {
        await existingFile.delete();
      }

      print('📥 Starting download from: ${translation.downloadUrl}');

      final request = await http.Client().send(
        http.Request('GET', Uri.parse(translation.downloadUrl)),
      );

      if (request.statusCode != 200) {
        throw Exception('Download failed with status: ${request.statusCode}');
      }

      final fileStream = File(filePath).openWrite();
      int downloaded = 0;
      int total = request.contentLength ?? 0;

      print('📊 Total size: $total bytes');

      await for (var chunk in request.stream) {
        fileStream.add(chunk);
        downloaded += chunk.length;

        if (total > 0) {
          final progress = downloaded / total;
          onProgress(progress);

          if (downloaded % 100000 == 0) {
            print(
              '⏬ Downloaded: ${(downloaded / 1024).toStringAsFixed(1)} KB / ${(total / 1024).toStringAsFixed(1)} KB',
            );
          }
        }
      }

      await fileStream.close();
      print('✅ File downloaded: $filePath');

      // Verify the downloaded file
      final isValid = await _verifyDatabase(filePath, translation.abbreviation);
      if (!isValid) {
        await File(filePath).delete();
        await markDownloadComplete(translation.id); // Clear the flag
        throw Exception(
          'Downloaded file is not a valid ${translation.abbreviation} Bible database',
        );
      }

      // Mark as downloaded in metadata ONLY after successful verification
      final db = await metadataDatabase;
      await db.update(
        'translations',
        {'is_downloaded': 1},
        where: 'id = ?',
        whereArgs: [translation.id],
      );

      // Mark download as complete
      await markDownloadComplete(translation.id);

      print(
        '✅ Successfully downloaded and verified ${translation.abbreviation}',
      );
    } catch (e) {
      print('❌ Error downloading ${translation.abbreviation}: $e');

      // Clean up on error
      await markDownloadComplete(translation.id);

      // Delete incomplete file
      final dbPath = await getDatabasesPath();
      final filePath = p.join(dbPath, 'bible_${translation.id}.db');
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      rethrow;
    }
  }

  // Verify downloaded database with better detection
  Future<bool> _verifyDatabase(String path, String abbreviation) async {
    try {
      print('🔍 Verifying database at: $path');

      // Check if file exists and has reasonable size
      final file = File(path);
      if (!await file.exists()) {
        print('❌ File does not exist');
        return false;
      }

      final fileSize = await file.length();
      print('📦 File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB');

      // Bible databases should be at least 3MB (considering KJV is 4.8MB)
      // This allows for some variation but catches incomplete downloads
      if (fileSize < 3 * 1024 * 1024) {
        print('❌ File too small to be a complete Bible database');
        return false;
      }

      final db = await openDatabase(path, readOnly: true);

      // Check if it's a valid SQLite database by listing all tables
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );

      print('📊 Found ${tables.length} tables in database');

      if (tables.isEmpty) {
        await db.close();
        print('❌ No tables found in database');
        return false;
      }

      // Look for translation-specific verse table
      final upperAbbrev = abbreviation.toUpperCase();
      final expectedVersesTable = '${upperAbbrev}_verses';

      print('🔍 Looking for table: $expectedVersesTable');

      String? versesTableName;
      for (var table in tables) {
        final tableName = table['name'] as String;
        if (tableName.toLowerCase() == expectedVersesTable.toLowerCase()) {
          versesTableName = tableName;
          break;
        }
      }

      if (versesTableName == null) {
        print('❌ Verses table not found');
        await db.close();
        return false;
      }

      // Verify the verses table has the required columns
      final columns = await db.rawQuery('PRAGMA table_info($versesTableName)');
      final columnNames = columns
          .map((col) => (col['name'] as String).toLowerCase())
          .toSet();

      print('📋 Columns in $versesTableName: ${columnNames.join(', ')}');

      final requiredColumns = {'id', 'book_id', 'chapter', 'verse', 'text'};
      final hasAllColumns = requiredColumns.every(
        (col) => columnNames.contains(col),
      );

      if (!hasAllColumns) {
        print('❌ Missing required columns');
        await db.close();
        return false;
      }

      // Verify the verses table has sufficient data
      // Bible should have at least 30,000 verses (KJV has ~31,102)
      final verseCount = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $versesTableName'),
      );

      await db.close();

      if (verseCount == null || verseCount < 30000) {
        print('❌ Insufficient verses: $verseCount (expected at least 30,000)');
        return false;
      }

      print(
        '✅ Database verified successfully: $verseCount verses, ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );
      return true;
    } catch (e) {
      print('❌ Database verification failed: $e');
      return false;
    }
  }

  // Delete translation database
  Future<void> deleteTranslation(BibleTranslation translation) async {
    try {
      final dbPath = await getDatabasesPath();
      final filePath = p.join(dbPath, 'bible_${translation.id}.db');

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }

      final db = await metadataDatabase;
      await db.update(
        'translations',
        {'is_downloaded': 0},
        where: 'id = ?',
        whereArgs: [translation.id],
      );

      print('✅ Deleted ${translation.abbreviation}');
    } catch (e) {
      print('❌ Error deleting ${translation.abbreviation}: $e');
      rethrow;
    }
  }

  // Get current selected translation
  Future<String> getCurrentTranslation() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_bible_translation') ?? 'kjv';
  }

  // Set current translation
  Future<void> setCurrentTranslation(String translationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_bible_translation', translationId);
  }

  // Open translation database
  Future<Database?> openTranslationDatabase(String translationId) async {
    try {
      final dbPath = await getDatabasesPath();
      final filePath = p.join(dbPath, 'bible_$translationId.db');

      if (!await File(filePath).exists()) {
        print('❌ Translation database not found: $translationId');
        return null;
      }

      return await openDatabase(filePath, readOnly: true);
    } catch (e) {
      print('❌ Error opening translation database: $e');
      return null;
    }
  }

  // Get verses from translation database - FIXED VERSION
  Future<List<BibleVerse>> getTranslationVerses({
    required String translationId,
    required int bookId,
    required int chapter,
  }) async {
    try {
      final db = await openTranslationDatabase(translationId);
      if (db == null) return [];

      // Use translation-specific table name (e.g., KJV_verses, ASV_verses)
      final upperTranslationId = translationId.toUpperCase();
      final versesTableName = '${upperTranslationId}_verses';

      print('🔍 Querying $versesTableName for book=$bookId, chapter=$chapter');

      // Query the verses directly with known column names
      final List<Map<String, dynamic>> maps = await db.query(
        versesTableName,
        where: 'book_id = ? AND chapter = ?',
        whereArgs: [bookId, chapter],
        orderBy: 'verse ASC',
      );

      await db.close();

      print('📖 Found ${maps.length} verses');

      return maps.map((map) {
        return BibleVerse(
          id: map['id'] as int,
          bookId: map['book_id'] as int,
          chapter: map['chapter'] as int,
          verse: map['verse'] as int,
          text: map['text'] as String,
        );
      }).toList();
    } catch (e) {
      print('❌ Error fetching translation verses: $e');
      return [];
    }
  }

  // Search verses in translation - FIXED VERSION
  Future<List<Map<String, dynamic>>> searchInTranslation({
    required String translationId,
    required String query,
    int limit = 50,
  }) async {
    try {
      final db = await openTranslationDatabase(translationId);
      if (db == null) return [];

      final upperTranslationId = translationId.toUpperCase();
      final versesTableName = '${upperTranslationId}_verses';

      final List<Map<String, dynamic>> maps = await db.query(
        versesTableName,
        where: 'text LIKE ?',
        whereArgs: ['%$query%'],
        limit: limit,
      );

      await db.close();
      return maps;
    } catch (e) {
      print('❌ Error searching translation: $e');
      return [];
    }
  }

  // Get book name from translation database - NEW METHOD
  Future<String?> getBookName(String translationId, int bookId) async {
    try {
      final db = await openTranslationDatabase(translationId);
      if (db == null) return null;

      final upperTranslationId = translationId.toUpperCase();
      final booksTableName = '${upperTranslationId}_books';

      final List<Map<String, dynamic>> maps = await db.query(
        booksTableName,
        where: 'id = ?',
        whereArgs: [bookId],
        limit: 1,
      );

      await db.close();

      if (maps.isNotEmpty) {
        return maps.first['name'] as String;
      }

      return null;
    } catch (e) {
      print('❌ Error getting book name: $e');
      return null;
    }
  }

  // In BibleTranslationManager class, add a method to track partial downloads
  Future<void> markDownloadInProgress(String translationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'downloading_$translationId',
      DateTime.now().toIso8601String(),
    );
  }

  Future<void> markDownloadComplete(String translationId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('downloading_$translationId');
  }

  Future<bool> isDownloadInProgress(String translationId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('downloading_$translationId');
  }

  // Clean up incomplete downloads when app starts
  Future<void> cleanupIncompleteDownloads() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where(
        (key) => key.startsWith('downloading_'),
      );

      for (var key in keys) {
        final translationId = key.replaceFirst('downloading_', '');

        // Delete the incomplete file
        final dbPath = await getDatabasesPath();
        final filePath = p.join(dbPath, 'bible_$translationId.db');
        final file = File(filePath);

        if (await file.exists()) {
          await file.delete();
          print('🗑️ Deleted incomplete download: $translationId');
        }

        // Clear the download flag
        await prefs.remove(key);

        // Mark as not downloaded in metadata
        final db = await metadataDatabase;
        await db.update(
          'translations',
          {'is_downloaded': 0},
          where: 'id = ?',
          whereArgs: [translationId],
        );
      }
    } catch (e) {
      print('❌ Error cleaning up incomplete downloads: $e');
    }
  }
}

// Bible Translations Download Page
class BibleTranslationsDownloadPage extends StatefulWidget {
  const BibleTranslationsDownloadPage({super.key});

  @override
  State<BibleTranslationsDownloadPage> createState() =>
      _BibleTranslationsDownloadPageState();
}

class _BibleTranslationsDownloadPageState
    extends State<BibleTranslationsDownloadPage> {
  List<BibleTranslation> translations = [];
  bool isLoading = true;
  String? currentTranslationId;
  bool isDownloading = false; // ✅ NEW: Track if any download is in progress

  @override
  void initState() {
    super.initState();
    _loadTranslations();
  }

  Future<void> _loadTranslations() async {
    setState(() => isLoading = true);

    try {
      // Initialize translations metadata
      await BibleTranslationManager.instance.initializeTranslations();

      // Get all translations
      final allTranslations = await BibleTranslationManager.instance
          .getAllTranslations();

      // Get current translation
      final current = await BibleTranslationManager.instance
          .getCurrentTranslation();

      setState(() {
        translations = allTranslations;
        currentTranslationId = current;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      _showErrorSnackBar('Failed to load translations: $e');
    }
  }

  // ✅ UPDATED: Prevent back navigation during download
  Future<bool> _onWillPop() async {
    if (isDownloading) {
      _showErrorSnackBar('Please wait for the download to complete');
      return false; // Prevent navigation
    }
    return true; // Allow navigation
  }

  Future<void> _downloadTranslation(BibleTranslation translation) async {
    setState(() {
      translation.isDownloading = true;
      translation.downloadProgress = 0.0;
      isDownloading = true; // ✅ NEW: Set global download flag
    });

    try {
      await BibleTranslationManager.instance.downloadTranslation(translation, (
        progress,
      ) {
        setState(() {
          translation.downloadProgress = progress;
        });
      });

      setState(() {
        translation.isDownloading = false;
        translation.isDownloaded = true;
        isDownloading = false; // ✅ NEW: Clear global download flag
      });

      _showSuccessSnackBar(
        '${translation.abbreviation} downloaded successfully!',
      );
    } catch (e) {
      setState(() {
        translation.isDownloading = false;
        isDownloading = false; // ✅ NEW: Clear global download flag on error
      });
      _showErrorSnackBar('Failed to download ${translation.abbreviation}: $e');
    }
  }

  // ✅ REMOVED: _deleteTranslation method (delete button functionality removed)

  Future<void> _setCurrentTranslation(BibleTranslation translation) async {
    if (!translation.isDownloaded) {
      _showErrorSnackBar('Please download this translation first');
      return;
    }

    try {
      await BibleTranslationManager.instance.setCurrentTranslation(
        translation.id,
      );

      setState(() {
        currentTranslationId = translation.id;
      });

      _showSuccessSnackBar(
        '${translation.abbreviation} set as active translation',
      );
    } catch (e) {
      _showErrorSnackBar('Failed to set translation: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $message'),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $message'),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ UPDATED: Wrap with WillPopScope to prevent back navigation during download
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("📥 Bible Translations"),
          backgroundColor: Colors.black,
          // ✅ UPDATED: Disable back button during download
          leading: isDownloading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(
                    color: Colors.amber,
                    strokeWidth: 2,
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.pop(context),
                ),
        ),
        backgroundColor: const Color(0xFF1E1E1E),
        body: isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              )
            : Column(
                children: [
                  // Info Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    color: Colors.blue[900]?.withOpacity(0.3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue[300]),
                            const SizedBox(width: 8),
                            Text(
                              'Available Translations',
                              style: TextStyle(
                                color: Colors.blue[300],
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Download Bible translations to read offline. You can switch between translations at any time.',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        // ✅ NEW: Warning during download
                        if (isDownloading) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange[900]?.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.orange.withOpacity(0.5),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange[300],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Download in progress. Please wait...',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Translations List
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: translations.length,
                      itemBuilder: (context, index) {
                        final translation = translations[index];
                        return _buildTranslationCard(translation);
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ✅ UPDATED: Remove delete button from translation card
  Widget _buildTranslationCard(BibleTranslation translation) {
    final isActive = translation.id == currentTranslationId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2D2D2D),
        borderRadius: BorderRadius.circular(12),
        border: isActive
            ? Border.all(color: Colors.amber, width: 2)
            : Border.all(color: Colors.white12, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row
          Row(
            children: [
              // Translation Icon
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: translation.isDownloaded
                      ? Colors.green[700]
                      : Colors.grey[700],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  translation.isDownloaded ? Icons.check : Icons.book,
                  color: Colors.white,
                  size: 24,
                ),
              ),

              const SizedBox(width: 12),

              // Translation Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          translation.abbreviation,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      translation.name,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),

              // Status Badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: translation.isDownloaded
                      ? Colors.green.withOpacity(0.2)
                      : Colors.grey.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: translation.isDownloaded
                        ? Colors.green
                        : Colors.grey,
                    width: 1,
                  ),
                ),
                child: Text(
                  translation.isDownloaded
                      ? 'Downloaded'
                      : '${translation.sizeInMB} MB',
                  style: TextStyle(
                    color: translation.isDownloaded
                        ? Colors.green[300]
                        : Colors.grey[400],
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Description
          Text(
            translation.description,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
              height: 1.4,
            ),
          ),

          // Download Progress
          if (translation.isDownloading) ...[
            const SizedBox(height: 12),
            Column(
              children: [
                LinearProgressIndicator(
                  value: translation.downloadProgress,
                  backgroundColor: Colors.grey[800],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(translation.downloadProgress * 100).toInt()}% downloaded',
                  style: const TextStyle(color: Colors.amber, fontSize: 11),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          // ✅ UPDATED Action Buttons: Only download or set active (NO DELETE)
          Row(
            children: [
              if (!translation.isDownloaded && !translation.isDownloading)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed:
                        isDownloading // ✅ Disable if any download in progress
                        ? null
                        : () => _downloadTranslation(translation),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDownloading
                          ? Colors.grey
                          : Colors.amber,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),

              if (translation.isDownloading)
                Expanded(
                  child: ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Downloading...'),
                  ),
                ),

              if (translation.isDownloaded) ...[
                if (!isActive)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _setCurrentTranslation(translation),
                      icon: const Icon(Icons.radio_button_unchecked, size: 18),
                      label: const Text('Set as Active'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                if (isActive)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber, width: 1),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: Colors.amber,
                            size: 18,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Active Translation',
                            style: TextStyle(
                              color: Colors.amber,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ✅ REMOVED: Delete button no longer included
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// Simple Bible Book Page (Shows Chapters)
class SimpleBibleBookPage extends StatelessWidget {
  final SimpleBibleBook book;

  const SimpleBibleBookPage({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(book.name), backgroundColor: Colors.black),
      backgroundColor: const Color(0xFF1E1E1E),
      body: Column(
        children: [
          // Book Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: const Color(0xFF2D2D2D),
            child: Column(
              children: [
                Icon(
                  Icons.menu_book,
                  size: 48,
                  color: book.testament == "Old"
                      ? Colors.blue[300]
                      : Colors.green[300],
                ),
                const SizedBox(height: 12),
                Text(
                  book.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${book.testament} Testament',
                  style: TextStyle(
                    fontSize: 16,
                    color: book.testament == "Old"
                        ? Colors.blue[300]
                        : Colors.green[300],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${book.chapters} ${book.chapters == 1 ? 'Chapter' : 'Chapters'}',
                  style: const TextStyle(fontSize: 14, color: Colors.white70),
                ),
              ],
            ),
          ),

          // Chapters Grid
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.0,
                ),
                itemCount: book.chapters,
                itemBuilder: (context, index) {
                  final chapter = index + 1;
                  return GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EnhancedBibleChapterPage(
                            book: book,
                            chapter: chapter,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2D2D2D),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: book.testament == "Old"
                              ? Colors.blue.withOpacity(0.3)
                              : Colors.green.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          chapter.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Simple Bible Chapter Page (Shows Verses)
class EnhancedBibleChapterPage extends StatefulWidget {
  final SimpleBibleBook book;
  final int chapter;
  final int? highlightVerse;

  const EnhancedBibleChapterPage({
    super.key,
    required this.book,
    required this.chapter,
    this.highlightVerse,
  });

  @override
  State<EnhancedBibleChapterPage> createState() =>
      _EnhancedBibleChapterPageState();
}

class _EnhancedBibleChapterPageState extends State<EnhancedBibleChapterPage> {
  double fontSize = 16.0;
  List<BibleVerse> verses = [];
  Map<int, bool> favoriteVerses = {}; // verse number -> is favorite
  bool isLoading = true;
  String currentTranslationId = 'kjv';
  String currentTranslationName = 'KJV';
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadFontSize();
    _loadCurrentTranslation();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      fontSize = prefs.getDouble('bible_font_size') ?? 16.0;
    });
  }

  Future<void> _loadCurrentTranslation() async {
    try {
      final translationId = await BibleTranslationManager.instance
          .getCurrentTranslation();
      final translations = await BibleTranslationManager.instance
          .getAllTranslations();
      final currentTranslation = translations.firstWhere(
        (t) => t.id == translationId,
        orElse: () => translations.first,
      );

      setState(() {
        currentTranslationId = translationId;
        currentTranslationName = currentTranslation.abbreviation;
      });

      await _loadVerses();
    } catch (e) {
      setState(() {
        currentTranslationId = 'kjv';
        currentTranslationName = 'KJV';
      });
      await _loadVerses();
    }
  }

  Future<void> _loadVerses() async {
    setState(() => isLoading = true);

    try {
      final loadedVerses = await BibleTranslationManager.instance
          .getTranslationVerses(
            translationId: currentTranslationId,
            bookId: widget.book.id,
            chapter: widget.chapter,
          );

      // Load favorite status for all verses
      // Load favorite status for all verses from unified database
      // Load favorite status for all verses from unified database
      final Map<int, bool> favorites = {};
      for (var verse in loadedVerses) {
        final referenceId =
            '${widget.book.id}_${widget.chapter}_${verse.verse}';
        final isFav = await UnifiedFavoritesDatabase.instance.isFavorite(
          type: 'bible_verse',
          referenceId: referenceId,
        );
        favorites[verse.verse] = isFav;
      }

      setState(() {
        verses = loadedVerses;
        favoriteVerses = favorites;
        isLoading = false;
      });

      // Scroll to highlighted verse if provided
      if (widget.highlightVerse != null && loadedVerses.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToVerse(widget.highlightVerse!);
        });
      }
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading verses: $e')));
      }
    }
  }

  void _scrollToVerse(int verseNumber) {
    try {
      final index = verses.indexWhere((v) => v.verse == verseNumber);
      if (index != -1) {
        final position = index * 80.0; // Approximate height per verse
        _scrollController.animateTo(
          position,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      print('Error scrolling to verse: $e');
    }
  }

  Future<void> _toggleFavorite(BibleVerse verse) async {
    try {
      // Use unified favorites database
      final referenceId = '${widget.book.id}_${widget.chapter}_${verse.verse}';
      final isFavorite = favoriteVerses[verse.verse] ?? false;

      if (isFavorite) {
        // Remove from unified favorites
        await UnifiedFavoritesDatabase.instance.removeFavorite(
          type: 'bible_verse',
          referenceId: referenceId,
        );

        setState(() {
          favoriteVerses[verse.verse] = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Removed from favorites'),
            duration: Duration(seconds: 1),
          ),
        );
      } else {
        // Add to unified favorites
        await UnifiedFavoritesDatabase.instance.addFavorite(
          type: 'bible_verse',
          referenceId: referenceId,
          title: '${widget.book.name} ${widget.chapter}:${verse.verse}',
          content: verse.text,
          subtitle: currentTranslationName,
          bookId: widget.book.id,
          chapter: widget.chapter,
          verse: verse.verse,
          translationId: currentTranslationId,
        );

        setState(() {
          favoriteVerses[verse.verse] = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💝 Added to favorites'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _changeTranslation() async {
    try {
      final translations = await BibleTranslationManager.instance
          .getAllTranslations();
      final downloadedTranslations = translations
          .where((t) => t.isDownloaded)
          .toList();

      if (downloadedTranslations.isEmpty) {
        _showErrorSnackBar(
          'No translations downloaded. Please download a translation first.',
        );

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const BibleTranslationsDownloadPage(),
          ),
        );
        return;
      }

      if (!mounted) return;

      final selected = await showDialog<BibleTranslation>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Text(
            'Select Translation',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: downloadedTranslations.length,
              itemBuilder: (context, index) {
                final translation = downloadedTranslations[index];
                final isSelected = translation.id == currentTranslationId;

                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.amber : Colors.white70,
                  ),
                  title: Text(
                    translation.abbreviation,
                    style: TextStyle(
                      color: isSelected ? Colors.amber : Colors.white,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    translation.name,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  onTap: () => Navigator.pop(context, translation),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
          ],
        ),
      );

      if (selected != null && selected.id != currentTranslationId) {
        await BibleTranslationManager.instance.setCurrentTranslation(
          selected.id,
        );
        setState(() {
          currentTranslationId = selected.id;
          currentTranslationName = selected.abbreviation;
        });
        await _loadVerses();
        _showSuccessSnackBar('Switched to ${selected.abbreviation}');
      }
    } catch (e) {
      _showErrorSnackBar('Failed to change translation: $e');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $message'),
        backgroundColor: Colors.green[600],
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('❌ $message'),
        backgroundColor: Colors.red[600],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _saveFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('bible_font_size', fontSize);
  }

  void _showFontSizeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Font Size', style: TextStyle(color: Colors.white)),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Sample Text',
                style: TextStyle(color: Colors.white, fontSize: fontSize),
              ),
              const SizedBox(height: 16),
              Slider(
                value: fontSize,
                min: 12.0,
                max: 24.0,
                divisions: 12,
                activeColor: Colors.amber,
                onChanged: (value) {
                  setDialogState(() => fontSize = value);
                  setState(() => fontSize = value);
                },
              ),
              Text(
                '${fontSize.toInt()}px',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              _saveFontSize();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('Save', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.book.name} ${widget.chapter}',
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              currentTranslationName,
              style: const TextStyle(fontSize: 12, color: Colors.amber),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            onPressed: _changeTranslation,
            tooltip: 'Change Translation',
          ),
          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: _showFontSizeDialog,
            tooltip: 'Font Size',
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : verses.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.menu_book,
                      size: 80,
                      color: Colors.white30,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '${widget.book.name} Chapter ${widget.chapter}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No verses available\nDownload a translation',
                      style: TextStyle(fontSize: 16, color: Colors.white70),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: verses.length,
              itemBuilder: (context, index) {
                final verse = verses[index];
                final isFavorite = favoriteVerses[verse.verse] ?? false;
                final isHighlighted = widget.highlightVerse == verse.verse;

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: isHighlighted
                      ? BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber, width: 2),
                        )
                      : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Verse number
                      Container(
                        width: 40,
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${verse.verse}',
                          style: TextStyle(
                            fontSize: fontSize * 0.85,
                            color: isHighlighted ? Colors.amber : Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Verse text
                      Expanded(
                        child: Text(
                          verse.text,
                          style: TextStyle(
                            fontSize: fontSize,
                            color: Colors.white,
                            height: 1.6,
                          ),
                        ),
                      ),
                      // Favorite button
                      IconButton(
                        icon: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          color: isFavorite ? Colors.red : Colors.white54,
                          size: 20,
                        ),
                        onPressed: () => _toggleFavorite(verse),
                        tooltip: isFavorite
                            ? 'Remove from favorites'
                            : 'Add to favorites',
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
