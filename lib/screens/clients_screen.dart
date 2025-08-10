// lib/screens/clients_screen.dart

import 'package:flutter/material.dart';
import '../models/client_model.dart';
import '../services/firestore_service.dart';
import '../widgets/client_dialog.dart';
import 'client_order_history_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      // Evita reconstruções desnecessárias se o texto não mudou
      if (_searchQuery != _searchController.text) {
        setState(() {
          _searchQuery = _searchController.text;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _confirmDelete(Client client) async {
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
      await _firestoreService.deleteClient(client.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A estrutura principal é uma Coluna
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 1. O CAMPO DE BUSCA FICA FORA DA LISTA QUE ATUALIZA
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar por nome, telefone ou CNPJ/CPF',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            
            // 2. A LISTA OCUPA O RESTO DA TELA
            Expanded(
              child: StreamBuilder<List<Client>>(
                stream: _firestoreService.getClientsStream(),
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

                  final allClients = snapshot.data!;
                  final filteredClients = allClients.where((client) {
                    final query = _searchQuery.toLowerCase();
                    return client.name.toLowerCase().contains(query) ||
                           client.phone.contains(query) ||
                           (client.cnpj ?? '').contains(query);
                  }).toList();
                  
                  if (filteredClients.isEmpty) {
                    return const Center(child: Text('Nenhum cliente encontrado para a sua busca.'));
                  }

                  // 3. O SizedBox força a DataTable a ocupar toda a largura
                  return SizedBox(
                    width: double.infinity,
                    child: SingleChildScrollView(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Nome', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Telefone', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Email', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: filteredClients.map((client) {
                          return DataRow(cells: [
                            DataCell(Text(client.name)),
                            DataCell(Text(client.phone)),
                            DataCell(Text(client.email ?? '-')),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
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
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  tooltip: 'Editar',
                                  onPressed: () async {
                                    final result = await showDialog<Client>(
                                      context: context,
                                      builder: (context) => ClientDialog(client: client),
                                    );
                                    if (result != null) {
                                        await _firestoreService.updateClient(result);
                                    }
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  tooltip: 'Excluir',
                                  onPressed: () => _confirmDelete(client),
                                ),
                              ],
                            )),
                          ]);
                        }).toList(),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}