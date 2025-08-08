// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_model.dart';
import '../models/expense_model.dart';
import '../services/firestore_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month + 1, 0, 23, 59, 59);

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        // Garante que a data final inclua o dia inteiro
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Balanço: ${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}'),
        actions: [IconButton(icon: const Icon(Icons.calendar_today), onPressed: _selectDateRange)],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        // O Stream agora é criado aqui, usando as datas do estado
        stream: _firestoreService.getDashboardStream(_startDate, _endDate),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            // O erro do índice (se necessário) aparecerá no console, não aqui
            return Center(child: Text('Erro ao carregar dados: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Nenhum dado encontrado para o período.'));
          }

          final List<Order> orders = snapshot.data!['orders'];
          final List<Expense> expenses = snapshot.data!['expenses'];

          // Cálculos feitos em tempo real
          final double totalRevenue = orders.fold(0.0, (sum, order) => sum + order.finalAmount);
          final double totalExpenses = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
          final int orderCount = orders.length;
          final double balance = totalRevenue - totalExpenses;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildSummaryCard(title: 'Faturamento Total', value: currencyFormatter.format(totalRevenue), icon: Icons.trending_up, color: Colors.green),
              _buildSummaryCard(title: 'Total de Gastos', value: currencyFormatter.format(totalExpenses), icon: Icons.trending_down, color: Colors.red),
              _buildSummaryCard(title: 'Balanço (Lucro Bruto)', value: currencyFormatter.format(balance), icon: Icons.account_balance_wallet, color: balance >= 0 ? Colors.blue : Colors.deepOrange),
              _buildSummaryCard(title: 'Pedidos Válidos no Período', value: orderCount.toString(), icon: Icons.receipt_long, color: Colors.grey.shade700),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 40, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                  Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}