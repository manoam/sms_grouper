import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:uuid/uuid.dart';

import '../models/client_connection.dart';
import '../models/log_entry.dart';
import '../models/sms_message.dart';
import 'database_service.dart';
import 'license_service.dart';
import 'sms_service.dart';

class WebSocketServerService extends ChangeNotifier {
  static const int port = 8085;

  final DatabaseService _databaseService;
  final SmsService _smsService;
  LicenseService? _licenseService;

  HttpServer? _server;
  final Map<String, WebSocket> _clients = {};
  final Map<String, String?> _clientSessions = {}; // clientId -> sessionToken
  final List<ClientConnection> _connections = [];
  final List<LogEntry> _logs = [];
  final _uuid = const Uuid();

  bool _isRunning = false;
  String? _localIp;
  final Map<String, String> _webAssets = {};

  WebSocketServerService(this._databaseService, this._smsService);

  void setLicenseService(LicenseService licenseService) {
    _licenseService = licenseService;
  }

  bool get isRunning => _isRunning;
  String? get localIp => _localIp;
  List<ClientConnection> get connections => List.unmodifiable(_connections);
  List<LogEntry> get logs => List.unmodifiable(_logs);
  int get clientCount => _connections.where((c) => c.isActive).length;

  Function(Map<String, dynamic>)? onSendSmsRequest;

  Future<void> start() async {
    if (_isRunning) return;

    try {
      await _getLocalIp();
      await _loadWebAssets();

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;

      _addLog(LogEntry.success(
        'Serveur WebSocket démarré',
        details: 'Port $port | IP: $_localIp',
      ));

      _server!.listen(_handleRequest);
      notifyListeners();
    } catch (e) {
      _addLog(LogEntry.error('Échec du démarrage du serveur', details: e.toString()));
      rethrow;
    }
  }

  Future<void> _loadWebAssets() async {
    final assetFiles = [
      'index.html',
      'send.html',
      'inbox.html',
      'outbox.html',
      'campaigns.html',
      'style.css',
      'shared.js',
    ];

    for (final file in assetFiles) {
      try {
        _webAssets[file] = await rootBundle.loadString('assets/web/$file');
      } catch (e) {
        _addLog(LogEntry.warning('Asset non trouvé: $file', details: e.toString()));
      }
    }

    if (_webAssets.isNotEmpty) {
      _addLog(LogEntry.info('Assets web chargés', details: '${_webAssets.length} fichiers'));
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;

    for (final client in _clients.values) {
      await client.close();
    }
    _clients.clear();

    for (final connection in _connections) {
      connection.isActive = false;
    }

    await _server?.close();
    _server = null;
    _isRunning = false;

    _addLog(LogEntry.info('Serveur WebSocket arrêté'));
    notifyListeners();
  }

  Future<void> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback) {
            _localIp = address.address;
            return;
          }
        }
      }
      _localIp = '127.0.0.1';
    } catch (e) {
      _localIp = '127.0.0.1';
    }
  }

  void _handleRequest(HttpRequest request) async {
    // Handle WebSocket upgrade requests
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      _handleWebSocketConnection(request);
      return;
    }

    // Serve web assets for HTTP requests
    String path = request.uri.path;

    // Default to index.html for root
    if (path == '/') {
      path = '/index.html';
    }

    // Remove leading slash
    final fileName = path.substring(1);

    if (_webAssets.containsKey(fileName)) {
      final content = _webAssets[fileName]!;

      // Set content type based on file extension
      if (fileName.endsWith('.html')) {
        request.response.headers.contentType = ContentType.html;
      } else if (fileName.endsWith('.css')) {
        request.response.headers.contentType = ContentType('text', 'css', charset: 'utf-8');
      } else if (fileName.endsWith('.js')) {
        request.response.headers.contentType = ContentType('application', 'javascript', charset: 'utf-8');
      }

      request.response.write(content);
      await request.response.close();

      _addLog(LogEntry.info(
        'Asset servi: $fileName',
        details: 'IP: ${request.connectionInfo?.remoteAddress.address}',
      ));
      return;
    }

    // 404 for unknown paths
    request.response.statusCode = HttpStatus.notFound;
    request.response.write('Fichier non trouvé: $fileName');
    await request.response.close();
  }

  void _handleWebSocketConnection(HttpRequest request) async {
    try {
      final socket = await WebSocketTransformer.upgrade(request);
      final clientId = _uuid.v4();
      final remoteAddress = request.connectionInfo?.remoteAddress.address ?? 'unknown';

      _clients[clientId] = socket;

      final connection = ClientConnection(
        id: clientId,
        remoteAddress: remoteAddress,
        connectedAt: DateTime.now(),
      );
      _connections.add(connection);

      _addLog(LogEntry.info(
        'Client connecté',
        details: 'ID: ${clientId.substring(0, 8)}... | IP: $remoteAddress',
      ));

      // Send welcome message
      _sendToClient(clientId, {
        'type': 'connected',
        'clientId': clientId,
        'serverTime': DateTime.now().toIso8601String(),
      });

      notifyListeners();

      socket.listen(
        (data) => _handleMessage(clientId, data),
        onDone: () => _handleDisconnect(clientId),
        onError: (error) => _handleError(clientId, error),
      );
    } catch (e) {
      _addLog(LogEntry.error('Erreur de connexion', details: e.toString()));
    }
  }

  void _handleMessage(String clientId, dynamic data) async {
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final type = message['type'] as String?;

      _addLog(LogEntry.info(
        'Message reçu',
        details: 'Client: ${clientId.substring(0, 8)}... | Type: $type',
      ));

      switch (type) {
        case 'login':
          await _handleLogin(clientId, message);
          break;
        case 'restore_session':
          await _handleRestoreSession(clientId, message);
          break;
        case 'logout':
          _handleLogout(clientId);
          break;
        case 'send_sms':
          if (!_isAuthenticated(clientId)) {
            _sendToClient(clientId, {
              'type': 'auth_required',
              'message': 'Authentification requise',
            });
            return;
          }
          _handleSendSmsRequest(clientId, message);
          break;
        case 'send_bulk_sms':
          if (!_isAuthenticated(clientId)) {
            _sendToClient(clientId, {
              'type': 'auth_required',
              'message': 'Authentification requise',
            });
            return;
          }
          await _handleSendBulkSmsRequest(clientId, message);
          break;
        case 'ping':
          _sendToClient(clientId, {'type': 'pong'});
          break;
        case 'get_status':
          _sendToClient(clientId, {
            'type': 'status',
            'isRunning': _isRunning,
            'clientCount': clientCount,
            'serverTime': DateTime.now().toIso8601String(),
            'authenticated': _isAuthenticated(clientId),
          });
          break;
        case 'get_history':
          debugPrint('get_history request received from client: ${clientId.substring(0, 8)}...');
          if (!_isAuthenticated(clientId)) {
            debugPrint('Client not authenticated, sending auth_required');
            _sendToClient(clientId, {
              'type': 'auth_required',
              'message': 'Authentification requise',
            });
            return;
          }
          debugPrint('Client authenticated, calling _handleGetHistory');
          await _handleGetHistory(clientId);
          break;
        case 'get_campaigns':
          if (!_isAuthenticated(clientId)) {
            _sendToClient(clientId, {
              'type': 'auth_required',
              'message': 'Authentification requise',
            });
            return;
          }
          await _handleGetCampaigns(clientId);
          break;
        case 'get_campaign_messages':
          if (!_isAuthenticated(clientId)) {
            _sendToClient(clientId, {
              'type': 'auth_required',
              'message': 'Authentification requise',
            });
            return;
          }
          await _handleGetCampaignMessages(clientId, message);
          break;
        case 'get_sim_cards':
          if (!_isAuthenticated(clientId)) {
            _sendToClient(clientId, {
              'type': 'auth_required',
              'message': 'Authentification requise',
            });
            return;
          }
          await _handleGetSimCards(clientId);
          break;
        case 'get_limits':
          if (!_isAuthenticated(clientId)) {
            _sendToClient(clientId, {
              'type': 'auth_required',
              'message': 'Authentification requise',
            });
            return;
          }
          await _handleGetLimits(clientId);
          break;
        default:
          _addLog(LogEntry.warning('Type de message inconnu: $type'));
      }
    } catch (e) {
      _addLog(LogEntry.error('Erreur de parsing', details: e.toString()));
    }
  }

  bool _isAuthenticated(String clientId) {
    final sessionToken = _clientSessions[clientId];
    return sessionToken != null && _databaseService.validateSession(sessionToken);
  }

  Future<void> _handleLogin(String clientId, Map<String, dynamic> message) async {
    final username = message['username'] as String?;
    final password = message['password'] as String?;

    if (username == null || password == null) {
      _sendToClient(clientId, {
        'type': 'login_error',
        'message': 'Nom d\'utilisateur et mot de passe requis',
      });
      return;
    }

    final sessionToken = await _databaseService.authenticate(username, password);

    if (sessionToken != null) {
      _clientSessions[clientId] = sessionToken;
      final user = _databaseService.getUserFromSession(sessionToken);

      _sendToClient(clientId, {
        'type': 'login_success',
        'user': user?.toJson(),
        'sessionToken': sessionToken,
      });

      _addLog(LogEntry.success(
        'Utilisateur connecté',
        details: 'User: $username | Client: ${clientId.substring(0, 8)}...',
      ));
    } else {
      _sendToClient(clientId, {
        'type': 'login_error',
        'message': 'Identifiants invalides ou compte désactivé',
      });

      _addLog(LogEntry.warning(
        'Échec de connexion',
        details: 'User: $username | Client: ${clientId.substring(0, 8)}...',
      ));
    }
  }

  Future<void> _handleRestoreSession(String clientId, Map<String, dynamic> message) async {
    final token = message['token'] as String?;

    if (token == null) {
      _sendToClient(clientId, {
        'type': 'session_invalid',
        'message': 'Token manquant',
      });
      return;
    }

    if (_databaseService.validateSession(token)) {
      _clientSessions[clientId] = token;
      final user = _databaseService.getUserFromSession(token);

      _sendToClient(clientId, {
        'type': 'session_restored',
        'user': user?.toJson(),
        'sessionToken': token,
      });

      _addLog(LogEntry.success(
        'Session restaurée',
        details: 'User: ${user?.username} | Client: ${clientId.substring(0, 8)}...',
      ));
    } else {
      _sendToClient(clientId, {
        'type': 'session_invalid',
        'message': 'Session expirée ou invalide',
      });

      _addLog(LogEntry.info(
        'Session invalide',
        details: 'Client: ${clientId.substring(0, 8)}...',
      ));
    }
  }

  void _handleLogout(String clientId) {
    final sessionToken = _clientSessions[clientId];
    if (sessionToken != null) {
      _databaseService.invalidateSession(sessionToken);
    }
    _clientSessions[clientId] = null;

    _sendToClient(clientId, {
      'type': 'logout_success',
    });

    _addLog(LogEntry.info(
      'Utilisateur déconnecté',
      details: 'Client: ${clientId.substring(0, 8)}...',
    ));
  }

  Future<void> _handleGetHistory(String clientId) async {
    final sessionToken = _clientSessions[clientId];
    final userId = _databaseService.getUserIdFromSession(sessionToken!);
    final user = _databaseService.getUserFromSession(sessionToken);

    List<SmsMessage> history;
    if (user?.isAdmin == true) {
      // Admin can see all SMS
      history = await _databaseService.getSmsHistory();
    } else {
      // Regular user sees only their SMS
      history = await _databaseService.getSmsHistory(userId: userId);
    }

    // Debug: log message statuses
    for (final sms in history.where((s) => s.type == SmsType.outgoing).take(5)) {
      debugPrint('History SMS: id=${sms.id.substring(0, 8)}..., status=${sms.status.name}');
    }

    _sendToClient(clientId, {
      'type': 'sms_history',
      'messages': history.map((sms) => sms.toJson()).toList(),
    });
  }

  Future<void> _handleGetSimCards(String clientId) async {
    // Always reload SIM cards to ensure fresh data
    await _smsService.loadSimCards();

    final simCards = _smsService.simCards.map((sim) => sim.toJson()).toList();
    _sendToClient(clientId, {
      'type': 'sim_cards',
      'simCards': simCards,
    });

    _addLog(LogEntry.info(
      'Cartes SIM envoyées au client',
      details: '${simCards.length} carte(s) | Client: ${clientId.substring(0, 8)}...',
    ));
  }

  Future<void> _handleGetLimits(String clientId) async {
    if (_licenseService == null) {
      _sendToClient(clientId, {
        'type': 'limits',
        'error': 'Service de licence non disponible',
      });
      return;
    }

    final isTrial = _licenseService!.isTrial;
    final maxSmsPerDay = _licenseService!.maxSmsPerDay;
    final maxCampaigns = _licenseService!.maxCampaigns;

    // Use local database counters
    final smsSentToday = await _databaseService.getSmsSentToday();
    final campaignsUsed = isTrial
        ? await _databaseService.getTotalCampaigns()
        : await _databaseService.getCampaignsThisMonth();

    final plan = _licenseService!.currentLicense?.planName ?? 'Inconnu';

    _sendToClient(clientId, {
      'type': 'limits',
      'plan': plan,
      'isTrial': isTrial,
      'sms': {
        'used': smsSentToday,
        'max': maxSmsPerDay,
        'remaining': maxSmsPerDay - smsSentToday,
        'limitReached': smsSentToday >= maxSmsPerDay,
      },
      'campaigns': {
        'used': campaignsUsed,
        'max': maxCampaigns,
        'remaining': maxCampaigns - campaignsUsed,
        'limitReached': campaignsUsed >= maxCampaigns,
        'periodType': isTrial ? 'total' : 'monthly',
      },
    });
  }

  void _handleSendSmsRequest(String clientId, Map<String, dynamic> message) {
    final to = message['to'] as String?;
    final body = message['body'] as String?;
    final requestId = message['requestId'] as String?;
    final simSlot = message['simSlot'] as int?;

    if (to == null || body == null) {
      _sendToClient(clientId, {
        'type': 'sms_error',
        'requestId': requestId,
        'error': 'Missing "to" or "body" field',
      });
      return;
    }

    // Get user ID from session
    final sessionToken = _clientSessions[clientId];
    final userId = sessionToken != null
        ? _databaseService.getUserIdFromSession(sessionToken)
        : null;

    onSendSmsRequest?.call({
      'clientId': clientId,
      'requestId': requestId,
      'to': to,
      'body': body,
      'userId': userId,
      'simSlot': simSlot,
    });
  }

  // Track active campaigns
  final Map<String, String> _activeCampaigns = {}; // clientCampaignId -> dbCampaignId

  Future<void> _handleSendBulkSmsRequest(String clientId, Map<String, dynamic> message) async {
    final campaignId = message['campaignId'] as String?;
    final subject = message['subject'] as String?;
    final to = message['to'] as String?;
    final body = message['body'] as String?;
    final template = message['template'] as String?;
    final rowIndex = message['rowIndex'] as int?;
    final totalCount = message['totalCount'] as int?;
    final requestId = message['requestId'] as String?;
    final simSlot = message['simSlot'] as int?;

    if (campaignId == null || to == null || body == null || subject == null) {
      _sendToClient(clientId, {
        'type': 'sms_error',
        'requestId': requestId,
        'error': 'Missing required fields for bulk SMS',
      });
      return;
    }

    // Get user ID from session
    final sessionToken = _clientSessions[clientId];
    final userId = sessionToken != null
        ? _databaseService.getUserIdFromSession(sessionToken)
        : null;

    // Create campaign in database if it doesn't exist yet
    String dbCampaignId;
    if (!_activeCampaigns.containsKey(campaignId)) {
      // Check campaign limit before creating (using local database)
      if (_licenseService != null) {
        final isTrial = _licenseService!.isTrial;
        final maxCampaigns = _licenseService!.maxCampaigns;
        final campaignsUsed = isTrial
            ? await _databaseService.getTotalCampaigns()
            : await _databaseService.getCampaignsThisMonth();

        if (campaignsUsed >= maxCampaigns) {
          final limitType = isTrial ? 'totale' : 'mensuelle';
          _sendToClient(clientId, {
            'type': 'sms_error',
            'requestId': requestId,
            'error': 'Limite $limitType de campagnes atteinte ($maxCampaigns)',
          });
          _addLog(LogEntry.error(
            'Limite campagnes atteinte',
            details: 'Max: $maxCampaigns campagnes',
          ));
          return;
        }
      }

      dbCampaignId = await _databaseService.createCampaign(
        subject: subject,
        template: template ?? body,
        totalCount: totalCount ?? 1,
        userId: userId,
      );
      _activeCampaigns[campaignId] = dbCampaignId;

      _addLog(LogEntry.info(
        'Campagne créée: $subject',
        details: '$totalCount destinataires | Client: ${clientId.substring(0, 8)}...',
      ));
    } else {
      dbCampaignId = _activeCampaigns[campaignId]!;
    }

    // Generate messageId for tracking delivery - use same ID for campaign_message and SMS
    final messageId = _uuid.v4();
    debugPrint('Generated messageId for campaign SMS: $messageId');

    // Add message to campaign with the messageId
    await _databaseService.addCampaignMessage(
      campaignId: dbCampaignId,
      address: to,
      body: body,
      messageId: messageId,
    );

    // Send SMS request with campaign info and messageId
    onSendSmsRequest?.call({
      'clientId': clientId,
      'requestId': requestId,
      'to': to,
      'body': body,
      'userId': userId,
      'campaignId': dbCampaignId,
      'isBulk': true,
      'simSlot': simSlot,
      'messageId': messageId,
    });
  }

  Future<void> _handleGetCampaigns(String clientId) async {
    final sessionToken = _clientSessions[clientId];
    final userId = _databaseService.getUserIdFromSession(sessionToken!);
    final user = _databaseService.getUserFromSession(sessionToken);

    List<Map<String, dynamic>> campaigns;
    if (user?.isAdmin == true) {
      campaigns = await _databaseService.getCampaigns();
    } else {
      campaigns = await _databaseService.getCampaigns(userId: userId);
    }

    _sendToClient(clientId, {
      'type': 'campaigns_list',
      'campaigns': campaigns,
    });
  }

  Future<void> _handleGetCampaignMessages(String clientId, Map<String, dynamic> message) async {
    final campaignId = message['campaignId'] as String?;
    final limit = message['limit'] as int? ?? 10;
    final offset = message['offset'] as int? ?? 0;
    final statusFilter = message['statusFilter'] as String?;

    if (campaignId == null) {
      _sendToClient(clientId, {
        'type': 'error',
        'message': 'Campaign ID requis',
      });
      return;
    }

    final messages = await _databaseService.getCampaignMessages(
      campaignId,
      limit: limit,
      offset: offset,
      statusFilter: statusFilter,
    );

    // Get total count for pagination info
    final totalCount = await _databaseService.getCampaignMessagesCount(
      campaignId,
      statusFilter: statusFilter,
    );

    // Get all stats counts for the modal (only on first load)
    Map<String, int>? stats;
    if (offset == 0) {
      final results = await Future.wait([
        _databaseService.getCampaignMessagesCount(campaignId),
        _databaseService.getCampaignMessagesCount(campaignId, statusFilter: 'pending'),
        _databaseService.getCampaignMessagesCount(campaignId, statusFilter: 'sent'),
        _databaseService.getCampaignMessagesCount(campaignId, statusFilter: 'delivered'),
        _databaseService.getCampaignMessagesCount(campaignId, statusFilter: 'failed'),
      ]);
      stats = {
        'total': results[0],
        'pending': results[1],
        'sent': results[2],
        'delivered': results[3],
        'failed': results[4],
      };
    }

    _sendToClient(clientId, {
      'type': 'campaign_messages',
      'campaignId': campaignId,
      'messages': messages,
      'totalCount': totalCount,
      'limit': limit,
      'offset': offset,
      'hasMore': offset + messages.length < totalCount,
      if (stats != null) 'stats': stats,
    });
  }

  Future<void> updateCampaignMessageStatus({
    required String campaignId,
    required String address,
    required bool success,
    String? error,
  }) async {
    await _databaseService.updateCampaignMessageStatus(
      campaignId: campaignId,
      address: address,
      status: success ? 'sent' : 'failed',
      errorMessage: error,
    );
  }

  int? getUserIdForClient(String clientId) {
    final sessionToken = _clientSessions[clientId];
    return sessionToken != null
        ? _databaseService.getUserIdFromSession(sessionToken)
        : null;
  }

  void _handleDisconnect(String clientId) {
    _clients.remove(clientId);
    final connection = _connections.firstWhere(
      (c) => c.id == clientId,
      orElse: () => ClientConnection(
        id: clientId,
        remoteAddress: 'unknown',
        connectedAt: DateTime.now(),
      ),
    );
    connection.isActive = false;

    _addLog(LogEntry.info(
      'Client déconnecté',
      details: 'ID: ${clientId.substring(0, 8)}... | Durée: ${connection.formattedDuration}',
    ));

    notifyListeners();
  }

  void _handleError(String clientId, dynamic error) {
    _addLog(LogEntry.error(
      'Erreur client',
      details: 'ID: ${clientId.substring(0, 8)}... | $error',
    ));
    _handleDisconnect(clientId);
  }

  void _sendToClient(String clientId, Map<String, dynamic> data) {
    final client = _clients[clientId];
    if (client != null) {
      try {
        client.add(jsonEncode(data));
      } catch (e) {
        _addLog(LogEntry.error('Échec d\'envoi au client', details: e.toString()));
      }
    }
  }

  void broadcastSmsReceived(SmsMessage sms) {
    final data = {
      'type': 'sms_received',
      'sms': sms.toJson(),
    };

    for (final clientId in _clients.keys) {
      _sendToClient(clientId, data);
    }

    _addLog(LogEntry.info(
      'SMS diffusé aux clients',
      details: 'De: ${sms.address} | ${clientCount} client(s)',
    ));
  }

  void notifySmsSent(String clientId, String? requestId, bool success, {String? error}) {
    _sendToClient(clientId, {
      'type': success ? 'sms_sent' : 'sms_error',
      'requestId': requestId,
      if (error != null) 'error': error,
    });
  }

  void broadcastDeliveryStatus(String messageId, String status) {
    final data = {
      'type': 'delivery_status',
      'messageId': messageId,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    };

    for (final clientId in _clients.keys) {
      _sendToClient(clientId, data);
    }

    _addLog(LogEntry.info(
      'Accusé diffusé aux clients',
      details: 'Message: ${messageId.substring(0, 8)}... | Statut: $status | ${clientCount} client(s)',
    ));
  }

  void _addLog(LogEntry log) {
    _logs.insert(0, log);
    if (_logs.length > 100) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  void clearConnectionHistory() {
    _connections.removeWhere((c) => !c.isActive);
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
