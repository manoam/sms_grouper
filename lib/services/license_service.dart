import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LicensePlan {
  trial,
  starter,
  pro,
  unlimited,
}

class LicenseInfo {
  final String licenseKey;
  final LicensePlan plan;
  final String deviceId;
  final DateTime activatedAt;
  final DateTime? expiresAt; // null = lifetime
  final int maxSmsPerDay;
  final int maxUsers;
  final int maxCampaigns;

  LicenseInfo({
    required this.licenseKey,
    required this.plan,
    required this.deviceId,
    required this.activatedAt,
    this.expiresAt,
    required this.maxSmsPerDay,
    required this.maxUsers,
    required this.maxCampaigns,
  });

  bool get isExpired {
    if (expiresAt == null) return false; // Lifetime license
    return DateTime.now().isAfter(expiresAt!);
  }

  bool get isValid => !isExpired;

  String get planName {
    switch (plan) {
      case LicensePlan.trial:
        return 'Essai';
      case LicensePlan.starter:
        return 'Starter';
      case LicensePlan.pro:
        return 'Pro';
      case LicensePlan.unlimited:
        return 'Unlimited';
    }
  }

  Map<String, dynamic> toJson() => {
        'licenseKey': licenseKey,
        'plan': plan.name,
        'deviceId': deviceId,
        'activatedAt': activatedAt.toIso8601String(),
        'expiresAt': expiresAt?.toIso8601String(),
        'maxSmsPerDay': maxSmsPerDay,
        'maxUsers': maxUsers,
        'maxCampaigns': maxCampaigns,
      };

  factory LicenseInfo.fromJson(Map<String, dynamic> json) {
    return LicenseInfo(
      licenseKey: json['licenseKey'] as String,
      plan: LicensePlan.values.firstWhere(
        (p) => p.name == json['plan'],
        orElse: () => LicensePlan.trial,
      ),
      deviceId: json['deviceId'] as String,
      activatedAt: DateTime.parse(json['activatedAt'] as String),
      expiresAt: json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          : null,
      maxSmsPerDay: json['maxSmsPerDay'] as int,
      maxUsers: json['maxUsers'] as int,
      maxCampaigns: json['maxCampaigns'] as int,
    );
  }
}

class LicenseService extends ChangeNotifier {
  static const String _licenseKeyPref = 'license_key';
  static const String _licenseDataPref = 'license_data';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  LicenseInfo? _currentLicense;
  bool _isLoading = false;
  String? _error;
  String? _deviceId;

  LicenseInfo? get currentLicense => _currentLicense;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasValidLicense => _currentLicense?.isValid ?? false;
  String? get deviceId => _deviceId;

  // License limits
  int get maxSmsPerDay => _currentLicense?.maxSmsPerDay ?? 0;
  int get maxCampaigns => _currentLicense?.maxCampaigns ?? 0;
  bool get isTrial => _currentLicense?.plan == LicensePlan.trial;

  /// Initialize and check existing license
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Get device ID
      _deviceId = await _getDeviceId();

      // Check for stored license
      final prefs = await SharedPreferences.getInstance();
      final storedLicenseData = prefs.getString(_licenseDataPref);

      if (storedLicenseData != null) {
        try {
          final json = Map<String, dynamic>.from(
            _parseJson(storedLicenseData),
          );
          _currentLicense = LicenseInfo.fromJson(json);

          // Verify license on server in background (non-blocking)
          // App will work offline with cached license
          _verifyLicenseOnServer().catchError((e) {
            debugPrint('Background license verification failed: $e');
          });
        } catch (e) {
          debugPrint('Error parsing stored license: $e');
          _currentLicense = null;
        }
      }
    } catch (e) {
      _error = e.toString();
      debugPrint('License initialization error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get current month string (YYYY-MM format)
  String _getCurrentMonth() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  /// Activate a license key
  Future<bool> activateLicense(String licenseKey) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Normalize license key
      licenseKey = licenseKey.trim().toUpperCase();

      // Get device ID
      final deviceId = await _getDeviceId();

      // Check license in Firestore
      final licenseDoc =
          await _firestore.collection('licenses').doc(licenseKey).get();

      if (!licenseDoc.exists) {
        _error = 'Cle de licence invalide';
        return false;
      }

      final licenseData = licenseDoc.data()!;

      // Check if license is revoked
      if (licenseData['revoked'] == true) {
        _error = 'Cette licence a ete revoquee';
        return false;
      }

      // Check if license is already activated on another device
      final activatedDeviceId = licenseData['deviceId'] as String?;
      if (activatedDeviceId != null && activatedDeviceId != deviceId) {
        _error = 'Cette licence est deja activee sur un autre appareil';
        return false;
      }

      // Check monthly activation limit for same device
      // This prevents reinstalling the app to reset counters
      final lastActivationMonth = licenseData['lastActivationMonth'] as String?;
      final lastActivationDeviceId = licenseData['lastActivationDeviceId'] as String?;
      final currentMonth = _getCurrentMonth();

      // Check if we have a local license stored (meaning app was not reinstalled)
      final prefs = await SharedPreferences.getInstance();
      final hasLocalLicense = prefs.getString(_licenseDataPref) != null;

      if (lastActivationMonth == currentMonth && lastActivationDeviceId == deviceId) {
        // This device already activated this month
        if (hasLocalLicense) {
          // App was NOT reinstalled, just reopening - allow
        } else {
          // App was reinstalled (no local license) but Firebase shows activation this month
          _error = 'Cette licence a deja ete activee ce mois-ci sur cet appareil. Reessayez le mois prochain.';
          return false;
        }
      }

      // Get plan
      final plan = LicensePlan.values.firstWhere(
        (p) => p.name == licenseData['plan'],
        orElse: () => LicensePlan.trial,
      );

      // Get limits from Firebase (or fallback to plan defaults)
      final defaultLimits = _getPlanLimits(plan);
      final maxSmsPerDay = licenseData['maxSmsPerDay'] as int? ?? defaultLimits['maxSmsPerDay']!;
      final maxUsers = licenseData['maxUsers'] as int? ?? defaultLimits['maxUsers']!;
      final maxCampaigns = licenseData['maxCampaigns'] as int? ?? defaultLimits['maxCampaigns']!;

      // Activate license on this device
      final now = DateTime.now();
      await _firestore.collection('licenses').doc(licenseKey).update({
        'deviceId': deviceId,
        'activatedAt': now.toIso8601String(),
        'lastVerified': now.toIso8601String(),
        'lastActivationMonth': currentMonth,
        'lastActivationDeviceId': deviceId,
      });

      // Create license info
      _currentLicense = LicenseInfo(
        licenseKey: licenseKey,
        plan: plan,
        deviceId: deviceId,
        activatedAt: now,
        expiresAt: licenseData['expiresAt'] != null
            ? DateTime.parse(licenseData['expiresAt'] as String)
            : null,
        maxSmsPerDay: maxSmsPerDay,
        maxUsers: maxUsers,
        maxCampaigns: maxCampaigns,
      );

      // Store locally
      await _storeLicenseLocally();

      return true;
    } catch (e) {
      _error = 'Erreur d\'activation: $e';
      debugPrint('License activation error: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Verify license on server (called periodically)
  Future<bool> _verifyLicenseOnServer() async {
    if (_currentLicense == null) return false;

    try {
      final licenseDoc = await _firestore
          .collection('licenses')
          .doc(_currentLicense!.licenseKey)
          .get();

      if (!licenseDoc.exists) {
        _currentLicense = null;
        await _clearStoredLicense();
        return false;
      }

      final licenseData = licenseDoc.data()!;

      // Check if revoked
      if (licenseData['revoked'] == true) {
        _currentLicense = null;
        await _clearStoredLicense();
        _error = 'Cette licence a ete revoquee';
        notifyListeners();
        return false;
      }

      // Check device ID
      if (licenseData['deviceId'] != _deviceId) {
        _currentLicense = null;
        await _clearStoredLicense();
        _error = 'Licence transferee sur un autre appareil';
        notifyListeners();
        return false;
      }

      // Update limits from Firebase (in case they changed)
      final plan = LicensePlan.values.firstWhere(
        (p) => p.name == licenseData['plan'],
        orElse: () => _currentLicense!.plan,
      );
      final defaultLimits = _getPlanLimits(plan);

      _currentLicense = LicenseInfo(
        licenseKey: _currentLicense!.licenseKey,
        plan: plan,
        deviceId: _currentLicense!.deviceId,
        activatedAt: _currentLicense!.activatedAt,
        expiresAt: licenseData['expiresAt'] != null
            ? DateTime.parse(licenseData['expiresAt'] as String)
            : _currentLicense!.expiresAt,
        maxSmsPerDay: licenseData['maxSmsPerDay'] as int? ?? defaultLimits['maxSmsPerDay']!,
        maxUsers: licenseData['maxUsers'] as int? ?? defaultLimits['maxUsers']!,
        maxCampaigns: licenseData['maxCampaigns'] as int? ?? defaultLimits['maxCampaigns']!,
      );

      // Store updated license locally
      await _storeLicenseLocally();

      // Update last verified
      await _firestore
          .collection('licenses')
          .doc(_currentLicense!.licenseKey)
          .update({
        'lastVerified': DateTime.now().toIso8601String(),
      });

      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('License verification error: $e');
      // Don't invalidate license on network error
      return _currentLicense?.isValid ?? false;
    }
  }

  /// Deactivate current license
  Future<void> deactivateLicense() async {
    if (_currentLicense == null) return;

    try {
      // Clear device ID on server (allows reactivation on another device)
      await _firestore
          .collection('licenses')
          .doc(_currentLicense!.licenseKey)
          .update({
        'deviceId': null,
        'deactivatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error deactivating license on server: $e');
    }

    _currentLicense = null;
    await _clearStoredLicense();
    notifyListeners();
  }

  /// Get device unique ID
  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;

    try {
      final androidInfo = await _deviceInfo.androidInfo;
      _deviceId = androidInfo.id; // Android ID
      return _deviceId!;
    } catch (e) {
      debugPrint('Error getting device ID: $e');
      // Fallback to a stored ID
      final prefs = await SharedPreferences.getInstance();
      var storedId = prefs.getString('device_id');
      if (storedId == null) {
        storedId = DateTime.now().millisecondsSinceEpoch.toString();
        await prefs.setString('device_id', storedId);
      }
      _deviceId = storedId;
      return _deviceId!;
    }
  }

  /// Get plan limits
  Map<String, int> _getPlanLimits(LicensePlan plan) {
    switch (plan) {
      case LicensePlan.trial:
        return {
          'maxSmsPerDay': 50,
          'maxUsers': 1,
          'maxCampaigns': 3,
        };
      case LicensePlan.starter:
        return {
          'maxSmsPerDay': 500,
          'maxUsers': 3,
          'maxCampaigns': 20,
        };
      case LicensePlan.pro:
        return {
          'maxSmsPerDay': 5000,
          'maxUsers': 10,
          'maxCampaigns': 100,
        };
      case LicensePlan.unlimited:
        return {
          'maxSmsPerDay': 999999,
          'maxUsers': 999999,
          'maxCampaigns': 999999,
        };
    }
  }

  /// Store license locally
  Future<void> _storeLicenseLocally() async {
    if (_currentLicense == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_licenseKeyPref, _currentLicense!.licenseKey);
    await prefs.setString(
        _licenseDataPref, _encodeJson(_currentLicense!.toJson()));
  }

  /// Clear stored license
  Future<void> _clearStoredLicense() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseKeyPref);
    await prefs.remove(_licenseDataPref);
  }

  /// Simple JSON encode/decode helpers
  String _encodeJson(Map<String, dynamic> json) {
    return json.entries.map((e) => '${e.key}::${e.value}').join('||');
  }

  Map<String, dynamic> _parseJson(String encoded) {
    final result = <String, dynamic>{};
    for (final pair in encoded.split('||')) {
      final parts = pair.split('::');
      if (parts.length == 2) {
        final key = parts[0];
        final value = parts[1];
        // Parse int values
        if (value == 'null') {
          result[key] = null;
        } else if (int.tryParse(value) != null) {
          result[key] = int.parse(value);
        } else {
          result[key] = value;
        }
      }
    }
    return result;
  }
}
