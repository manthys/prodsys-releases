// lib/screens/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../models/order_model.dart';
import '../models/expense_model.dart';
import '../services/firestore_service.dart';
import 'order_details_screen.dart'; // Import necessário

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

    if (!mounted) return;

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
    }
  }

  // ##### NOVA FUNÇÃO PARA MOSTRAR OS PEDIDOS FINALIZADOS #####
   void _showFinalizedOrdersDialog(List<Order> finalizedOrders, DateTime startDate, DateTime endDate) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Pedidos Finalizados (${DateFormat('dd/MM/yy').format(startDate)} - ${DateFormat('dd/MM/yy').format(endDate)})'),
          content: SizedBox(
            width: 600,
            height: 400,
            child: ListView.builder(
              itemCount: finalizedOrders.length,
              itemBuilder: (context, index) {
                final order = finalizedOrders[index];
                final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? 'N/A';
                // USA A NOVA DATA DE FINALIZAÇÃO CORRETA
                final dateToShow = order.finalizationDate ?? order.creationDate;
                return Card(
                  child: ListTile(
                    title: Text('${order.clientName} - Pedido #$orderIdShort'),
                    subtitle: Text('Finalizado em: ${DateFormat('dd/MM/yyyy').format(dateToShow.toDate())}'),
                    trailing: Text(NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(order.finalAmount)),
                    onTap: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => OrderDetailsScreen(order: order),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

   @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    return Scaffold(
      appBar: AppBar(
        // =================================================================
        // CORREÇÃO DO OVERFLOW APLICADA AQUI (REMOVENDO O 'Flexible')
        // =================================================================
        title: Text(
          'Dashboard: ${DateFormat('dd/MM/yy').format(_startDate)} - ${DateFormat('dd/MM/yy').format(_endDate)}',
          overflow: TextOverflow.ellipsis, // Esta propriedade já previne o overflow do texto
        ),
        actions: [IconButton(icon: const Icon(Icons.calendar_today), onPressed: _selectDateRange)],
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<List<dynamic>>(
        stream: Rx.combineLatest3(
          _firestoreService.getOperationalOrdersStream(), 
          _firestoreService.getDashboardStream(_startDate, _endDate),
          _firestoreService.getFinalizedOrdersStream(_startDate, _endDate),
          (List<Order> opOrders, Map<String, dynamic> financialData, List<Order> finalizedOrders) => [opOrders, financialData, finalizedOrders]
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            debugPrint("ERRO NO STREAM DA DASHBOARD: ${snapshot.error}");
            return Center(child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Erro ao carregar dados. Verifique o console para mais detalhes (pode ser necessário criar um índice no Firestore).', textAlign: TextAlign.center),
            ));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Nenhum dado encontrado.'));
          }

          final List<Order> operationalOrders = snapshot.data![0];
          final Map<String, dynamic> financialData = snapshot.data![1];
          final List<Order> finalizedOrdersForRevenue = snapshot.data![2];

          final List<Order> ordersForCashflow = financialData['orders'];
          final List<Expense> expenses = financialData['expenses'];

          final quotesCount = operationalOrders.where((o) => o.status == OrderStatus.cotacao).length;
          final pendingPaymentCount = operationalOrders.where((o) => o.status == OrderStatus.pedido).length;
          final inProductionCount = operationalOrders.where((o) => o.status == OrderStatus.emFabricacao).length;
          final readyForDeliveryCount = operationalOrders.where((o) => o.status == OrderStatus.aguardandoEntrega).length;
          
          final double totalRevenue = finalizedOrdersForRevenue.fold(0.0, (sum, order) => sum + order.finalAmount);
          
          final Map<String, double> finalizedRevenueByRecipient = {};
          for (final order in finalizedOrdersForRevenue) {
            for (final payment in order.paymentDistributions) {
              finalizedRevenueByRecipient.update(
                payment.recipient,
                (value) => value + payment.amount,
                ifAbsent: () => payment.amount,
              );
            }
          }
          
          final Map<String, double> cashInflowByRecipient = {};
          final validOrdersForCashflow = ordersForCashflow.where((o) => 
              o.status != OrderStatus.cancelado && 
              o.status != OrderStatus.cotacao &&
              o.status != OrderStatus.pedido
          ).toList();

          for (final order in validOrdersForCashflow) {
            for (final payment in order.paymentDistributions) {
              cashInflowByRecipient.update(
                payment.recipient,
                (value) => value + payment.amount,
                ifAbsent: () => payment.amount,
              );
            }
          }
          final double totalCashInflow = cashInflowByRecipient.values.fold(0.0, (sum, amount) => sum + amount);

          final double totalExpenses = expenses.fold(0.0, (sum, expense) => sum + expense.amount);
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
              
              InkWell(
                onTap: () => _showFinalizedOrdersDialog(finalizedOrdersForRevenue, _startDate, _endDate),
                child: _buildSummaryCard(
                  title: 'Faturamento (Pedidos Finalizados)', 
                  value: currencyFormatter.format(totalRevenue), 
                  icon: Icons.check_circle, 
                  color: Colors.green
                ),
              ),

              _buildSummaryCard(title: 'Valores Recebidos (Entradas)', value: currencyFormatter.format(totalCashInflow), icon: Icons.attach_money, color: Colors.blueAccent),
              _buildSummaryCard(title: 'Total de Gastos (Saídas)', value: currencyFormatter.format(totalExpenses), icon: Icons.trending_down, color: Colors.red),
              _buildSummaryCard(title: 'Balanço (Faturamento - Gastos)', value: currencyFormatter.format(balance), icon: Icons.account_balance_wallet, color: balance >= 0 ? Colors.teal : Colors.deepOrange),
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
      margin: const EdgeInsets.only(top: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const Divider(),
            ...sortedEntries.map((entry) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(Icons.person_outline, color: Colors.grey.shade600),
                title: Text(entry.key),
                trailing: Text(
                  currencyFormatter.format(entry.value),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}