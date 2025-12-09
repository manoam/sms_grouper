import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../models/log_entry.dart';
import '../models/sms_message.dart';

class SimCard {
  final int slot;
  final int subscriptionId;
  final String carrierName;
  final String displayName;
  final String number;

  SimCard({
    required this.slot,
    required this.subscriptionId,
    required this.carrierName,
    required this.displayName,
    required this.number,
  });

  factory SimCard.fromMap(Map<String, dynamic> map) {
    return SimCard(
      slot: map['slot'] as int? ?? 0,
      subscriptionId: map['subscriptionId'] as int? ?? 0,
      carrierName: map['carrierName'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      number: map['number'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'subscriptionId': subscriptionId,
    'carrierName': carrierName,
    'displayName': displayName,
    'number': number,
  };
}

class SmsService extends ChangeNotifier {
  static const _methodChannel = MethodChannel('com.smsgrouper/sms');
  static const _eventChannel = EventChannel('com.smsgrouper/sms_events');

  final _uuid = const Uuid();

  final List<SmsMessage> _messages = [];
  final List<LogEntry> _logs = [];
  List<SimCard> _simCards = [];

  bool _hasPermission = false;
  bool _isListening = false;
  StreamSubscription? _smsSubscription;

  bool get hasPermission => _hasPermission;
  bool get isListening => _isListening;
  List<SmsMessage> get messages => List.unmodifiable(_messages);
  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<SimCard> get simCards => List.unmodifiable(_simCards);

  Function(SmsMessage)? onSmsReceived;
  Function(String messageId, String status)? onDeliveryReport;
  Function(String messageId, String status)? onStatusUpdate;

  Future<bool> requestPermissions() async {
    if (!Platform.isAndroid) {
      _addLog(LogEntry.warning('SMS non supporté sur cette plateforme'));
      return false;
    }

    try {
      final result = await _methodChannel.invokeMethod<bool>('requestPermissions');
      _hasPermission = result ?? false;

      // Check again after request
      await Future.delayed(const Duration(milliseconds: 500));
      _hasPermission = await _methodChannel.invokeMethod<bool>('hasPermissions') ?? false;

      if (_hasPermission) {
        _addLog(LogEntry.success('Permissions SMS accordées'));
        // Load SIM cards after permissions granted
        await loadSimCards();
      } else {
        _addLog(LogEntry.error('Permissions SMS refusées'));
      }

      notifyListeners();
      return _hasPermission;
    } catch (e) {
      _addLog(LogEntry.error('Erreur de demande de permissions', details: e.toString()));
      return false;
    }
  }

  Future<void> checkPermissions() async {
    if (!Platform.isAndroid) return;

    try {
      _hasPermission = await _methodChannel.invokeMethod<bool>('hasPermissions') ?? false;
      if (_hasPermission) {
        await loadSimCards();
      }
      notifyListeners();
    } catch (e) {
      _hasPermission = false;
    }
  }

  Future<void> loadSimCards() async {
    if (!Platform.isAndroid) return;

    try {
      _addLog(LogEntry.info('Chargement des cartes SIM...'));
      final result = await _methodChannel.invokeMethod<List<dynamic>>('getSimCards');
      if (result != null) {
        _simCards = result
            .map((e) => SimCard.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();

        if (_simCards.isNotEmpty) {
          _addLog(LogEntry.success(
            '${_simCards.length} carte(s) SIM détectée(s)',
            details: _simCards.map((s) => '${s.carrierName} (slot ${s.slot})').join(', '),
          ));
        } else {
          _addLog(LogEntry.warning('Aucune carte SIM détectée'));
        }
        notifyListeners();
      } else {
        _addLog(LogEntry.warning('Résultat getSimCards null'));
      }
    } catch (e) {
      _addLog(LogEntry.error('Erreur chargement cartes SIM', details: e.toString()));
    }
  }

  Future<void> startListening() async {
    if (!Platform.isAndroid) return;
    if (!_hasPermission) {
      await requestPermissions();
      if (!_hasPermission) return;
    }

    _smsSubscription?.cancel();
    _smsSubscription = _eventChannel.receiveBroadcastStream().listen(
      (data) {
        if (data is Map) {
          _handleSmsEvent(Map<String, dynamic>.from(data));
        }
      },
      onError: (error) {
        _addLog(LogEntry.error('Erreur réception SMS', details: error.toString()));
      },
    );

    _isListening = true;
    _addLog(LogEntry.success('Écoute des SMS activée'));
    notifyListeners();
  }

  void stopListening() {
    _smsSubscription?.cancel();
    _smsSubscription = null;
    _isListening = false;
    _addLog(LogEntry.info('Écoute des SMS désactivée'));
    notifyListeners();
  }

  void _handleSmsEvent(Map<String, dynamic> data) {
    debugPrint('_handleSmsEvent received: $data');
    final type = data['type'] as String?;

    switch (type) {
      case 'sms_received':
        debugPrint('Processing sms_received event');
        _handleIncomingSms(data);
        break;
      case 'sms_sent_status':
        _handleSentStatus(data);
        break;
      case 'sms_delivery_status':
        _handleDeliveryStatus(data);
        break;
      default:
        // Legacy format (no type field) - treat as incoming SMS
        if (data.containsKey('address') && data.containsKey('body')) {
          _handleIncomingSms(data);
        }
    }
  }

  void _handleIncomingSms(Map<String, dynamic> data) {
    debugPrint('_handleIncomingSms: data=$data');
    final sms = SmsMessage(
      id: _uuid.v4(),
      address: data['address'] as String? ?? 'Inconnu',
      body: data['body'] as String? ?? '',
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (data['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      type: SmsType.incoming,
    );

    debugPrint('Created incoming SMS: id=${sms.id}, from=${sms.address}');

    _messages.insert(0, sms);
    if (_messages.length > 100) {
      _messages.removeLast();
    }

    _addLog(LogEntry.info(
      'SMS reçu',
      details: 'De: ${sms.address}',
    ));

    debugPrint('Calling onSmsReceived callback: ${onSmsReceived != null}');
    onSmsReceived?.call(sms);
    notifyListeners();
  }

  void _handleSentStatus(Map<String, dynamic> data) {
    debugPrint('_handleSentStatus received: $data');
    final messageId = data['messageId'] as String?;
    final status = data['status'] as String?;
    final to = data['to'] as String?;

    debugPrint('Parsed sent status: messageId=$messageId, status=$status, to=$to');
    if (messageId == null || status == null) {
      debugPrint('messageId or status is null, ignoring sent status');
      return;
    }

    // Update message status in local list
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      final newStatus = status == 'sent' ? SmsStatus.sent : SmsStatus.failed;
      _messages[index] = _messages[index].copyWith(status: newStatus);
      debugPrint('Updated local message status to: $newStatus');
      notifyListeners();
    } else {
      debugPrint('Message not found in local list for id: $messageId');
    }

    if (status != 'sent') {
      _addLog(LogEntry.error(
        'Échec envoi SMS',
        details: 'À: $to | Erreur: $status',
      ));
    }

    // Notify callbacks for database update
    onDeliveryReport?.call(messageId, status);
    onStatusUpdate?.call(messageId, status);
  }

  void _handleDeliveryStatus(Map<String, dynamic> data) {
    debugPrint('_handleDeliveryStatus received: $data');
    final messageId = data['messageId'] as String?;
    final status = data['status'] as String?;
    final to = data['to'] as String?;

    debugPrint('Parsed: messageId=$messageId, status=$status, to=$to');
    if (messageId == null || status == null) {
      debugPrint('messageId or status is null, ignoring delivery status');
      return;
    }

    // Update message status in local list
    if (status == 'delivered') {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: SmsStatus.delivered);
        debugPrint('Updated local message status to: delivered');
        notifyListeners();
      } else {
        debugPrint('Message not found in local list for id: $messageId');
      }

      _addLog(LogEntry.success(
        'SMS livré',
        details: 'À: $to',
      ));
    } else {
      _addLog(LogEntry.warning(
        'Accusé de réception',
        details: 'À: $to | Statut: $status',
      ));
    }

    // Notify callbacks for database update
    onDeliveryReport?.call(messageId, status);
    onStatusUpdate?.call(messageId, status);
  }

  Future<bool> sendSms(String to, String body, {int? simSlot, String? messageId}) async {
    if (!Platform.isAndroid) {
      _addLog(LogEntry.error('Envoi SMS non supporté sur cette plateforme'));
      return false;
    }

    if (!_hasPermission) {
      await requestPermissions();
      if (!_hasPermission) return false;
    }

    try {
      final smsId = messageId ?? _uuid.v4();
      final sms = SmsMessage(
        id: smsId,
        address: to,
        body: body,
        timestamp: DateTime.now(),
        type: SmsType.outgoing,
        status: SmsStatus.pending,
      );

      _messages.insert(0, sms);
      notifyListeners();

      final Map<String, dynamic> args = {
        'to': to,
        'message': body,
        'messageId': smsId,
      };
      if (simSlot != null) {
        args['simSlot'] = simSlot;
      }

      final result = await _methodChannel.invokeMethod<bool>('sendSms', args);

      // Note: Status will be updated via event channel when delivery reports come in
      // For now, just mark as sent if the method call succeeded
      if (result != true) {
        final index = _messages.indexWhere((m) => m.id == smsId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(status: SmsStatus.failed);
        }
        _addLog(LogEntry.error('Échec envoi SMS', details: 'À: $to'));
      } else {
        final simInfo = simSlot != null ? ' (SIM ${simSlot + 1})' : '';
        _addLog(LogEntry.info('SMS en cours d\'envoi$simInfo', details: 'À: $to'));
      }

      notifyListeners();
      return result == true;
    } on PlatformException catch (e) {
      _addLog(LogEntry.error('Échec d\'envoi SMS', details: e.message));
      return false;
    } catch (e) {
      _addLog(LogEntry.error('Échec d\'envoi SMS', details: e.toString()));
      return false;
    }
  }

  /// Returns the message ID for tracking delivery
  String generateMessageId() => _uuid.v4();

  void _addLog(LogEntry log) {
    _logs.insert(0, log);
    if (_logs.length > 100) {
      _logs.removeLast();
    }
    notifyListeners();
  }

  void clearMessages() {
    _messages.clear();
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _smsSubscription?.cancel();
    super.dispose();
  }
}
