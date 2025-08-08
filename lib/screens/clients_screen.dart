// lib/screens/clients_screen.dart

import 'package:flutter/material.dart';
import '../models/client_model.dart';
import '../services/firestore_service.dart';
import '../widgets/client_dialog.dart';
import 'client_order_history_screen.dart'; // <-- IMPORTA A NOVA TELA

class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    void confirmDelete(Client client) async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza que deseja excluir ${client.name}?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Não')),
            TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sim', style: TextStyle(color: Colors.red))),
          ],
        ),
      );
      if (confirm == true) {
        await firestoreService.deleteClient(client.id!);
      }
    }

    return StreamBuilder<List<Client>>(
      stream: firestoreService.getClientsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Erro: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Nenhum cliente cadastrado.'));
        }

        final clients = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            DataTable(
              columns: const [
                DataColumn(label: Text('Nome', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Telefone', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: clients.map((client) {
                return DataRow(cells: [
                  DataCell(Text(client.name)),
                  DataCell(Text(client.phone)),
                  DataCell(Text(client.email ?? '-')),
                  DataCell(Row(
                    children: [
                      // ===== BOTÃO DE HISTÓRICO ADICIONADO =====
                      IconButton(
                        icon: const Icon(Icons.history, color: Colors.teal),
                        tooltip: 'Ver Histórico de Pedidos',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ClientOrderHistoryScreen(client: client),
                            ),
                          );
                        },
                      ),
                      // ===========================================
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        tooltip: 'Editar',
                        onPressed: () async {
                          final result = await showDialog<Client>(
                            context: context,
                            builder: (context) => ClientDialog(client: client),
                          );
                          if (result != null) {
                              await firestoreService.updateClient(result);
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'Excluir',
                        onPressed: () => confirmDelete(client),
                      ),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}