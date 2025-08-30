// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart'; // Import necessário para combinar streams
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

    // ##### CORREÇÃO AQUI #####
    // Se a tela não estiver mais visível quando o usuário terminar de escolher a data, não fazemos nada.
    if (!mounted) return;

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard: ${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}'),
        actions: [IconButton(icon: const Icon(Icons.calendar_today), onPressed: _selectDateRange)],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<List<dynamic>>(
        stream: Rx.combineLatest2(
          _firestoreService.getOperationalOrdersStream(), 
          _firestoreService.getDashboardStream(_startDate, _endDate), 
          (List<Order> operationalOrders, Map<String, dynamic> financialData) => [operationalOrders, financialData]
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar dados: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Nenhum dado encontrado.'));
          }

          final List<Order> operationalOrders = snapshot.data![0];
          final Map<String, dynamic> financialData = snapshot.data![1];
          
          final List<Order> ordersForFinance = financialData['orders'];
          final List<Expense> expenses = financialData['expenses'];

          final quotesCount = operationalOrders.where((o) => o.status == OrderStatus.cotacao).length;
          final pendingPaymentCount = operationalOrders.where((o) => o.status == OrderStatus.pedido).length;
          final inProductionCount = operationalOrders.where((o) => o.status == OrderStatus.emFabricacao).length;
          final readyForDeliveryCount = operationalOrders.where((o) => o.status == OrderStatus.aguardandoEntrega).length;

          final finalizedOrders = ordersForFinance.where((order) => order.status == OrderStatus.finalizado).toList();
          final double totalRevenue = finalizedOrders.fold(0.0, (sum, order) => sum + order.finalAmount);
          final double totalExpenses = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
          final int validOrderCount = ordersForFinance.where((o) => o.status != OrderStatus.cotacao && o.status != OrderStatus.cancelado).length;
          final double balance = totalRevenue - totalExpenses;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              Text('Visão Operacional (Tempo Real)', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  _buildStatusCard(title: 'Cotações', count: quotesCount, icon: Icons.request_quote, color: Colors.blueGrey),
                  _buildStatusCard(title: 'Aguard. Sinal', count: pendingPaymentCount, icon: Icons.hourglass_top, color: Colors.orange),
                  _buildStatusCard(title: 'Em Fabricação', count: inProductionCount, icon: Icons.precision_manufacturing, color: Colors.blue),
                  _buildStatusCard(title: 'Aguard. Entrega', count: readyForDeliveryCount, icon: Icons.inventory_2, color: Colors.purple),
                ],
              ),
              const Divider(height: 32),
              
              Text('Resumo Financeiro (Período Selecionado)', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),

              _buildSummaryCard(title: 'Faturamento (Pedidos Finalizados)', value: currencyFormatter.format(totalRevenue), icon: Icons.trending_up, color: Colors.green),
              _buildSummaryCard(title: 'Total de Gastos', value: currencyFormatter.format(totalExpenses), icon: Icons.trending_down, color: Colors.red),
              _buildSummaryCard(title: 'Balanço (Lucro Bruto)', value: currencyFormatter.format(balance), icon: Icons.account_balance_wallet, color: balance >= 0 ? Colors.blue : Colors.deepOrange),
              _buildSummaryCard(title: 'Pedidos Válidos no Período', value: validOrderCount.toString(), icon: Icons.receipt_long, color: Colors.grey.shade700),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusCard({required String title, required int count, required IconData icon, required Color color}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 500 ? (constraints.maxWidth / 4) - 8 : (constraints.maxWidth / 2) - 8;

        return SizedBox(
          width: cardWidth,
          child: Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 32, color: color),
                  const SizedBox(height: 8),
                  Text(
                    count.toString(),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    title,
                    style: const TextStyle(color: Colors.grey, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      }
    );
  }

  Widget _buildSummaryCard({required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(top: 16),
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