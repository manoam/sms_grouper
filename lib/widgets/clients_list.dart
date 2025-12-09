import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/client_connection.dart';

class ClientsList extends StatelessWidget {
  final List<ClientConnection> connections;

  const ClientsList({super.key, required this.connections});

  @override
  Widget build(BuildContext context) {
    final activeConnections = connections.where((c) => c.isActive).toList();

    if (activeConnections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.computer_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Aucun PC connecté',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Les ordinateurs connectés apparaîtront ici',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (activeConnections.isNotEmpty) ...[
          _buildSectionHeader(
            'PC connectés',
            activeConnections.length,
            Colors.green,
          ),
          ...activeConnections.map((c) => _buildClientTile(c, true)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientTile(ClientConnection connection, bool isActive) {
    final dateFormat = DateFormat('HH:mm:ss');

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green : Colors.grey,
          child: Icon(
            isActive ? Icons.computer : Icons.computer_outlined,
            color: Colors.white,
          ),
        ),
        title: Text(
          connection.remoteAddress,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ID: ${connection.id.substring(0, 8)}...',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              'Connecté à ${dateFormat.format(connection.connectedAt)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? Colors.green.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? 'Actif' : 'Déconnecté',
                style: TextStyle(
                  fontSize: 11,
                  color: isActive ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              connection.formattedDuration,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }
}
