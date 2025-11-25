// devotional_enhancements.dart
// Enhanced favorites system with clickable verse/theme cards

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'feature_restrictions.dart';
import 'premium_feature_gate.dart';

// Note: This file works independently of main.dart
// It uses dynamic typing to avoid circular dependencies

// ------------------------- UNIFIED FAVORITES DATABASE -------------------------
class UnifiedFavoritesDatabase {
  static final UnifiedFavoritesDatabase instance =
      UnifiedFavoritesDatabase._init();
  static Database? _database;

  UnifiedFavoritesDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('unified_favorites.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE unified_favorites (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        reference_id TEXT NOT NULL,
        title TEXT NOT NULL,
        content TEXT,
        subtitle TEXT,
        book_id INTEGER,
        chapter INTEGER,
        verse INTEGER,
        translation_id TEXT,
        created_at TEXT NOT NULL,
        UNIQUE(type, reference_id)
      )
    ''');

    // Create index for faster queries
    await db.execute('''
      CREATE INDEX idx_type_reference ON unified_favorites(type, reference_id)
    ''');
  }

  // Add a favorite
  Future<void> addFavorite({
    required String type,
    required String referenceId,
    required String title,
    String? content,
    String? subtitle,
    int? bookId,
    int? chapter,
    int? verse,
    String? translationId,
  }) async {
    final db = await instance.database;

    await db.insert('unified_favorites', {
      'type': type,
      'reference_id': referenceId,
      'title': title,
      'content': content,
      'subtitle': subtitle,
      'book_id': bookId,
      'chapter': chapter,
      'verse': verse,
      'translation_id': translationId,
      'created_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Sync to cloud after adding
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId != null) {
        await CloudSyncManager.instance.syncFavoritesToCloud(userId);
      }
    } catch (e) {
      print('⚠️ Could not sync favorite to cloud: $e');
    }
  }

  // Remove a favorite
  Future<void> removeFavorite({
    required String type,
    required String referenceId,
  }) async {
    final db = await instance.database;

    await db.delete(
      'unified_favorites',
      where: 'type = ? AND reference_id = ?',
      whereArgs: [type, referenceId],
    );

    // Remove from cloud after deleting locally
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId != null) {
        await CloudSyncManager.instance.removeFavoriteFromCloud(
          userId: userId,
          type: type,
          referenceId: referenceId,
        );
      }
    } catch (e) {
      print('⚠️ Could not remove favorite from cloud: $e');
    }
  }

  // Check if a favorite exists
  Future<bool> isFavorite({
    required String type,
    required String referenceId,
  }) async {
    final db = await instance.database;
    final result = await db.query(
      'unified_favorites',
      where: 'type = ? AND reference_id = ?',
      whereArgs: [type, referenceId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // Get all favorites
  Future<List<Map<String, dynamic>>> getAllFavorites() async {
    final db = await instance.database;
    return await db.query('unified_favorites', orderBy: 'created_at DESC');
  }

  // Get favorites by type
  Future<List<Map<String, dynamic>>> getFavoritesByType(String type) async {
    final db = await instance.database;
    return await db.query(
      'unified_favorites',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'created_at DESC',
    );
  }

  // Get devotional favorites
  Future<List<Map<String, dynamic>>> getDevotionalFavorites() async {
    return await getFavoritesByType('devotional');
  }

  // Get Bible verse favorites
  Future<List<Map<String, dynamic>>> getBibleVerseFavorites() async {
    return await getFavoritesByType('bible_verse');
  }

  // Clear all favorites (for testing)
  Future<void> clearAllFavorites() async {
    final db = await instance.database;
    await db.delete('unified_favorites');
  }
}

// ==================== VERSE OF THE MONTH PAGE ====================
class VerseOfTheMonthPage extends StatefulWidget {
  final Map<String, String> verse;

  const VerseOfTheMonthPage({super.key, required this.verse});

  @override
  State<VerseOfTheMonthPage> createState() => _VerseOfTheMonthPageState();
}

class _VerseOfTheMonthPageState extends State<VerseOfTheMonthPage> {
  bool isFavorite = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
  }

  Future<void> _checkFavoriteStatus() async {
    final favStatus = await UnifiedFavoritesDatabase.instance.isFavorite(
      type: 'verse_of_month',
      referenceId: widget.verse['reference']!,
    );

    setState(() {
      isFavorite = favStatus;
      isLoading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    try {
      if (isFavorite) {
        await UnifiedFavoritesDatabase.instance.removeFavorite(
          type: 'verse_of_month',
          referenceId: widget.verse['reference']!,
        );
        setState(() => isFavorite = false);
        _showSnackBar('❌ Removed from favorites', Colors.red);
      } else {
        await UnifiedFavoritesDatabase.instance.addFavorite(
          type: 'verse_of_month',
          referenceId: widget.verse['reference']!,
          title: 'Verse of the Month',
          content: widget.verse['text']!,
          subtitle: widget.verse['reference'],
        );
        setState(() => isFavorite = true);
        _showSnackBar('💝 Added to favorites', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
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
        title: const Text('📖 Verse of the Month'),
        backgroundColor: Colors.black,
        actions: [
          if (!isLoading)
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.red : Colors.white,
              ),
              onPressed: _toggleFavorite,
              tooltip: isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Decorative Icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 2),
                ),
                child: const Icon(
                  Icons.auto_stories,
                  size: 60,
                  color: Colors.amber,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Title
            const Center(
              child: Text(
                'Verse of the Month',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Month
            Center(
              child: Text(
                DateFormat('MMMM yyyy').format(DateTime.now()),
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
            ),

            const SizedBox(height: 40),

            // Verse Text
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"${widget.verse['text']}"',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      height: 1.6,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        widget.verse['reference']!,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[300]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This verse is specially selected for this month to guide and inspire you.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== THEME OF THE MONTH PAGE ====================
class ThemeOfTheMonthPage extends StatefulWidget {
  final String theme;

  const ThemeOfTheMonthPage({super.key, required this.theme});

  @override
  State<ThemeOfTheMonthPage> createState() => _ThemeOfTheMonthPageState();
}

class _ThemeOfTheMonthPageState extends State<ThemeOfTheMonthPage> {
  bool isFavorite = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
  }

  Future<void> _checkFavoriteStatus() async {
    final favStatus = await UnifiedFavoritesDatabase.instance.isFavorite(
      type: 'theme_of_month',
      referenceId: DateFormat('yyyy-MM').format(DateTime.now()),
    );

    setState(() {
      isFavorite = favStatus;
      isLoading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    try {
      final referenceId = DateFormat('yyyy-MM').format(DateTime.now());

      if (isFavorite) {
        await UnifiedFavoritesDatabase.instance.removeFavorite(
          type: 'theme_of_month',
          referenceId: referenceId,
        );
        setState(() => isFavorite = false);
        _showSnackBar('❌ Removed from favorites', Colors.red);
      } else {
        await UnifiedFavoritesDatabase.instance.addFavorite(
          type: 'theme_of_month',
          referenceId: referenceId,
          title: 'Theme of the Month',
          content: widget.theme,
          subtitle: DateFormat('MMMM yyyy').format(DateTime.now()),
        );
        setState(() => isFavorite = true);
        _showSnackBar('💝 Added to favorites', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
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
        title: const Text('💡 Theme of the Month'),
        backgroundColor: Colors.black,
        actions: [
          if (!isLoading)
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color: isFavorite ? Colors.red : Colors.white,
              ),
              onPressed: _toggleFavorite,
              tooltip: isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Decorative Icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber, width: 2),
                ),
                child: const Icon(
                  Icons.lightbulb,
                  size: 60,
                  color: Colors.amber,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Title
            const Center(
              child: Text(
                'Theme of the Month',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.amber,
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Month
            Center(
              child: Text(
                DateFormat('MMMM yyyy').format(DateTime.now()),
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
            ),

            const SizedBox(height: 40),

            // Theme Content
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Center(
                child: Text(
                  widget.theme,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[900]?.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue[300]),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'This theme sets the spiritual focus for the entire month.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== ENHANCED DEVOTIONAL DETAIL PAGE ====================
// This page is designed to work with the Devotional model from main.dart
// To use it, you need to pass the devotional data when navigating

class EnhancedDevotionalDetailPage extends StatefulWidget {
  final dynamic devotional;

  const EnhancedDevotionalDetailPage({super.key, required this.devotional});

  @override
  State<EnhancedDevotionalDetailPage> createState() =>
      _EnhancedDevotionalDetailPageState();
}

class _EnhancedDevotionalDetailPageState
    extends State<EnhancedDevotionalDetailPage> with WidgetsBindingObserver {
  bool _isFavorite = false;
  bool _isDownloaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkStatus();
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

  Future<void> _checkStatus() async {
    // Check favorite status
    final favStatus = await UnifiedFavoritesDatabase.instance.isFavorite(
      type: 'devotional',
      referenceId: widget.devotional.id.toString(),
    );

    // Check download status
    final devotionalId = widget.devotional.id?.toString() ?? '';
    bool downloadStatus = false;

    if (devotionalId.isNotEmpty) {
      try {
        downloadStatus = await DownloadsDatabase.instance.isDownloaded(
          devotionalId,
        );
      } catch (e) {
        print('Error checking download status: $e');
      }
    }

    setState(() {
      _isFavorite = favStatus;
      _isDownloaded = downloadStatus;
    });
  }

  Future<void> _downloadDevotional() async {
    // Check if user has permission to download
    final canDownload = await FeatureRestrictions.canDownloadOffline(context);
    if (!canDownload) {
      return; // Upgrade dialog already shown
    }

    // Validation
    final devotionalId = widget.devotional.id?.toString() ?? '';
    final devotionalTitle = widget.devotional.title?.toString() ?? '';
    final devotionalContent = widget.devotional.content?.toString() ?? '';

    print('📥 Download attempt:');
    print('  ID: "$devotionalId"');
    print('  Title: "$devotionalTitle"');
    print('  Content length: ${devotionalContent.length}');

    if (devotionalId.isEmpty) {
      _showSnackBar("❌ Invalid devotional: Missing ID", Colors.red);
      return;
    }

    if (devotionalTitle.trim().isEmpty) {
      _showSnackBar("❌ Invalid devotional: Missing title", Colors.red);
      return;
    }

    if (devotionalContent.trim().isEmpty) {
      _showSnackBar("❌ No content to download", Colors.red);
      return;
    }

    try {
      _showSnackBar("⏳ Downloading...", Colors.blue);

      // Use the singleton DownloadsDatabase from main.dart
      // You'll need to import it or access it through a global reference
      await DownloadsDatabase.instance.insertDevotional(widget.devotional);

      setState(() {
        _isDownloaded = true;
      });

      _showSnackBar("✅ Downloaded successfully!", Colors.green);
    } catch (e) {
      print('❌ Download error: $e');

      setState(() {
        _isDownloaded = false;
      });

      _showSnackBar("❌ Download failed: ${e.toString()}", Colors.red);
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      if (_isFavorite) {
        await UnifiedFavoritesDatabase.instance.removeFavorite(
          type: 'devotional',
          referenceId: widget.devotional.id.toString(),
        );
        setState(() => _isFavorite = false);
        _showSnackBar('❌ Removed from favorites', Colors.red);
      } else {
        await UnifiedFavoritesDatabase.instance.addFavorite(
          type: 'devotional',
          referenceId: widget.devotional.id.toString(),
          title: widget.devotional.title.toString(),
          content: widget.devotional.content.toString(),
          subtitle: DateFormat(
            'MMM dd, yyyy',
          ).format(widget.devotional.date as DateTime),
        );
        setState(() => _isFavorite = true);
        _showSnackBar('💝 Added to favorites', Colors.green);
      }
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
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
    // ✅ Check if devotional has valid content
    final hasValidContent =
        widget.devotional.id.toString().isNotEmpty &&
        widget.devotional.content.toString().trim().isNotEmpty &&
        widget.devotional.title != 'No devotional for today.';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.devotional.title.toString()),
        backgroundColor: Colors.black,
        actions: [
          // ✅ Only show buttons when there's valid content
          if (hasValidContent) ...[
            // Favorite button
            IconButton(
              icon: Icon(
                _isFavorite ? Icons.favorite : Icons.favorite_border,
                color: _isFavorite ? Colors.red : Colors.white,
              ),
              onPressed: _toggleFavorite,
              tooltip: _isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
            ),

            // Download button
            IconButton(
              icon: Icon(
                _isDownloaded ? Icons.download_done : Icons.download,
                color: Colors.white,
              ),
              onPressed: _isDownloaded ? null : _downloadDevotional,
              tooltip: _isDownloaded ? 'Already downloaded' : 'Download',
            ),
          ],
        ],
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.devotional.title.toString(),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.devotional.content.toString(),
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "Date: ${(widget.devotional.date as DateTime).toLocal().toString().split(' ')[0]}",
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),

            // ✅ Optional: Show a helpful message when no content is available
            if (!hasValidContent) ...[
              const SizedBox(height: 40),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.blue[900]?.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue[300],
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'No devotional available for today',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Please check back later or browse the archive for previous devotionals.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ==================== UNIFIED FAVORITES PAGE ====================
class UnifiedFavoritesPage extends StatefulWidget {
  const UnifiedFavoritesPage({super.key});

  @override
  State<UnifiedFavoritesPage> createState() => _UnifiedFavoritesPageState();
}

class _UnifiedFavoritesPageState extends State<UnifiedFavoritesPage> {
  List<Map<String, dynamic>> allFavorites = [];
  List<Map<String, dynamic>> filteredFavorites = [];
  bool isLoading = true;
  String searchQuery = '';
  String sortOrder = 'newest'; // 'newest', 'oldest', 'alphabetical'

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      searchQuery = _searchController.text;
      _applyFiltersAndSort();
    });
  }

  Future<void> _loadFavorites() async {
    setState(() => isLoading = true);

    try {
      final favorites = await UnifiedFavoritesDatabase.instance
          .getAllFavorites();

      setState(() {
        allFavorites = favorites;
        filteredFavorites = favorites;
        isLoading = false;
      });

      _applyFiltersAndSort();
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('Error loading favorites: $e', Colors.red);
    }
  }

  void _applyFiltersAndSort() {
    List<Map<String, dynamic>> filtered = List.from(allFavorites);

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      filtered = filtered.where((fav) {
        final title = fav['title'].toString().toLowerCase();
        final content = fav['content'].toString().toLowerCase();
        final query = searchQuery.toLowerCase();
        return title.contains(query) || content.contains(query);
      }).toList();
    }

    // Apply sorting
    switch (sortOrder) {
      case 'newest':
        filtered.sort(
          (a, b) =>
              b['created_at'].toString().compareTo(a['created_at'].toString()),
        );
        break;
      case 'oldest':
        filtered.sort(
          (a, b) =>
              a['created_at'].toString().compareTo(b['created_at'].toString()),
        );
        break;
      case 'alphabetical':
        filtered.sort(
          (a, b) => a['title'].toString().compareTo(b['title'].toString()),
        );
        break;
    }

    setState(() {
      filteredFavorites = filtered;
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
            _buildSortOption('Newest First', 'newest', Icons.arrow_downward),
            _buildSortOption('Oldest First', 'oldest', Icons.arrow_upward),
            _buildSortOption(
              'Alphabetical',
              'alphabetical',
              Icons.sort_by_alpha,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String label, String value, IconData icon) {
    return ListTile(
      leading: Icon(
        icon,
        color: sortOrder == value ? Colors.amber : Colors.white70,
      ),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      trailing: sortOrder == value
          ? const Icon(Icons.check, color: Colors.amber)
          : null,
      onTap: () {
        setState(() {
          sortOrder = value;
          _applyFiltersAndSort();
        });
        Navigator.pop(context);
      },
    );
  }

  Future<void> _removeFavorite(Map<String, dynamic> favorite) async {
    try {
      await UnifiedFavoritesDatabase.instance.removeFavorite(
        type: favorite['type'],
        referenceId: favorite['reference_id'],
      );

      await _loadFavorites();
      _showSnackBar('✅ Removed from favorites', Colors.green);
    } catch (e) {
      _showSnackBar('Error: $e', Colors.red);
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

  String _getTypeLabel(String type) {
    switch (type) {
      case 'devotional':
        return 'Devotional';
      case 'verse_of_month':
        return 'Verse of the Month';
      case 'theme_of_month':
        return 'Theme of the Month';
      case 'bible_verse':
        return 'Bible Verse';
      default:
        return 'Item';
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'devotional':
        return Icons.auto_stories;
      case 'verse_of_month':
        return Icons.menu_book;
      case 'theme_of_month':
        return Icons.lightbulb;
      case 'bible_verse':
        return Icons.book;
      default:
        return Icons.favorite;
    }
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'devotional':
        return const Color(0xFF2196F3); // Colors.blue
      case 'verse_of_month':
        return const Color(0xFFFFC107); // Colors.amber
      case 'theme_of_month':
        return const Color(0xFF4CAF50); // Colors.green
      case 'bible_verse':
        return const Color(0xFF9C27B0); // Colors.purple
      default:
        return const Color(0xFF9E9E9E); // Colors.grey
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("💝 Favorites"),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.sort),
            onPressed: _showSortOptions,
            tooltip: 'Sort Options',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFavorites,
            tooltip: 'Refresh',
          ),
        ],
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
                    hintText: 'Search favorites...',
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${filteredFavorites.length} favorite${filteredFavorites.length != 1 ? 's' : ''}',
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
            ),
          ),

          // Favorites List
          Expanded(
            child: isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.amber),
                  )
                : filteredFavorites.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredFavorites.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final favorite = filteredFavorites[index];
                      return _buildFavoriteCard(favorite);
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
            const Icon(Icons.favorite_border, size: 80, color: Colors.white30),
            const SizedBox(height: 24),
            Text(
              searchQuery.isNotEmpty
                  ? 'No favorites found'
                  : 'No favorites yet',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              searchQuery.isNotEmpty
                  ? 'Try adjusting your search'
                  : 'Start adding items to your favorites',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(Map<String, dynamic> favorite) {
    final type = favorite['type'] as String;
    final typeColor = _getTypeColor(type);
    final typeIcon = _getTypeIcon(type);
    final typeLabel = _getTypeLabel(type);

    return GestureDetector(
      onTap: () => _openFavoriteDetail(favorite),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D2D),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: typeColor.withOpacity(0.3), width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: typeColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: typeColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, color: typeColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          color: typeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Delete Button
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.white54),
                  iconSize: 20,
                  onPressed: () => _removeFavorite(favorite),
                  tooltip: 'Remove from favorites',
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Title
            Text(
              favorite['title'] as String,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            if (favorite['subtitle'] != null) ...[
              const SizedBox(height: 4),
              Text(
                favorite['subtitle'] as String,
                style: TextStyle(
                  color: typeColor.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Content Preview
            Text(
              (favorite['content'] as String).length > 150
                  ? "${(favorite['content'] as String).substring(0, 150)}..."
                  : favorite['content'] as String,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.5,
              ),
            ),

            const SizedBox(height: 12),

            // Footer
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat(
                    'MMM dd, yyyy',
                  ).format(DateTime.parse(favorite['created_at'] as String)),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                Row(
                  children: [
                    const Text(
                      'Tap to open',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward,
                      color: Colors.white38,
                      size: 14,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Navigate to appropriate detail page based on type
  void _openFavoriteDetail(Map<String, dynamic> favorite) {
    final type = favorite['type'] as String;

    try {
      switch (type) {
        case 'devotional':
          // Navigate to devotional detail
          // We need to reconstruct a Devotional object
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => FavoriteDevotionalDetailPage(
                title: favorite['title'] as String,
                content: favorite['content'] as String,
                subtitle: favorite['subtitle'] as String?,
              ),
            ),
          );
          break;

        case 'verse_of_month':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VerseOfTheMonthPage(
                verse: {
                  'text': favorite['content'] as String,
                  'reference': favorite['subtitle'] as String? ?? '',
                },
              ),
            ),
          );
          break;

        case 'theme_of_month':
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ThemeOfTheMonthPage(theme: favorite['content'] as String),
            ),
          );
          break;

        case 'bible_verse':
          // Navigate to Bible chapter with highlighted verse
          _navigateToBibleVerse(favorite);
          break;

        default:
          _showSnackBar('Cannot open this item', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Error opening item: $e', Colors.red);
    }
  }

  void _navigateToBibleVerse(Map<String, dynamic> favorite) {
    // This requires accessing SimpleBibleBook from main.dart
    // We'll create a simple detail page instead that shows the verse
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FavoriteBibleVerseDetailPage(
          title: favorite['title'] as String,
          content: favorite['content'] as String,
          subtitle: favorite['subtitle'] as String?,
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
}

// ==================== FAVORITE DETAIL PAGES ====================

// Simple detail page for favorited devotionals
class FavoriteDevotionalDetailPage extends StatelessWidget {
  final String title;
  final String content;
  final String? subtitle;

  const FavoriteDevotionalDetailPage({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 Devotional'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.amber,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
            const SizedBox(height: 20),
            Text(
              content,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple detail page for favorited Bible verses
class FavoriteBibleVerseDetailPage extends StatelessWidget {
  final String title;
  final String content;
  final String? subtitle;

  const FavoriteBibleVerseDetailPage({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📖 Bible Verse'),
        backgroundColor: Colors.black,
      ),
      backgroundColor: const Color(0xFF1E1E1E),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Decorative Icon
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.purple, width: 2),
                ),
                child: const Icon(
                  Icons.menu_book,
                  size: 60,
                  color: Colors.purple,
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Reference
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.purple,
                  ),
                ),
              ),
            ),

            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(
                  subtitle!.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Verse Text
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.purple.withOpacity(0.3)),
              ),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
