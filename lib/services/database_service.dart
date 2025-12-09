import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/sms_message.dart';
import '../models/user.dart';

class DatabaseService extends ChangeNotifier {
  static Database? _database;
  final _uuid = const Uuid();

  List<User> _users = [];
  List<User> get users => List.unmodifiable(_users);

  // Session tokens: token -> userId
  final Map<String, int> _sessions = {};

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'sms_grouper.db');

    return openDatabase(
      path,
      version: 2,
      onCreate: _createDb,
      onUpgrade: _upgradeDb,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    // Users table
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        is_admin INTEGER DEFAULT 0,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        last_login_at TEXT
      )
    ''');

    // SMS history table with user association
    await db.execute('''
      CREATE TABLE sms_history (
        id TEXT PRIMARY KEY,
        user_id INTEGER,
        address TEXT NOT NULL,
        body TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    // Campaigns table for bulk SMS
    await db.execute('''
      CREATE TABLE campaigns (
        id TEXT PRIMARY KEY,
        user_id INTEGER,
        subject TEXT NOT NULL,
        template TEXT NOT NULL,
        total_count INTEGER NOT NULL,
        sent_count INTEGER DEFAULT 0,
        failed_count INTEGER DEFAULT 0,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        completed_at TEXT,
        FOREIGN KEY (user_id) REFERENCES users (id)
      )
    ''');

    // Campaign messages table
    await db.execute('''
      CREATE TABLE campaign_messages (
        id TEXT PRIMARY KEY,
        campaign_id TEXT NOT NULL,
        address TEXT NOT NULL,
        body TEXT NOT NULL,
        status TEXT NOT NULL,
        sent_at TEXT,
        error_message TEXT,
        FOREIGN KEY (campaign_id) REFERENCES campaigns (id)
      )
    ''');

    // Create default admin user
    final adminHash = _hashPassword('admin');
    await db.insert('users', {
      'username': 'admin',
      'password_hash': adminHash,
      'is_admin': 1,
      'is_active': 1,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add campaigns table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS campaigns (
          id TEXT PRIMARY KEY,
          user_id INTEGER,
          subject TEXT NOT NULL,
          template TEXT NOT NULL,
          total_count INTEGER NOT NULL,
          sent_count INTEGER DEFAULT 0,
          failed_count INTEGER DEFAULT 0,
          status TEXT NOT NULL,
          created_at TEXT NOT NULL,
          completed_at TEXT,
          FOREIGN KEY (user_id) REFERENCES users (id)
        )
      ''');

      // Add campaign messages table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS campaign_messages (
          id TEXT PRIMARY KEY,
          campaign_id TEXT NOT NULL,
          address TEXT NOT NULL,
          body TEXT NOT NULL,
          status TEXT NOT NULL,
          sent_at TEXT,
          error_message TEXT,
          FOREIGN KEY (campaign_id) REFERENCES campaigns (id)
        )
      ''');
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  // ============ User Management ============

  Future<void> loadUsers() async {
    final db = await database;
    final maps = await db.query('users', orderBy: 'created_at DESC');
    _users = maps.map((map) => User.fromMap(map)).toList();
    notifyListeners();
  }

  Future<int> getUserCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM users');
    return result.first['count'] as int;
  }

  Future<User?> createUser({
    required String username,
    required String password,
    bool isAdmin = false,
  }) async {
    final db = await database;

    // Check if username exists
    final existing = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
    );

    if (existing.isNotEmpty) {
      return null; // Username already exists
    }

    final user = User(
      username: username,
      passwordHash: _hashPassword(password),
      isAdmin: isAdmin,
    );

    final id = await db.insert('users', user.toMap());
    final newUser = user.copyWith(id: id);

    _users.insert(0, newUser);
    notifyListeners();

    return newUser;
  }

  Future<bool> updateUser(User user, {String? newPassword}) async {
    final db = await database;

    final updateData = user.toMap();
    if (newPassword != null && newPassword.isNotEmpty) {
      updateData['password_hash'] = _hashPassword(newPassword);
    }

    final count = await db.update(
      'users',
      updateData,
      where: 'id = ?',
      whereArgs: [user.id],
    );

    if (count > 0) {
      await loadUsers();
      return true;
    }
    return false;
  }

  Future<bool> deleteUser(int userId) async {
    final db = await database;

    // Don't delete last admin
    final admins = _users.where((u) => u.isAdmin && u.id != userId).toList();
    final userToDelete = _users.firstWhere((u) => u.id == userId);

    if (userToDelete.isAdmin && admins.isEmpty) {
      return false; // Can't delete last admin
    }

    final count = await db.delete(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    );

    if (count > 0) {
      _users.removeWhere((u) => u.id == userId);
      // Remove any sessions for this user
      _sessions.removeWhere((_, id) => id == userId);
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<bool> toggleUserActive(int userId) async {
    final user = _users.firstWhere((u) => u.id == userId);
    final updatedUser = user.copyWith(isActive: !user.isActive);
    return updateUser(updatedUser);
  }

  // ============ Authentication ============

  Future<String?> authenticate(String username, String password) async {
    final db = await database;

    final results = await db.query(
      'users',
      where: 'username = ? AND password_hash = ? AND is_active = 1',
      whereArgs: [username, _hashPassword(password)],
    );

    if (results.isEmpty) {
      return null; // Invalid credentials or inactive user
    }

    final user = User.fromMap(results.first);

    // Update last login
    await db.update(
      'users',
      {'last_login_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [user.id],
    );

    // Generate session token
    final token = _uuid.v4();
    _sessions[token] = user.id!;

    await loadUsers(); // Refresh users list
    return token;
  }

  bool validateSession(String token) {
    return _sessions.containsKey(token);
  }

  int? getUserIdFromSession(String token) {
    return _sessions[token];
  }

  User? getUserFromSession(String token) {
    final userId = _sessions[token];
    if (userId == null) return null;
    try {
      return _users.firstWhere((u) => u.id == userId);
    } catch (_) {
      return null;
    }
  }

  void invalidateSession(String token) {
    _sessions.remove(token);
  }

  // ============ SMS History ============

  Future<void> saveSmsHistory(SmsMessage sms, {int? userId}) async {
    final db = await database;

    await db.insert(
      'sms_history',
      {
        'id': sms.id,
        'user_id': userId,
        'address': sms.address,
        'body': sms.body,
        'timestamp': sms.timestamp.toIso8601String(),
        'type': sms.type.name,
        'status': sms.status.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SmsMessage>> getSmsHistory({
    int? userId,
    int limit = 100,
    int offset = 0,
    SmsType? type,
  }) async {
    final db = await database;

    final List<Map<String, dynamic>> maps;
    String? where;
    List<dynamic> whereArgs = [];

    // Build where clause
    List<String> conditions = [];

    if (userId != null) {
      // Show user's outgoing SMS + all incoming SMS (incoming SMS have no user_id)
      conditions.add("(user_id = ? OR type = 'incoming')");
      whereArgs.add(userId);
    }

    if (type != null) {
      conditions.add("type = ?");
      whereArgs.add(type.name);
    }

    if (conditions.isNotEmpty) {
      where = conditions.join(' AND ');
    }

    maps = await db.query(
      'sms_history',
      where: where,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );

    return maps.map((map) {
      return SmsMessage(
        id: map['id'] as String,
        address: map['address'] as String,
        body: map['body'] as String,
        timestamp: DateTime.parse(map['timestamp'] as String),
        type: SmsType.values.firstWhere((t) => t.name == map['type']),
        status: SmsStatus.values.firstWhere((s) => s.name == map['status']),
      );
    }).toList();
  }

  Future<void> clearSmsHistory({int? userId}) async {
    final db = await database;

    if (userId != null) {
      await db.delete(
        'sms_history',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
    } else {
      await db.delete('sms_history');
    }
  }

  // ============ Campaign Management ============

  Future<String> createCampaign({
    required String subject,
    required String template,
    required int totalCount,
    int? userId,
  }) async {
    final db = await database;
    final campaignId = _uuid.v4();

    await db.insert('campaigns', {
      'id': campaignId,
      'user_id': userId,
      'subject': subject,
      'template': template,
      'total_count': totalCount,
      'sent_count': 0,
      'failed_count': 0,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });

    return campaignId;
  }

  Future<void> addCampaignMessage({
    required String campaignId,
    required String address,
    required String body,
    String? messageId,
  }) async {
    final db = await database;
    final id = messageId ?? _uuid.v4();

    await db.insert('campaign_messages', {
      'id': id,
      'campaign_id': campaignId,
      'address': address,
      'body': body,
      'status': 'pending',
    });
  }

  Future<void> updateCampaignMessageStatus({
    required String campaignId,
    required String address,
    required String status,
    String? errorMessage,
  }) async {
    final db = await database;

    await db.update(
      'campaign_messages',
      {
        'status': status,
        'sent_at': DateTime.now().toIso8601String(),
        if (errorMessage != null) 'error_message': errorMessage,
      },
      where: 'campaign_id = ? AND address = ?',
      whereArgs: [campaignId, address],
    );

    // Update campaign counters
    if (status == 'sent') {
      await db.rawUpdate(
        'UPDATE campaigns SET sent_count = sent_count + 1 WHERE id = ?',
        [campaignId],
      );
    } else if (status == 'failed') {
      await db.rawUpdate(
        'UPDATE campaigns SET failed_count = failed_count + 1 WHERE id = ?',
        [campaignId],
      );
    }

    // Check if campaign is complete
    final campaign = await db.query(
      'campaigns',
      where: 'id = ?',
      whereArgs: [campaignId],
    );

    if (campaign.isNotEmpty) {
      final c = campaign.first;
      final total = c['total_count'] as int;
      final sent = c['sent_count'] as int;
      final failed = c['failed_count'] as int;

      if (sent + failed >= total) {
        await db.update(
          'campaigns',
          {
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [campaignId],
        );
      }
    }
  }

  Future<void> updateCampaignStatus(String campaignId, String status) async {
    final db = await database;

    await db.update(
      'campaigns',
      {
        'status': status,
        if (status == 'completed')
          'completed_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [campaignId],
    );
  }

  Future<List<Map<String, dynamic>>> getCampaigns({int? userId, int limit = 50}) async {
    final db = await database;

    String query;
    List<dynamic> args;

    // Calculate real counts from campaign_messages table
    if (userId != null) {
      query = '''
        SELECT
          campaigns.*,
          users.username as sender_username,
          (SELECT COUNT(*) FROM campaign_messages WHERE campaign_id = campaigns.id) as total_count,
          (SELECT COUNT(*) FROM campaign_messages WHERE campaign_id = campaigns.id AND (status = 'sent' OR status = 'delivered')) as sent_count,
          (SELECT COUNT(*) FROM campaign_messages WHERE campaign_id = campaigns.id AND status = 'failed') as failed_count
        FROM campaigns
        LEFT JOIN users ON campaigns.user_id = users.id
        WHERE campaigns.user_id = ?
        ORDER BY campaigns.created_at DESC
        LIMIT ?
      ''';
      args = [userId, limit];
    } else {
      query = '''
        SELECT
          campaigns.*,
          users.username as sender_username,
          (SELECT COUNT(*) FROM campaign_messages WHERE campaign_id = campaigns.id) as total_count,
          (SELECT COUNT(*) FROM campaign_messages WHERE campaign_id = campaigns.id AND (status = 'sent' OR status = 'delivered')) as sent_count,
          (SELECT COUNT(*) FROM campaign_messages WHERE campaign_id = campaigns.id AND status = 'failed') as failed_count
        FROM campaigns
        LEFT JOIN users ON campaigns.user_id = users.id
        ORDER BY campaigns.created_at DESC
        LIMIT ?
      ''';
      args = [limit];
    }

    return db.rawQuery(query, args);
  }

  Future<List<Map<String, dynamic>>> getCampaignMessages(
    String campaignId, {
    int limit = 100,
    int offset = 0,
    String? statusFilter,
  }) async {
    final db = await database;

    String where = 'campaign_id = ?';
    List<dynamic> whereArgs = [campaignId];

    if (statusFilter != null) {
      if (statusFilter == 'sent') {
        // 'sent' includes both sent and delivered
        where += " AND (status = 'sent' OR status = 'delivered')";
      } else {
        where += ' AND status = ?';
        whereArgs.add(statusFilter);
      }
    }

    return db.query(
      'campaign_messages',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'sent_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<int> getCampaignMessagesCount(String campaignId, {String? statusFilter}) async {
    final db = await database;

    String where = 'campaign_id = ?';
    List<dynamic> whereArgs = [campaignId];

    if (statusFilter != null) {
      if (statusFilter == 'sent') {
        where += " AND (status = 'sent' OR status = 'delivered')";
      } else {
        where += ' AND status = ?';
        whereArgs.add(statusFilter);
      }
    }

    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM campaign_messages WHERE $where',
      whereArgs,
    );

    return result.first['count'] as int;
  }

  Future<Map<String, dynamic>?> getCampaign(String campaignId) async {
    final db = await database;

    final results = await db.query(
      'campaigns',
      where: 'id = ?',
      whereArgs: [campaignId],
    );

    return results.isNotEmpty ? results.first : null;
  }

  // ============ Statistics ============

  Future<Map<String, int>> getStatistics() async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();
    final yearStart = DateTime(now.year, 1, 1).toIso8601String();

    // Campaign counts
    final campaignsTotal = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM campaigns'),
    ) ?? 0;

    final campaignsToday = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM campaigns WHERE created_at >= ?', [todayStart]),
    ) ?? 0;

    final campaignsMonth = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM campaigns WHERE created_at >= ?', [monthStart]),
    ) ?? 0;

    final campaignsYear = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM campaigns WHERE created_at >= ?', [yearStart]),
    ) ?? 0;

    // SMS counts (outgoing only)
    final smsTotal = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM sms_history WHERE type = 'outgoing'"),
    ) ?? 0;

    final smsToday = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM sms_history WHERE type = 'outgoing' AND timestamp >= ?", [todayStart]),
    ) ?? 0;

    final smsMonth = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM sms_history WHERE type = 'outgoing' AND timestamp >= ?", [monthStart]),
    ) ?? 0;

    final smsYear = Sqflite.firstIntValue(
      await db.rawQuery("SELECT COUNT(*) FROM sms_history WHERE type = 'outgoing' AND timestamp >= ?", [yearStart]),
    ) ?? 0;

    return {
      'campaignsTotal': campaignsTotal,
      'campaignsToday': campaignsToday,
      'campaignsMonth': campaignsMonth,
      'campaignsYear': campaignsYear,
      'smsTotal': smsTotal,
      'smsToday': smsToday,
      'smsMonth': smsMonth,
      'smsYear': smsYear,
    };
  }

  // ============ License Limits ============

  /// Get SMS count sent today (for license limit check)
  Future<int> getSmsSentToday() async {
    final db = await database;
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        "SELECT COUNT(*) FROM sms_history WHERE type = 'outgoing' AND timestamp >= ?",
        [todayStart],
      ),
    );

    return result ?? 0;
  }

  /// Get campaigns count for current month (for license limit check)
  Future<int> getCampaignsThisMonth() async {
    final db = await database;
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1).toIso8601String();

    final result = Sqflite.firstIntValue(
      await db.rawQuery(
        'SELECT COUNT(*) FROM campaigns WHERE created_at >= ?',
        [monthStart],
      ),
    );

    return result ?? 0;
  }

  /// Get total campaigns count (for trial license limit check)
  Future<int> getTotalCampaigns() async {
    final db = await database;

    final result = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM campaigns'),
    );

    return result ?? 0;
  }

  // ============ SMS Status Updates ============

  Future<void> updateSmsStatus(String messageId, String status) async {
    final db = await database;

    // Map delivery status to SmsStatus enum value
    String smsStatus;
    switch (status) {
      case 'delivered':
        smsStatus = 'delivered';
        break;
      case 'sent':
        smsStatus = 'sent';
        break;
      case 'failed':
      case 'failed_generic':
      case 'failed_no_service':
      case 'failed_null_pdu':
      case 'failed_radio_off':
      case 'failed_unknown':
      case 'not_delivered':
        smsStatus = 'failed';
        break;
      default:
        smsStatus = 'pending';
    }

    // Update in sms_history table
    final rowsAffected = await db.update(
      'sms_history',
      {'status': smsStatus},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    debugPrint('updateSmsStatus: messageId=$messageId, status=$smsStatus, rowsAffected=$rowsAffected');

    // Also update in campaign_messages if this is a campaign message
    final campaignRowsAffected = await db.update(
      'campaign_messages',
      {'status': smsStatus},
      where: 'id = ?',
      whereArgs: [messageId],
    );

    debugPrint('updateSmsStatus campaign_messages: messageId=$messageId, status=$smsStatus, rowsAffected=$campaignRowsAffected');
  }
}
