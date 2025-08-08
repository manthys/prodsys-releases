// lib/screens/production_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/mold_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';
import '../services/firestore_service.dart';
import '../services/production_scheduler.dart';

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});

  @override
  _ProductionScreenState createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ProductionScheduler _scheduler = ProductionScheduler();
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _setInitialDate();
  }
  
  void _setInitialDate() {
    DateTime now = DateTime.now();
    DateTime initialDate = now;
    if (initialDate.weekday == DateTime.saturday) {
      initialDate = initialDate.add(const Duration(days: 2));
    } else if (initialDate.weekday == DateTime.sunday) {
      initialDate = initialDate.add(const Duration(days: 1));
    } else {
       initialDate = initialDate.add(const Duration(days: 1));
       if (initialDate.weekday == DateTime.saturday) initialDate = initialDate.add(const Duration(days: 2));
       if (initialDate.weekday == DateTime.sunday) initialDate = initialDate.add(const Duration(days: 1));
    }
    _selectedDate = DateTime(initialDate.year, initialDate.month, initialDate.day);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
      selectableDayPredicate: (DateTime day) => day.weekday != DateTime.saturday && day.weekday != DateTime.sunday,
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  void _showLaunchProductionDialog(ProductionPlanItem planItem) {
    final qtyController = TextEditingController(text: planItem.quantityToProduce.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Lançar Produção de ${planItem.productName}'),
          content: TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Quantidade Realmente Produzida'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                int qtyProduced = int.tryParse(qtyController.text) ?? 0;
                if (qtyProduced <= 0) return;
                if (qtyProduced > planItem.quantityToProduce) {
                  qtyProduced = planItem.quantityToProduce;
                }
                
                final itemsToLaunch = planItem.sourceItems.take(qtyProduced).toList();
                
                await _firestoreService.launchProductionRun(itemsToLaunch);
                
                if (planItem.sourceItems.isNotEmpty && planItem.sourceItems.first.orderId != null) {
                  await _firestoreService.checkAndUpdateOrderStatusAfterProduction(planItem.sourceItems.first.orderId!);
                }
                
                if (mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                   SnackBar(content: Text('$qtyProduced x ${planItem.productName} lançado(s) em estoque!'), backgroundColor: Colors.green),
                  );
                  setState(() {});
                }
              },
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('dd/MM/yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Text('Produção de $formattedDate'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Selecionar Data de Produção',
            onPressed: () => _selectDate(context),
          ),
        ],
      ),
      body: StreamBuilder<Map<String, dynamic>>(
        stream: _firestoreService.getDataForProductionPlanStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || (snapshot.data!['pendingItems'] as List).isEmpty) {
            return const Center(child: Text('Nenhum item pendente para produção.'));
          }

          final List<Mold> molds = snapshot.data!['molds'];
          final List<StockItem> allPendingItems = snapshot.data!['pendingItems'];
          final Map<String, Product> productCatalog = snapshot.data!['products'];

          final fullPlan = _scheduler.scheduleProduction(
            allPendingItems: allPendingItems,
            allMolds: molds,
            productCatalog: productCatalog,
          );
          
          final productionPlanForSelectedDate = fullPlan[_selectedDate] ?? [];

          if (productionPlanForSelectedDate.isEmpty) {
            return Center(
              child: Text(
                'Nenhuma produção agendada para $formattedDate.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: productionPlanForSelectedDate.length,
            itemBuilder: (context, index) {
              final planItem = productionPlanForSelectedDate[index];
              final isLate = planItem.deliveryDeadline.isBefore(DateTime.now());

              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 12),
                color: isLate ? Colors.red.shade50 : null,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  leading: CircleAvatar(
                    radius: 28,
                    backgroundColor: isLate ? Colors.red : Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    child: Text(
                      planItem.quantityToProduce.toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  title: Text(
                    '${planItem.sku} - ${planItem.productName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'Cliente: ${planItem.clientName} | Pedido: #${planItem.orderId}\n'
                    'Total do Lote: ${planItem.totalPendingForGroup} | Logo: ${planItem.logoType}\n'
                    'Prazo Final: ${DateFormat('dd/MM/yy').format(planItem.deliveryDeadline)}',
                    style: TextStyle(color: isLate ? Colors.red.shade900 : null),
                  ),
                  isThreeLine: true,
                  trailing: ElevatedButton(
                    onPressed: () => _showLaunchProductionDialog(planItem),
                    child: const Text('Lançar'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}