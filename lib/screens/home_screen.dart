import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/sms_message.dart';
import '../services/app_service.dart';
import '../services/database_service.dart';
import '../services/websocket_server_service.dart';
import '../services/sms_service.dart';
import '../widgets/server_status_card.dart';
import '../widgets/campaigns_list.dart';
import 'users_screen.dart';
import 'contact_screen.dart';
import 'clients_screen.dart';
import 'license_details_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initPermissions();
  }

  Future<void> _initPermissions() async {
    final smsService = context.read<SmsService>();
    await smsService.requestPermissions();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMS Grouper'),
        centerTitle: true,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Serveur'),
            Tab(icon: Icon(Icons.campaign), text: 'Campagnes'),
            Tab(icon: Icon(Icons.message), text: 'SMS'),
          ],
        ),
      ),
      drawer: _buildDrawer(context),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ServerTab(),
          CampaignsTab(),
          SmsTab(),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.blue.shade800],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.sms,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'SMS Grouper',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Gestion SMS',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.manage_accounts),
            title: const Text('Utilisateurs'),
            subtitle: const Text('Gerer les comptes'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const UsersScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.computer),
            title: const Text('PC connectés'),
            subtitle: const Text('Voir les connexions'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClientsScreen()),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key),
            title: const Text('Licence'),
            subtitle: const Text('Voir les limites'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LicenseDetailsScreen()),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.support_agent),
            title: const Text('Contact'),
            subtitle: const Text('Support et assistance'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class ServerTab extends StatelessWidget {
  const ServerTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<WebSocketServerService, SmsService>(
      builder: (context, wsService, smsService, _) {
        final appService = context.read<AppService>();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ServerStatusCard(
                isRunning: wsService.isRunning,
                localIp: wsService.localIp,
                port: WebSocketServerService.port,
                clientCount: wsService.clientCount,
                hasPermission: smsService.hasPermission,
              ),
              const SizedBox(height: 24),
              _buildActionButtons(context, wsService, appService),
              const SizedBox(height: 24),
              _buildQuickStats(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WebSocketServerService wsService,
    AppService appService,
  ) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: wsService.isRunning
                ? null
                : () async {
                    try {
                      await appService.startServer();
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Erreur: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
            icon: const Icon(Icons.play_arrow),
            label: const Text('Démarrer'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: wsService.isRunning
                ? () async {
                    await appService.stopServer();
                  }
                : null,
            icon: const Icon(Icons.stop),
            label: const Text('Arrêter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    final dbService = context.read<DatabaseService>();

    return FutureBuilder<Map<String, int>>(
      future: dbService.getStatistics(),
      builder: (context, snapshot) {
        final stats = snapshot.data ?? {};

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Statistiques',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                // Campaigns stats
                _StatSection(
                  icon: Icons.campaign,
                  title: 'Campagnes',
                  color: Colors.blue,
                  today: stats['campaignsToday'] ?? 0,
                  month: stats['campaignsMonth'] ?? 0,
                  year: stats['campaignsYear'] ?? 0,
                  total: stats['campaignsTotal'] ?? 0,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                // SMS stats
                _StatSection(
                  icon: Icons.message,
                  title: 'SMS envoyés',
                  color: Colors.green,
                  today: stats['smsToday'] ?? 0,
                  month: stats['smsMonth'] ?? 0,
                  year: stats['smsYear'] ?? 0,
                  total: stats['smsTotal'] ?? 0,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final int today;
  final int month;
  final int year;
  final int total;

  const _StatSection({
    required this.icon,
    required this.title,
    required this.color,
    required this.today,
    required this.month,
    required this.year,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatBox(label: 'Aujourd\'hui', value: today, color: color),
            _StatBox(label: 'Ce mois', value: month, color: color),
            _StatBox(label: 'Cette année', value: year, color: color),
            _StatBox(label: 'Total', value: total, color: color, isTotal: true),
          ],
        ),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool isTotal;

  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isTotal ? color.withOpacity(0.15) : color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: isTotal ? 18 : 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class CampaignsTab extends StatelessWidget {
  const CampaignsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DatabaseService>(
      builder: (context, dbService, _) {
        return CampaignsList(databaseService: dbService);
      },
    );
  }
}

class SmsTab extends StatefulWidget {
  const SmsTab({super.key});

  @override
  State<SmsTab> createState() => _SmsTabState();
}

class _SmsTabState extends State<SmsTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: AnimatedBuilder(
            animation: _tabController,
            builder: (context, _) {
              return TabBar(
                controller: _tabController,
                labelColor: Theme.of(context).colorScheme.primary,
                unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                indicatorColor: Theme.of(context).colorScheme.primary,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call_received, size: 18),
                        if (_tabController.index != 0) ...[
                          const SizedBox(width: 8),
                          const Text('Reçus'),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.call_made, size: 18),
                        if (_tabController.index != 1) ...[
                          const SizedBox(width: 8),
                          const Text('Envoyés'),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _SmsListView(type: SmsType.incoming),
              _SmsListView(type: SmsType.outgoing),
            ],
          ),
        ),
      ],
    );
  }
}

class _SmsListView extends StatefulWidget {
  final SmsType type;

  const _SmsListView({required this.type});

  @override
  State<_SmsListView> createState() => _SmsListViewState();
}

class _SmsListViewState extends State<_SmsListView> {
  final List<SmsMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  bool _hasMore = true;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMessages() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    final dbService = context.read<DatabaseService>();
    final messages = await dbService.getSmsHistory(
      limit: _pageSize,
      offset: 0,
      type: widget.type,
    );

    setState(() {
      _messages.clear();
      _messages.addAll(messages);
      _hasMore = messages.length >= _pageSize;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    setState(() => _isLoading = true);

    final dbService = context.read<DatabaseService>();
    final newMessages = await dbService.getSmsHistory(
      limit: _pageSize,
      offset: _messages.length,
      type: widget.type,
    );

    setState(() {
      _messages.addAll(newMessages);
      _hasMore = newMessages.length >= _pageSize;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_messages.isEmpty && !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              widget.type == SmsType.incoming
                  ? Icons.call_received
                  : Icons.call_made,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              widget.type == SmsType.incoming
                  ? 'Aucun SMS reçu'
                  : 'Aucun SMS envoyé',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMessages,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _messages.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _buildSmsTile(_messages[index]);
        },
      ),
    );
  }

  Widget _buildSmsTile(SmsMessage sms) {
    final dateFormat = DateFormat('dd/MM HH:mm');
    final isIncoming = sms.type == SmsType.incoming;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isIncoming
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isIncoming ? Icons.call_received : Icons.call_made,
                    size: 18,
                    color: isIncoming ? Colors.blue : Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            sms.address,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const Spacer(),
                          if (isIncoming)
                            _buildTypeBadge()
                          else
                            _buildStatusBadge(sms.status),
                        ],
                      ),
                      Text(
                        dateFormat.format(sms.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                sms.body,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_received, size: 12, color: Colors.blue),
          SizedBox(width: 4),
          Text(
            'Reçu',
            style: TextStyle(
              fontSize: 11,
              color: Colors.blue,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(SmsStatus status) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case SmsStatus.pending:
        color = Colors.orange;
        label = 'En attente';
        icon = Icons.schedule;
        break;
      case SmsStatus.sent:
        color = Colors.blue;
        label = 'Envoyé';
        icon = Icons.check;
        break;
      case SmsStatus.delivered:
        color = Colors.green;
        label = 'Livré';
        icon = Icons.done_all;
        break;
      case SmsStatus.failed:
        color = Colors.red;
        label = 'Échec';
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

