import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/license_service.dart';

class LicenseScreen extends StatefulWidget {
  final VoidCallback onLicenseActivated;

  const LicenseScreen({super.key, required this.onLicenseActivated});

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _licenseController = TextEditingController();
  bool _isActivating = false;

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _activateLicense() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isActivating = true);

    final licenseService = context.read<LicenseService>();
    final success =
        await licenseService.activateLicense(_licenseController.text);

    setState(() => _isActivating = false);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Licence activee avec succes!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onLicenseActivated();
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(licenseService.error ?? 'Erreur d\'activation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary,
              Theme.of(context).colorScheme.secondary,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.message_rounded,
                      size: 60,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Title
                  const Text(
                    'SMS Grouper',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Activation de licence',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // License form card
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Entrez votre cle de licence',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // License key input
                          TextFormField(
                            controller: _licenseController,
                            decoration: InputDecoration(
                              labelText: 'Cle de licence',
                              hintText: 'XXXX-XXXX-XXXX-XXXX',
                              prefixIcon: const Icon(Icons.vpn_key),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                            ),
                            textCapitalization: TextCapitalization.characters,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[A-Za-z0-9-]')),
                              _LicenseKeyFormatter(),
                            ],
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Veuillez entrer votre cle de licence';
                              }
                              if (value.replaceAll('-', '').length < 16) {
                                return 'Cle de licence invalide';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // Activate button
                          SizedBox(
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isActivating ? null : _activateLicense,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                foregroundColor:
                                    Theme.of(context).colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isActivating
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Activer la licence',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Device ID info
                  Consumer<LicenseService>(
                    builder: (context, licenseService, _) {
                      final deviceId = licenseService.deviceId ?? '...';
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.phone_android,
                              size: 16,
                              color: Colors.white.withOpacity(0.7),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ID: ${deviceId.length > 20 ? '${deviceId.substring(0, 20)}...' : deviceId}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Contact info
                  Text(
                    'Pour obtenir une licence, contactez le support',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Formatter for license key (adds dashes automatically)
class _LicenseKeyFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Remove all dashes
    var text = newValue.text.replaceAll('-', '').toUpperCase();

    // Limit to 16 characters
    if (text.length > 16) {
      text = text.substring(0, 16);
    }

    // Add dashes every 4 characters
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) {
        buffer.write('-');
      }
      buffer.write(text[i]);
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
