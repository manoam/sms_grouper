class SmsMessage {
  final String id;
  final String address;
  final String body;
  final DateTime timestamp;
  final SmsType type;
  final SmsStatus status;

  SmsMessage({
    required this.id,
    required this.address,
    required this.body,
    required this.timestamp,
    required this.type,
    this.status = SmsStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'address': address,
        'body': body,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'status': status.name,
      };

  factory SmsMessage.fromJson(Map<String, dynamic> json) => SmsMessage(
        id: json['id'] as String,
        address: json['address'] as String,
        body: json['body'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        type: SmsType.values.byName(json['type'] as String),
        status: SmsStatus.values.byName(json['status'] as String? ?? 'pending'),
      );

  SmsMessage copyWith({SmsStatus? status}) => SmsMessage(
        id: id,
        address: address,
        body: body,
        timestamp: timestamp,
        type: type,
        status: status ?? this.status,
      );
}

enum SmsType { incoming, outgoing }

enum SmsStatus { pending, sent, delivered, failed }
