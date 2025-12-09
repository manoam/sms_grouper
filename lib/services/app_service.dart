import 'package:flutter/foundation.dart';

import '../models/log_entry.dart';
import '../models/sms_message.dart';
import 'database_service.dart';
import 'license_service.dart';
import 'sms_service.dart';
import 'websocket_server_service.dart';

class AppService extends ChangeNotifier {
  final WebSocketServerService wsService;
  final SmsService smsService;
  final DatabaseService databaseService;
  final LicenseService licenseService;

  final List<LogEntry> _logs = [];

  AppService({
    required this.wsService,
    required this.smsService,
    required this.databaseService,
    required this.licenseService,
  }) {
    wsService.setLicenseService(licenseService);
    _setupListeners();
  }

  List<LogEntry> get logs => List.unmodifiable(_logs);

  void _setupListeners() {
    // When WebSocket client requests to send SMS
    wsService.onSendSmsRequest = _handleSendSmsRequest;

    // When SMS is received, broadcast to WebSocket clients
    smsService.onSmsReceived = _handleSmsReceived;

    // When delivery report is received
    smsService.onDeliveryReport = _handleDeliveryReport;

    // When SMS status changes, update database
    smsService.onStatusUpdate = _handleStatusUpdate;
  }

  void _handleStatusUpdate(String messageId, String status) {
    debugPrint('_handleStatusUpdate: messageId=$messageId, status=$status');
    // Update database with new status
    databaseService.updateSmsStatus(messageId, status);
  }

  Future<void> _handleSendSmsRequest(Map<String, dynamic> request) async {
    final clientId = request['clientId'] as String;
    final requestId = request['requestId'] as String?;
    final to = request['to'] as String;
    final body = request['body'] as String;
    final userId = request['userId'] as int?;
    final campaignId = request['campaignId'] as String?;
    final isBulk = request['isBulk'] as bool? ?? false;
    final simSlot = request['simSlot'] as int?;

    // Check SMS daily limit (using local database)
    final smsSentToday = await databaseService.getSmsSentToday();
    final maxSmsPerDay = licenseService.maxSmsPerDay;
    if (smsSentToday >= maxSmsPerDay) {
      _addLog(LogEntry.error(
        'Limite SMS atteinte',
        details: '$smsSentToday/$maxSmsPerDay SMS envoyes aujourd\'hui',
      ));
      wsService.notifySmsSent(clientId, requestId, false,
          error: 'Limite journaliere atteinte ($maxSmsPerDay SMS/jour)');
      return;
    }

    // Use provided messageId (from campaign) or generate a new one
    final messageId = request['messageId'] as String? ?? smsService.generateMessageId();
    debugPrint('Using messageId for SMS: $messageId (provided: ${request['messageId'] != null})');

    final simInfo = simSlot != null ? ' (SIM ${simSlot + 1})' : '';
    _addLog(LogEntry.info(
      isBulk ? 'Envoi SMS campagne$simInfo' : 'Demande d\'envoi SMS$simInfo',
      details: 'Client: ${clientId.substring(0, 8)}... → $to',
    ));

    // Save SMS to database BEFORE sending (with pending status)
    final sms = SmsMessage(
      id: messageId,
      address: to,
      body: body,
      timestamp: DateTime.now(),
      type: SmsType.outgoing,
      status: SmsStatus.pending,
    );
    debugPrint('Saving SMS to database with id: ${sms.id}');
    await databaseService.saveSmsHistory(sms, userId: userId);

    // Send SMS with the same messageId for tracking
    final success = await smsService.sendSms(to, body, simSlot: simSlot, messageId: messageId);
    wsService.notifySmsSent(clientId, requestId, success);

    // Update status immediately if failed
    if (!success) {
      await databaseService.updateSmsStatus(messageId, 'failed');
    }

    // Update campaign message status if this is a bulk SMS
    if (isBulk && campaignId != null) {
      await wsService.updateCampaignMessageStatus(
        campaignId: campaignId,
        address: to,
        success: success,
        error: success ? null : 'Échec d\'envoi',
      );
    }

    if (success) {
      _addLog(LogEntry.success('SMS envoyé via WebSocket', details: 'À: $to'));
    } else {
      _addLog(LogEntry.error('Échec envoi SMS via WebSocket', details: 'À: $to'));
    }
  }

  void _handleSmsReceived(SmsMessage sms) {
    debugPrint('_handleSmsReceived: from=${sms.address}, body=${sms.body.substring(0, sms.body.length > 20 ? 20 : sms.body.length)}...');
    _addLog(LogEntry.info(
      'SMS reçu, diffusion aux clients',
      details: 'De: ${sms.address}',
    ));

    // Save received SMS to database (no specific user)
    debugPrint('Saving incoming SMS to database');
    databaseService.saveSmsHistory(sms);

    debugPrint('Broadcasting SMS to ${wsService.clientCount} WebSocket clients');
    wsService.broadcastSmsReceived(sms);
  }

  void _handleDeliveryReport(String messageId, String status) {
    debugPrint('_handleDeliveryReport: messageId=$messageId, status=$status');

    _addLog(LogEntry.info(
      'Accusé de réception',
      details: 'Message: ${messageId.substring(0, 8)}... | Statut: $status',
    ));

    // Broadcast delivery status to all WebSocket clients
    wsService.broadcastDeliveryStatus(messageId, status);

    // Update database if needed
    debugPrint('Calling databaseService.updateSmsStatus with messageId=$messageId');
    databaseService.updateSmsStatus(messageId, status);
  }

  Future<void> startServer() async {
    await wsService.start();
    await smsService.startListening();
    _addLog(LogEntry.success('Services démarrés'));
    notifyListeners();
  }

  Future<void> stopServer() async {
    await wsService.stop();
    smsService.stopListening();
    _addLog(LogEntry.info('Services arrêtés'));
    notifyListeners();
  }

  void _addLog(LogEntry log) {
    _logs.insert(0, log);
    if (_logs.length > 100) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  void clearAllLogs() {
    _logs.clear();
    wsService.clearLogs();
    smsService.clearLogs();
    notifyListeners();
  }

  @override
  void dispose() {
    stopServer();
    super.dispose();
  }
}
