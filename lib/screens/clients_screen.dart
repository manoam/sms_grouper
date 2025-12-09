import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/websocket_server_service.dart';
import '../widgets/clients_list.dart';

class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PC connectés'),
        centerTitle: true,
      ),
      body: Consumer<WebSocketServerService>(
        builder: (context, wsService, _) {
          return ClientsList(connections: wsService.connections);
        },
      ),
    );
  }
}
