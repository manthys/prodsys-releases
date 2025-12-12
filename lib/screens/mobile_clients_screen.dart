// lib/screens/mobile_clients_screen.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client_model.dart';
import '../services/firestore_service.dart';
import 'mobile_client_form_screen.dart'; // Importa a nova tela de formulário

class MobileClientsScreen extends StatefulWidget {
  final bool isPickerMode;

  const MobileClientsScreen({super.key, this.isPickerMode = false});

  @override
  State<MobileClientsScreen> createState() => _MobileClientsScreenState();
}

class _MobileClientsScreenState extends State<MobileClientsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Navega para o formulário e espera um resultado (o cliente salvo)
  void _navigateToClientForm({Client? client}) async {
    final result = await Navigator.of(context).push<Client>(
      MaterialPageRoute(
        builder: (context) => MobileClientFormScreen(client: client),
      ),
    );

    // Se estiver em modo de seleção e um cliente for salvo/retornado,
    // fecha a tela de seleção e retorna o cliente para o formulário de pedido.
    if (widget.isPickerMode && result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  Future<void> _launchPhone(String phoneNumber) async {
    final uri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }
  
  // =================================================================
  // NOVA FUNÇÃO PARA CONFIRMAR A EXCLUSÃO
  // =================================================================
  void _confirmDelete(Client client) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja excluir o cliente "${client.name}"?\n\nEsta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Não')),
          ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Sim, Excluir', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    
    if (confirm == true) {
      try {
        await _firestoreService.deleteClient(client.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cliente excluído com sucesso.'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir cliente: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Adiciona um AppBar SÓ SE estiver em modo de seleção
      appBar: widget.isPickerMode ? AppBar(
        title: const Text('Selecionar Cliente'),
      ) : null,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar por nome ou telefone',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => _searchController.clear(),
                    )
                  : null,
              ),
            ),
          ),
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
                         client.phone.contains(query);
                }).toList();

                if (filteredClients.isEmpty) {
                  return const Center(child: Text('Nenhum cliente encontrado.'));
                }
                
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80.0),
                  itemCount: filteredClients.length,
                  itemBuilder: (context, index) {
                    final client = filteredClients[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
                      child: ListTile(
                        leading: CircleAvatar(child: Text(client.name.substring(0, 1).toUpperCase())),
                        title: Text(client.name),
                        subtitle: Text(client.phone),
                        trailing: widget.isPickerMode ? null : IconButton( // Esconde o botão de ligar no modo de seleção
                          icon: Icon(Icons.phone, color: Colors.green.shade700),
                          onPressed: () => _launchPhone(client.phone),
                        ),
                        onTap: () {
                          if (widget.isPickerMode) {
                            // Se está selecionando, retorna o cliente
                            Navigator.of(context).pop(client);
                          } else {
                            // Se está na aba normal, vai para editar
                            _navigateToClientForm(client: client);
                          }
                        },
                        onLongPress: widget.isPickerMode ? null : () => _confirmDelete(client), // Desativa exclusão no modo de seleção
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      // Mostra o FAB apenas se NÃO estiver em modo de seleção
      floatingActionButton: widget.isPickerMode ? null : FloatingActionButton(
        onPressed: () => _navigateToClientForm(),
        tooltip: 'Novo Cliente',
        child: const Icon(Icons.add),
      ),
    );
  }
}