// lib/screens/mobile_dashboard_screen.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../models/order_model.dart';
import '../models/expense_model.dart';
import '../services/firestore_service.dart';

class MobileDashboardScreen extends StatefulWidget {
  const MobileDashboardScreen({super.key});

  @override
  State<MobileDashboardScreen> createState() => _MobileDashboardScreenState();
}

class _MobileDashboardScreenState extends State<MobileDashboardScreen> {
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
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            appBarTheme: Theme.of(context).appBarTheme.copyWith(
              backgroundColor: Theme.of(context).colorScheme.inversePrimary,
            )
          ),
          child: child!,
        );
      }
    );

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

    return StreamBuilder<List<dynamic>>(
      stream: Rx.combineLatest3( // <-- AGORA USAMOS combineLatest3
        _firestoreService.getOperationalOrdersStream(),
        _firestoreService.getDashboardStream(_startDate, _endDate),
        _firestoreService.getFinalizedOrdersStream(_startDate, _endDate), // <-- STREAM DE PEDIDOS FINALIZADOS
        (List<Order> opOrders, Map<String, dynamic> finData, List<Order> finOrders) => [opOrders, finData, finOrders]
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          debugPrint("ERRO NA DASHBOARD: ${snapshot.error}");
          return const Center(child: Text('Erro ao carregar dados. Verifique os índices do Firestore.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('Carregando...'));
        }

        final List<Order> operationalOrders = snapshot.data![0];
        final Map<String, dynamic> financialData = snapshot.data![1];
        final List<Order> finalizedOrdersForRevenue = snapshot.data![2]; // <-- DADOS PARA FATURAMENTO
        
        final List<Order> ordersForCashflow = financialData['orders'];
        final List<Expense> expenses = financialData['expenses'];

        // Cálculos Operacionais
        final quotesCount = operationalOrders.where((o) => o.status == OrderStatus.cotacao).length;
        final pendingPaymentCount = operationalOrders.where((o) => o.status == OrderStatus.pedido).length;
        final inProductionCount = operationalOrders.where((o) => o.status == OrderStatus.emFabricacao).length;
        final readyForDeliveryCount = operationalOrders.where((o) => o.status == OrderStatus.aguardandoEntrega).length;

        // Cálculos Financeiros
        final double totalRevenue = finalizedOrdersForRevenue.fold(0.0, (sum, order) => sum + order.finalAmount);
        
        final Map<String, double> finalizedRevenueByRecipient = {};
        for (final order in finalizedOrdersForRevenue) {
          for (final payment in order.paymentDistributions) {
            finalizedRevenueByRecipient.update(payment.recipient, (value) => value + payment.amount, ifAbsent: () => payment.amount);
          }
        }
        
        final Map<String, double> cashInflowByRecipient = {};
        final validOrdersForCashflow = ordersForCashflow.where((o) => o.status != OrderStatus.cancelado && o.status != OrderStatus.cotacao && o.status != OrderStatus.pedido).toList();
        for (final order in validOrdersForCashflow) {
          for (final payment in order.paymentDistributions) {
            cashInflowByRecipient.update(payment.recipient, (value) => value + payment.amount, ifAbsent: () => payment.amount);
          }
        }
        final double totalCashInflow = cashInflowByRecipient.values.fold(0.0, (sum, amount) => sum + amount);
        final double totalExpenses = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
        final double balance = totalRevenue - totalExpenses;

        return ListView(
          padding: const EdgeInsets.all(12.0),
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today, size: 18),
              label: Text('${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}'),
              onPressed: _selectDateRange,
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
            const SizedBox(height: 16),
            
            const Text('Visão Operacional', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.5,
              children: [
                _buildCompactStatusCard(title: 'Cotações', count: quotesCount, icon: Icons.request_quote, color: Colors.blueGrey),
                _buildCompactStatusCard(title: 'Aguard. Sinal', count: pendingPaymentCount, icon: Icons.hourglass_top, color: Colors.orange),
                _buildCompactStatusCard(title: 'Em Produção', count: inProductionCount, icon: Icons.precision_manufacturing, color: Colors.blue),
                _buildCompactStatusCard(title: 'Aguard. Entrega', count: readyForDeliveryCount, icon: Icons.inventory_2, color: Colors.purple),
              ],
            ),

            const SizedBox(height: 24),
            const Text('Resumo Financeiro', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            _buildMobileSummaryCard(title: 'Faturamento (Finalizados)', value: currencyFormatter.format(totalRevenue), icon: Icons.check_circle, color: Colors.green),
            _buildMobileSummaryCard(title: 'Entradas (Recebimentos)', value: currencyFormatter.format(totalCashInflow), icon: Icons.attach_money, color: Colors.blueAccent),
            _buildMobileSummaryCard(title: 'Saídas (Gastos)', value: currencyFormatter.format(totalExpenses), icon: Icons.trending_down, color: Colors.red),
            _buildMobileSummaryCard(title: 'Balanço', value: currencyFormatter.format(balance), icon: Icons.account_balance_wallet, color: balance >= 0 ? Colors.teal : Colors.deepOrange),
          
            // =================================================================
            // CARTÕES DE DISTRIBUIÇÃO ADICIONADOS AQUI
            // =================================================================
            const Divider(height: 32),

            if (cashInflowByRecipient.isNotEmpty)
              _buildDistributionCard(
                title: 'Valores Recebidos por Conta',
                distributionMap: cashInflowByRecipient,
                currencyFormatter: currencyFormatter,
                icon: Icons.login,
                color: Colors.blueAccent,
              ),

            if (finalizedRevenueByRecipient.isNotEmpty)
              _buildDistributionCard(
                title: 'Faturamento por Conta (Finalizados)',
                distributionMap: finalizedRevenueByRecipient,
                currencyFormatter: currencyFormatter,
                icon: Icons.assessment,
                color: Colors.green,
              ),

            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  Widget _buildCompactStatusCard({required String title, required int count, required IconData icon, required Color color}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const Spacer(),
            Text(count.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(title, style: TextStyle(color: Colors.grey[700], fontSize: 12), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileSummaryCard({required String title, required String value, required IconData icon, required Color color}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        subtitle: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)),
      ),
    );
  }

  // =================================================================
  // FUNÇÃO DE DISTRIBUIÇÃO ADICIONADA AQUI (COPIADA DO DESKTOP)
  // =================================================================
  Widget _buildDistributionCard({
    required String title,
    required Map<String, double> distributionMap,
    required NumberFormat currencyFormatter,
    required IconData icon,
    required Color color,
  }) {
    final sortedEntries = distributionMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16), // Mudei para 'bottom' para espaçamento
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)), // Usei titleSmall
              ],
            ),
            const Divider(),
            ...sortedEntries.map((entry) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact, // Deixa mais compacto
                leading: Icon(Icons.person_outline, color: Colors.grey.shade600, size: 20),
                title: Text(entry.key, style: const TextStyle(fontSize: 14)),
                trailing: Text(
                  currencyFormatter.format(entry.value),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}