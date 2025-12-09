class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? details;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.details,
  });

  factory LogEntry.info(String message, {String? details}) => LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: message,
        details: details,
      );

  factory LogEntry.warning(String message, {String? details}) => LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.warning,
        message: message,
        details: details,
      );

  factory LogEntry.error(String message, {String? details}) => LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.error,
        message: message,
        details: details,
      );

  factory LogEntry.success(String message, {String? details}) => LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.success,
        message: message,
        details: details,
      );
}

enum LogLevel { info, warning, error, success }
