// lib/widgets/manage_payment_accounts_dialog.dart

import 'package:flutter/material.dart';
import '../models/payment_account_model.dart';
import '../services/firestore_service.dart';

class ManagePaymentAccountsDialog extends StatefulWidget {
  const ManagePaymentAccountsDialog({super.key});

  @override
  State<ManagePaymentAccountsDialog> createState() => _ManagePaymentAccountsDialogState();
}

class _ManagePaymentAccountsDialogState extends State<ManagePaymentAccountsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _nameController = TextEditingController();

  // Função para popular automaticamente caso esteja vazio
  Future<void> _checkAndSeedDefaults(List<PaymentAccount> accounts) async {
    if (accounts.isEmpty) {
      final defaults = ["Cristiano", "Cleiton", "Osmildo", "Nota"];
      for (var name in defaults) {
        await _firestoreService.addPaymentAccount(name);
      }
    }
  }

  void _addAccount() async {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await _firestoreService.addPaymentAccount(name);
      _nameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Contas de Recebimento'),
      content: SizedBox(
        width: 400,
        height: 400,
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Nova Conta (Ex: Outro)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addAccount,
                  child: const Text('Adicionar'),
                ),
              ],
            ),
            const Divider(height: 30),
            Expanded(
              child: StreamBuilder<List<PaymentAccount>>(
                stream: _firestoreService.getPaymentAccountsStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                  
                  final accounts = snapshot.data!;
                  
                  // Se estiver vazio, popula automaticamente na primeira abertura
                  if (accounts.isEmpty) {
                    _checkAndSeedDefaults(accounts);
                    return const Center(child: CircularProgressIndicator());
                  }

                  return ListView.builder(
                    itemCount: accounts.length,
                    itemBuilder: (context, index) {
                      final account = accounts[index];
                      return ListTile(
                        title: Text(account.name, style: TextStyle(
                          decoration: account.isActive ? null : TextDecoration.lineThrough,
                          color: account.isActive ? Colors.black : Colors.grey,
                        )),
                        trailing: Switch(
                          value: account.isActive,
                          activeColor: Colors.green,
                          onChanged: (value) {
                            _firestoreService.togglePaymentAccountStatus(account.id, account.isActive);
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar')),
      ],
    );
  }
}