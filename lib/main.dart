import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'screens/license_screen.dart';
import 'services/app_service.dart';
import 'services/database_service.dart';
import 'services/license_service.dart';
import 'services/sms_service.dart';
import 'services/websocket_server_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with timeout (works offline after first init)
  try {
    await Firebase.initializeApp().timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        debugPrint('Firebase init timeout - continuing offline');
        return Firebase.app();
      },
    );
  } catch (e) {
    debugPrint('Firebase init error: $e - continuing anyway');
  }

  // Lock orientation to portrait
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  runApp(const SmsGrouperApp());
}

class SmsGrouperApp extends StatelessWidget {
  const SmsGrouperApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LicenseService()),
        ChangeNotifierProvider(create: (_) => DatabaseService()),
        ChangeNotifierProvider(create: (_) => SmsService()),
        ChangeNotifierProxyProvider2<DatabaseService, SmsService,
            WebSocketServerService>(
          create: (context) => WebSocketServerService(
            context.read<DatabaseService>(),
            context.read<SmsService>(),
          ),
          update: (context, dbService, smsService, previous) =>
              previous ?? WebSocketServerService(dbService, smsService),
        ),
        ChangeNotifierProxyProvider4<WebSocketServerService, SmsService,
            DatabaseService, LicenseService, AppService>(
          create: (context) => AppService(
            wsService: context.read<WebSocketServerService>(),
            smsService: context.read<SmsService>(),
            databaseService: context.read<DatabaseService>(),
            licenseService: context.read<LicenseService>(),
          ),
          update: (context, wsService, smsService, dbService, licenseService,
                  previous) =>
              previous ??
              AppService(
                wsService: wsService,
                smsService: smsService,
                databaseService: dbService,
                licenseService: licenseService,
              ),
        ),
      ],
      child: MaterialApp(
        title: 'SMS Grouper',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.light,
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        themeMode: ThemeMode.system,
        home: const _AppWrapper(),
      ),
    );
  }
}

/// Wrapper that checks license status and shows appropriate screen
class _AppWrapper extends StatefulWidget {
  const _AppWrapper();

  @override
  State<_AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<_AppWrapper> {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initializeLicense();
  }

  Future<void> _initializeLicense() async {
    final licenseService = context.read<LicenseService>();
    await licenseService.initialize();
    if (mounted) {
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Consumer<LicenseService>(
      builder: (context, licenseService, _) {
        if (licenseService.hasValidLicense) {
          return const HomeScreen();
        }
        return LicenseScreen(
          onLicenseActivated: () {
            setState(() {});
          },
        );
      },
    );
  }
}
