import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../services/license_service.dart';
import '../services/database_service.dart';

class LicenseDetailsScreen extends StatelessWidget {
  const LicenseDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Licence'),
        centerTitle: true,
      ),
      body: Consumer<LicenseService>(
        builder: (context, licenseService, _) {
          final license = licenseService.currentLicense;

          if (license == null) {
            return const Center(
              child: Text('Aucune licence active'),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Plan Card
                _buildPlanCard(context, license),
                const SizedBox(height: 16),

                // Limits Card
                _buildLimitsCard(context, license, licenseService),
                const SizedBox(height: 16),

                // License Info Card
                _buildLicenseInfoCard(context, license),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanCard(BuildContext context, LicenseInfo license) {
    Color planColor;
    IconData planIcon;

    switch (license.plan) {
      case LicensePlan.trial:
        planColor = Colors.orange;
        planIcon = Icons.hourglass_empty;
        break;
      case LicensePlan.starter:
        planColor = Colors.blue;
        planIcon = Icons.star_outline;
        break;
      case LicensePlan.pro:
        planColor = Colors.purple;
        planIcon = Icons.star;
        break;
      case LicensePlan.unlimited:
        planColor = Colors.green;
        planIcon = Icons.all_inclusive;
        break;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [planColor.shade400, planColor.shade700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                planIcon,
                color: Colors.white,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Plan ${license.planName}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                license.isValid ? 'Actif' : 'Expire',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitsCard(
      BuildContext context, LicenseInfo license, LicenseService licenseService) {
    final dbService = context.read<DatabaseService>();
    final isTrial = licenseService.isTrial;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: Colors.blue.shade600),
                const SizedBox(width: 12),
                const Text(
                  'Limites',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // SMS per day
            FutureBuilder<int>(
              future: dbService.getSmsSentToday(),
              builder: (context, snapshot) {
                final used = snapshot.data ?? 0;
                final max = license.maxSmsPerDay;
                final isUnlimited = max >= 999999;

                return _buildLimitRow(
                  icon: Icons.message,
                  label: 'SMS par jour',
                  used: used,
                  max: max,
                  isUnlimited: isUnlimited,
                );
              },
            ),
            const Divider(height: 24),

            // Campaigns
            FutureBuilder<int>(
              future: isTrial
                  ? dbService.getTotalCampaigns()
                  : dbService.getCampaignsThisMonth(),
              builder: (context, snapshot) {
                final used = snapshot.data ?? 0;
                final max = license.maxCampaigns;
                final isUnlimited = max >= 999999;
                final periodLabel = isTrial ? '(total)' : '(ce mois)';

                return _buildLimitRow(
                  icon: Icons.campaign,
                  label: 'Campagnes $periodLabel',
                  used: used,
                  max: max,
                  isUnlimited: isUnlimited,
                );
              },
            ),
            const Divider(height: 24),

            // Users
            FutureBuilder<int>(
              future: dbService.getUserCount(),
              builder: (context, snapshot) {
                final used = snapshot.data ?? 0;
                final max = license.maxUsers;
                final isUnlimited = max >= 999999;

                return _buildLimitRow(
                  icon: Icons.people,
                  label: 'Utilisateurs',
                  used: used,
                  max: max,
                  isUnlimited: isUnlimited,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitRow({
    required IconData icon,
    required String label,
    required int used,
    required int max,
    required bool isUnlimited,
  }) {
    final progress = isUnlimited ? 0.0 : (used / max).clamp(0.0, 1.0);
    final isNearLimit = !isUnlimited && progress >= 0.8;
    final isAtLimit = !isUnlimited && used >= max;

    Color progressColor;
    if (isAtLimit) {
      progressColor = Colors.red;
    } else if (isNearLimit) {
      progressColor = Colors.orange;
    } else {
      progressColor = Colors.green;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ),
            Text(
              isUnlimited ? '$used / Illimite' : '$used / $max',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: isAtLimit ? Colors.red : Colors.grey[800],
              ),
            ),
          ],
        ),
        if (!isUnlimited) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 6,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLicenseInfoCard(BuildContext context, LicenseInfo license) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade600),
                const SizedBox(width: 12),
                const Text(
                  'Informations',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _buildInfoRow(
              label: 'Cle de licence',
              value: _maskLicenseKey(license.licenseKey),
            ),
            const SizedBox(height: 12),

            _buildInfoRow(
              label: 'Active le',
              value: dateFormat.format(license.activatedAt),
            ),
            const SizedBox(height: 12),

            _buildInfoRow(
              label: 'Expire le',
              value: license.expiresAt != null
                  ? dateFormat.format(license.expiresAt!)
                  : 'Jamais (a vie)',
            ),
            const SizedBox(height: 12),

            _buildInfoRow(
              label: 'ID Appareil',
              value: _truncateDeviceId(license.deviceId),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({required String label, required String value}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _maskLicenseKey(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }

  String _truncateDeviceId(String deviceId) {
    if (deviceId.length <= 16) return deviceId;
    return '${deviceId.substring(0, 8)}...${deviceId.substring(deviceId.length - 8)}';
  }
}

extension on Color {
  Color get shade400 => withOpacity(0.8);
  Color get shade700 => withOpacity(1.0);
}
