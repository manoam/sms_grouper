class ClientConnection {
  final String id;
  final String remoteAddress;
  final DateTime connectedAt;
  bool isActive;

  ClientConnection({
    required this.id,
    required this.remoteAddress,
    required this.connectedAt,
    this.isActive = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'remoteAddress': remoteAddress,
        'connectedAt': connectedAt.toIso8601String(),
        'isActive': isActive,
      };

  Duration get connectionDuration => DateTime.now().difference(connectedAt);

  String get formattedDuration {
    final duration = connectionDuration;
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    }
    return '${duration.inSeconds}s';
  }
}
