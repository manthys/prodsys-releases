// lib/screens/expenses_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense_model.dart';
import '../services/firestore_service.dart';
import '../widgets/expense_dialog.dart';

class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ');
    final dateFormatter = DateFormat('dd/MM/yyyy');

    void showExpenseDialog({Expense? expense}) async {
      final result = await showDialog<Expense>(
        context: context,
        builder: (context) => ExpenseDialog(expense: expense),
      );
      if (result != null) {
        if (expense == null) {
          await firestoreService.addExpense(result);
        } else {
          await firestoreService.updateExpense(result);
        }
      }
    }

    // NOVA FUNÇÃO PARA CONFIRMAR A EXCLUSÃO
    void confirmDelete(Expense expense) async {
      final bool? confirmar = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza que deseja excluir a despesa "${expense.description}"?'),
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

      if (confirmar == true) {
        await firestoreService.deleteExpense(expense.id!);
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Despesa excluída com sucesso.'), backgroundColor: Colors.orange),
          );
        }
      }
    }

    return Scaffold(
      body: StreamBuilder<List<Expense>>(
        stream: firestoreService.getExpensesStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Nenhuma despesa registrada.'));
          }

          final expenses = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 80), // Espaço para o botão flutuante
            itemCount: expenses.length,
            itemBuilder: (context, index) {
              final expense = expenses[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.money_off),
                  title: Text(expense.description),
                  subtitle: Text('${expense.category} - ${dateFormatter.format(expense.expenseDate.toDate())}'),
                  // ===== MUDANÇA AQUI =====
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        currencyFormatter.format(expense.amount), 
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        tooltip: 'Excluir Despesa',
                        onPressed: () => confirmDelete(expense),
                      )
                    ],
                  ),
                  onTap: () => showExpenseDialog(expense: expense),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showExpenseDialog(),
        child: const Icon(Icons.add),
        tooltip: 'Nova Despesa',
      ),
    );
  }
}