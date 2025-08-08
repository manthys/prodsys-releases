// lib/screens/manage_users_screen.dart

import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../widgets/user_dialog.dart';

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});

  @override
  _ManageUsersScreenState createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen> {
  final AuthService _authService = AuthService();

  void _showAddUserDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const UserDialog(),
    );
    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Funcionário criado com sucesso!'), backgroundColor: Colors.green),
      );
    }
  }

  void _onActionSelected(String action, UserModel user) {
    switch (action) {
      case 'reset_password':
        _resetPassword(user);
        break;
      case 'toggle_role':
        _toggleRole(user);
        break;
      // NOVO CASO PARA EXCLUSÃO
      case 'delete_user':
        _deleteUser(user);
        break;
    }
  }

  void _resetPassword(UserModel user) async {
    final result = await _authService.sendPasswordResetEmail(user.email);
    if (mounted) {
      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email de redefinição enviado para ${user.email}'), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _toggleRole(UserModel user) async {
    final newRole = user.role == 'admin' ? 'employee' : 'admin';
    final newRoleName = newRole == 'admin' ? 'Administrador' : 'Funcionário';

    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Alteração'),
        content: Text('Deseja realmente alterar a função de ${user.email} para $newRoleName?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.updateUserRole(user.uid, newRole);
      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Função de ${user.email} atualizada para $newRoleName.'), backgroundColor: Colors.blue),
        );
      }
    }
  }

  // ===== NOVA FUNÇÃO PARA EXCLUIR USUÁRIO =====
  void _deleteUser(UserModel user) async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Exclusão'),
        content: Text('Tem certeza que deseja excluir o usuário ${user.email}? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sim, Excluir'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      final result = await _authService.deleteUser(user.uid);
      if (mounted) {
        if (result == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Usuário ${user.email} removido do sistema.'), backgroundColor: Colors.orange),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _authService.currentUser;

    return Scaffold(
      body: StreamBuilder<List<UserModel>>(
        stream: _authService.getUsersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar usuários: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Nenhum usuário encontrado.'));
          }

          final users = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final bool isAdmin = user.role == 'admin';
              final isCurrentUser = user.uid == currentUser?.uid;

              return Card(
                child: ListTile(
                  leading: Icon(
                    isAdmin ? Icons.admin_panel_settings : Icons.person,
                    color: isAdmin ? Colors.blue : Colors.grey,
                  ),
                  title: Text(user.email, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(isAdmin ? 'Administrador' : 'Funcionário'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) => _onActionSelected(value, user),
                    itemBuilder: (BuildContext context) {
                      return <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'reset_password',
                          child: Text('Redefinir Senha'),
                        ),
                        if (!isCurrentUser)
                          PopupMenuItem<String>(
                            value: 'toggle_role',
                            child: Text(isAdmin ? 'Tornar Funcionário' : 'Tornar Admin'),
                          ),
                        // SÓ MOSTRA A OPÇÃO DE EXCLUIR SE NÃO FOR O USUÁRIO ATUAL
                        if (!isCurrentUser)
                          const PopupMenuDivider(),
                        if (!isCurrentUser)
                          PopupMenuItem<String>(
                            value: 'delete_user',
                            child: Text('Excluir Usuário', style: TextStyle(color: Colors.red)),
                          ),
                      ];
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddUserDialog(context),
        tooltip: 'Novo Funcionário',
        child: const Icon(Icons.add),
      ),
    );
  }
}