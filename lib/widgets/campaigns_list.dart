import 'package:flutter/material.dart';

import '../services/database_service.dart';

class CampaignsList extends StatefulWidget {
  final DatabaseService databaseService;

  const CampaignsList({super.key, required this.databaseService});

  @override
  State<CampaignsList> createState() => _CampaignsListState();
}

class _CampaignsListState extends State<CampaignsList> {
  List<Map<String, dynamic>> _campaigns = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCampaigns();
  }

  Future<void> _loadCampaigns() async {
    setState(() => _isLoading = true);
    try {
      final campaigns = await widget.databaseService.getCampaigns();
      setState(() {
        _campaigns = campaigns;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_campaigns.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.campaign_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Aucune campagne',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Les campagnes envoyees apparaitront ici',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadCampaigns,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualiser'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCampaigns,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _campaigns.length,
        itemBuilder: (context, index) {
          final campaign = _campaigns[index];
          return _CampaignCard(
            campaign: campaign,
            onTap: () => _showCampaignDetails(campaign),
          );
        },
      ),
    );
  }

  void _showCampaignDetails(Map<String, dynamic> campaign) async {
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _CampaignDetailSheet(
          campaign: campaign,
          databaseService: widget.databaseService,
          scrollController: scrollController,
        ),
      ),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final Map<String, dynamic> campaign;
  final VoidCallback onTap;

  const _CampaignCard({required this.campaign, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = campaign['status'] as String? ?? 'pending';
    final totalCount = campaign['total_count'] as int? ?? 0;
    final sentCount = campaign['sent_count'] as int? ?? 0;
    final failedCount = campaign['failed_count'] as int? ?? 0;
    final senderUsername = campaign['sender_username'] as String? ?? 'Inconnu';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      campaign['subject'] ?? 'Sans titre',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _StatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    senderUsername,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                  const Spacer(),
                  Text(
                    _formatDate(campaign['created_at']),
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatChip(
                    label: 'Total',
                    value: totalCount.toString(),
                    color: Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Envoyes',
                    value: sentCount.toString(),
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _StatChip(
                    label: 'Echecs',
                    value: failedCount.toString(),
                    color: Colors.red,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateStr;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case 'completed':
        bgColor = Colors.green[100]!;
        textColor = Colors.green[800]!;
        label = 'Termine';
        break;
      case 'pending':
      default:
        bgColor = Colors.orange[100]!;
        textColor = Colors.orange[800]!;
        label = 'En cours';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampaignDetailSheet extends StatefulWidget {
  final Map<String, dynamic> campaign;
  final DatabaseService databaseService;
  final ScrollController scrollController;

  const _CampaignDetailSheet({
    required this.campaign,
    required this.databaseService,
    required this.scrollController,
  });

  @override
  State<_CampaignDetailSheet> createState() => _CampaignDetailSheetState();
}

class _CampaignDetailSheetState extends State<_CampaignDetailSheet> {
  String? _selectedFilter; // null = all, 'pending', 'sent', 'delivered', 'failed'
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  static const int _pageSize = 10;

  // Stats counts
  int _totalCount = 0;
  int _pendingCount = 0;
  int _sentCount = 0;
  int _deliveredCount = 0;
  int _failedCount = 0;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadMessages();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (widget.scrollController.position.pixels >=
        widget.scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadStats() async {
    final campaignId = widget.campaign['id'] as String;
    final db = widget.databaseService;

    // Load all counts in parallel
    final results = await Future.wait([
      db.getCampaignMessagesCount(campaignId),
      db.getCampaignMessagesCount(campaignId, statusFilter: 'pending'),
      db.getCampaignMessagesCount(campaignId, statusFilter: 'sent'),
      db.getCampaignMessagesCount(campaignId, statusFilter: 'delivered'),
      db.getCampaignMessagesCount(campaignId, statusFilter: 'failed'),
    ]);

    if (mounted) {
      setState(() {
        _totalCount = results[0];
        _pendingCount = results[1];
        _sentCount = results[2]; // includes delivered
        _deliveredCount = results[3];
        _failedCount = results[4];
      });
    }
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    final messages = await widget.databaseService.getCampaignMessages(
      widget.campaign['id'],
      limit: _pageSize,
      offset: 0,
      statusFilter: _selectedFilter,
    );

    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(messages);
        _hasMore = messages.length >= _pageSize;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);

    final newMessages = await widget.databaseService.getCampaignMessages(
      widget.campaign['id'],
      limit: _pageSize,
      offset: _messages.length,
      statusFilter: _selectedFilter,
    );

    if (mounted) {
      setState(() {
        _messages.addAll(newMessages);
        _hasMore = newMessages.length >= _pageSize;
        _isLoadingMore = false;
      });
    }
  }

  void _setFilter(String? filter) {
    if (_selectedFilter == filter) {
      filter = null; // Toggle off
    }
    setState(() {
      _selectedFilter = filter;
      _messages.clear();
      _hasMore = true;
    });
    _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.campaign['subject'] ?? 'Sans titre',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Info grid
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _InfoItem(label: 'Statut', value: widget.campaign['status'] == 'completed' ? 'Termine' : 'En cours')),
                    Expanded(child: _InfoItem(label: 'Envoye par', value: widget.campaign['sender_username'] ?? 'Inconnu')),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _InfoItem(label: 'Cree le', value: _formatDate(widget.campaign['created_at']))),
                    Expanded(child: _InfoItem(label: 'Termine le', value: _formatDate(widget.campaign['completed_at']))),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Stats (clickable filters)
          Row(
            children: [
              _FilterableStatBox(
                label: 'Total',
                value: _totalCount.toString(),
                color: Colors.blue,
                isSelected: _selectedFilter == null,
                onTap: () => _setFilter(null),
              ),
              _FilterableStatBox(
                label: 'Attente',
                value: _pendingCount.toString(),
                color: Colors.orange,
                isSelected: _selectedFilter == 'pending',
                onTap: () => _setFilter('pending'),
              ),
              _FilterableStatBox(
                label: 'Envoyes',
                value: _sentCount.toString(),
                color: Colors.blue,
                isSelected: _selectedFilter == 'sent',
                onTap: () => _setFilter('sent'),
              ),
              _FilterableStatBox(
                label: 'Livres',
                value: _deliveredCount.toString(),
                color: Colors.green,
                isSelected: _selectedFilter == 'delivered',
                onTap: () => _setFilter('delivered'),
              ),
              _FilterableStatBox(
                label: 'Echecs',
                value: _failedCount.toString(),
                color: Colors.red,
                isSelected: _selectedFilter == 'failed',
                onTap: () => _setFilter('failed'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Template complet
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Template complet',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.campaign['template'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Text(
                'Messages',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              if (_selectedFilter != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_messages.length}',
                        style: TextStyle(fontSize: 12, color: Colors.blue[800], fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () => _setFilter(null),
                        child: Icon(Icons.close, size: 14, color: Colors.blue[800]),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Text(
                          'Aucun message',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      )
                    : ListView.builder(
                        controller: widget.scrollController,
                        itemCount: _messages.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _messages.length) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _MessageItem(message: _messages[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '-';
    }
  }
}

class _FilterableStatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterableStatBox({
    required this.label,
    required this.value,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color : color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: isSelected ? Border.all(color: color, width: 2) : null,
          ),
          child: Column(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : color,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.white.withOpacity(0.9) : color.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageItem extends StatelessWidget {
  final Map<String, dynamic> message;

  const _MessageItem({required this.message});

  @override
  Widget build(BuildContext context) {
    final status = message['status'] as String? ?? 'pending';

    IconData icon;
    Color color;

    switch (status) {
      case 'delivered':
        icon = Icons.done_all;
        color = Colors.green;
        break;
      case 'sent':
        icon = Icons.done;
        color = Colors.blue;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = Colors.red;
        break;
      default:
        icon = Icons.schedule;
        color = Colors.orange;
    }

    return InkWell(
      onTap: () => _showMessageDetails(context, status, color),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message['address'] ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            Text(
              _getStatusLabel(status),
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _showMessageDetails(BuildContext context, String status, Color statusColor) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.message, size: 24),
            const SizedBox(width: 12),
            const Expanded(child: Text('Details du message')),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow(
                icon: Icons.person,
                label: 'Destinataire',
                value: message['address'] ?? '-',
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.info_outline,
                label: 'Statut',
                value: _getStatusLabel(status),
                valueColor: statusColor,
              ),
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.access_time,
                label: 'Date d\'envoi',
                value: _formatDate(message['sent_at']),
              ),
              if (message['error_message'] != null && message['error_message'].toString().isNotEmpty) ...[
                const SizedBox(height: 12),
                _DetailRow(
                  icon: Icons.error_outline,
                  label: 'Erreur',
                  value: message['error_message'].toString(),
                  valueColor: Colors.red,
                ),
              ],
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Contenu du message',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message['body'] ?? '-',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '-';
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'delivered':
        return 'Livre';
      case 'sent':
        return 'Envoye';
      case 'failed':
        return 'Echec';
      default:
        return 'Attente';
    }
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
