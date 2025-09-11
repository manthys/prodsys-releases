// lib/screens/production_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import '../models/mold_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';
import '../services/firestore_service.dart';
import '../services/production_scheduler.dart';

class StockOpportunity {
  final Mold mold;
  final List<Product> availableProducts;
  StockOpportunity({required this.mold, required this.availableProducts});
}

class ProductionScreen extends StatefulWidget {
  const ProductionScreen({super.key});

  @override
  _ProductionScreenState createState() => _ProductionScreenState();
}

class _ProductionScreenState extends State<ProductionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ProductionScheduler _scheduler = ProductionScheduler();
  late DateTime _selectedDate;
  Order? _selectedOrderFilter;
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _setInitialDate();
    _searchController.addListener(() {
      if(mounted) setState(() => _searchTerm = _searchController.text);
    });
  }
 
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setInitialDate() {
    DateTime now = DateTime.now();
    DateTime initialDate = now;
    if (now.weekday == DateTime.saturday || now.weekday == DateTime.sunday) {
        initialDate = _getNextWorkday(now);
    } else {
      initialDate = DateTime(now.year, now.month, now.day);
    }
    _selectedDate = initialDate;
  }

  DateTime _getNextWorkday(DateTime date) {
    DateTime nextDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
    while (nextDay.weekday == DateTime.saturday || nextDay.weekday == DateTime.sunday) {
      nextDay = nextDay.add(const Duration(days: 1));
    }
    return nextDay;
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
        _selectedOrderFilter = null;
        _searchController.clear();
      });
    }
  }

  Future<void> _selectOrderFilter(BuildContext context, List<StockItem> allPendingItems) async {
    final ordersWithPendingItems = allPendingItems
      .where((item) => item.orderId != null)
      .map((item) => item.orderId!)
      .toSet()
      .toList();

    if (ordersWithPendingItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum pedido com itens pendentes para filtrar.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    
    List<Order> candidateOrders = [];
    for(String orderId in ordersWithPendingItems) {
      final order = await _firestoreService.getOrderById(orderId);
      if (order != null) {
        candidateOrders.add(order);
      }
    }
    
    if (!mounted) return;

    final Order? picked = await showDialog<Order>(
      context: context,
      builder: (context) => _OrderFilterDialog(candidateOrders: candidateOrders),
    );

    if (picked != null) {
      setState(() {
        _selectedOrderFilter = picked;
        _searchController.clear();
      });
    }
  }

  void _showProduceForStockDialog(StockOpportunity opportunity) async {
    final Product? selectedProduct = await showDialog<Product>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Produzir para Estoque'),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('A forma "${opportunity.mold.name}" está ociosa. Qual produto você deseja fabricar?', style: Theme.of(context).textTheme.bodyLarge),
                  const Divider(height: 24),
                  ...opportunity.availableProducts.map((product) {
                    final String logoTypeLabel = product.sku.toLowerCase().contains('cleiton premoldados') ? 'Logo da Empresa' : 'Nenhum';
                    return ListTile(
                      title: Text(product.name),
                      subtitle: Text('SKU: ${product.sku} | Tipo: $logoTypeLabel'),
                      onTap: () => Navigator.of(context).pop(product),
                    );
                  }),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))],
        );
      },
    );

    if (selectedProduct != null) {
      final String logoTypeForDb = selectedProduct.sku.toLowerCase().contains('cleiton premoldados') ? 'Própria' : 'Nenhum';
      final tempPlanItem = ProductionPlanItem(
        productId: selectedProduct.id!,
        productName: selectedProduct.name,
        sku: selectedProduct.sku,
        logoType: logoTypeForDb,
        quantityToProduce: opportunity.mold.quantityAvailable,
        clientName: 'Estoque Interno',
        orderId: 'Estoque',
        deliveryDeadline: DateTime.now().add(const Duration(days: 90)),
        totalPendingForGroup: 0,
        sourceItems: [],
      );
      _showLaunchProductionDialog(tempPlanItem);
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
            decoration: const InputDecoration(labelText: 'Quantidade a Produzir'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () async {
                int qtyProduced = int.tryParse(qtyController.text) ?? 0;
                if (qtyProduced <= 0) return;
                
                if (planItem.sourceItems.isNotEmpty && qtyProduced > planItem.quantityToProduce) {
                  qtyProduced = planItem.quantityToProduce;
                }
                
                if (planItem.sourceItems.isEmpty) {
                  final product = (await _firestoreService.getProductById(planItem.productId))!;
                  await _firestoreService.addStockItemsToProductionQueue(
                    product: product, 
                    quantity: qtyProduced, 
                    logoType: planItem.logoType
                  );
                } else {
                  final itemsToLaunch = planItem.sourceItems.take(qtyProduced).toList();
                  await _firestoreService.launchProductionRun(itemsToLaunch);
                  if (planItem.sourceItems.first.orderId != null) {
                    // ##### CORREÇÃO APLICADA AQUI #####
                    // Chamando a nova função unificada e correta
                    await _firestoreService.checkIfOrderIsFullyCompleted(planItem.sourceItems.first.orderId!);
                  }
                }
                
                if (mounted) {
                  Navigator.of(context).pop();
                  final message = planItem.sourceItems.isEmpty
                    ? '$qtyProduced x ${planItem.productName} enviado(s) para a fila de produção!'
                    : '$qtyProduced x ${planItem.productName} lançado(s) em estoque!';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message), backgroundColor: Colors.green),
                  );
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
    final formattedDate = DateFormat('dd/MM/yyyy, EEEE', 'pt_BR').format(_selectedDate);
    final title = _searchTerm.isNotEmpty
      ? 'Buscando por "$_searchTerm"'
      : _selectedOrderFilter == null
          ? 'Produção de $formattedDate'
          : 'Produção para Pedido #${_selectedOrderFilter!.id!.substring(0, 6).toUpperCase()}';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_selectedOrderFilter != null)
            IconButton(
              icon: const Icon(Icons.filter_alt_off),
              tooltip: 'Limpar Filtro de Pedido',
              onPressed: () => setState(() => _selectedOrderFilter = null),
            ),
          StreamBuilder<Map<String, dynamic>>(
            stream: _firestoreService.getDataForProductionPlanStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              final List<StockItem> allPendingItems = snapshot.data!['pendingItems'];
              return IconButton(
                icon: const Icon(Icons.filter_alt),
                tooltip: 'Filtrar por Pedido',
                onPressed: () => _selectOrderFilter(context, allPendingItems),
              );
            }
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Selecionar Data de Produção',
            onPressed: () => _selectDate(context),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar produto em toda a produção...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: EdgeInsets.zero,
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
        ),
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
          if (!snapshot.hasData) {
            return const Center(child: Text('Carregando dados...'));
          }

          final List<Mold> allMolds = snapshot.data!['molds'];
          final List<StockItem> allPendingItems = snapshot.data!['pendingItems'];
          final Map<String, Product> productCatalog = snapshot.data!['products'];
          
          final fullPlan = _scheduler.scheduleProduction(
            allPendingItems: allPendingItems,
            allMolds: allMolds,
            productCatalog: productCatalog,
          );

          List<Widget> listWidgets = [];
          
          if (_searchTerm.isNotEmpty) {
            final allPlannedItems = fullPlan.entries
                .expand((entry) => entry.value.map((item) => MapEntry(entry.key, item)))
                .toList();

            final searchResults = allPlannedItems.where((entry) {
              final item = entry.value;
              final query = _searchTerm.toLowerCase();
              return item.productName.toLowerCase().contains(query) ||
                     item.sku.toLowerCase().contains(query);
            }).toList();

            final groupedSearchResults = groupBy(searchResults, (entry) => entry.key);
            final sortedDates = groupedSearchResults.keys.toList()..sort();

            for (var date in sortedDates) {
               listWidgets.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
                  child: Text(
                    DateFormat('dd/MM/yyyy, EEEE', 'pt_BR').format(date),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                )
              );
              listWidgets.addAll(groupedSearchResults[date]!.map((entry) => _buildProductionCard(entry.value)));
            }
          } else if (_selectedOrderFilter != null) {
              final Map<DateTime, List<ProductionPlanItem>> planToShow = {};
              fullPlan.forEach((date, items) {
                final filteredItems = items.where((item) => item.sourceItems.first.orderId == _selectedOrderFilter!.id).toList();
                if (filteredItems.isNotEmpty) {
                  planToShow[date] = filteredItems;
                }
              });

              final sortedDates = planToShow.keys.toList()..sort();
              for (var date in sortedDates) {
                listWidgets.add(
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
                    child: Text(
                      DateFormat('dd/MM/yyyy, EEEE', 'pt_BR').format(date),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  )
                );
                listWidgets.addAll(planToShow[date]!.map(_buildProductionCard));
              }
          } else {
              final productionForDay = fullPlan[_selectedDate] ?? [];
              listWidgets.addAll(productionForDay.map(_buildProductionCard));

              List<StockOpportunity> stockOpportunities = [];
              final dateToCheck = _selectedDate;
              final usedMoldTypes = (fullPlan[dateToCheck] ?? [])
                  .map((planItem) => productCatalog[planItem.productId]?.moldType)
                  .where((moldType) => moldType != null)
                  .toSet();
              
              final idleMolds = allMolds.where((mold) => !usedMoldTypes.contains(mold.name)).toList();

              for (final mold in idleMolds) {
                final productsForStock = productCatalog.values.where((p) {
                  if (p.moldType != mold.name) return false;
                  final skuLower = p.sku.toLowerCase();
                  return skuLower.contains('cleiton premoldados') || !skuLower.contains('manayra');
                }).toList();

                if (productsForStock.isNotEmpty) {
                  stockOpportunities.add(StockOpportunity(mold: mold, availableProducts: productsForStock));
                }
              }

              if (stockOpportunities.isNotEmpty) {
                listWidgets.add(const _StockOpportunityHeader());
                listWidgets.addAll(stockOpportunities.map((op) => _buildStockOpportunityCard(op)));
              }
          }

          if (listWidgets.isEmpty) {
            final message = _searchTerm.isNotEmpty 
              ? 'Nenhum item de produção encontrado para "$_searchTerm".'
              : _selectedOrderFilter != null
                  ? 'Nenhuma produção encontrada para este pedido.'
                  : 'Nenhuma produção agendada para ${DateFormat('dd/MM/yyyy').format(_selectedDate)}.';
            return Center(child: Text(message, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: listWidgets.length,
            itemBuilder: (context, index) => listWidgets[index],
          );
        },
      ),
    );
  }

  Widget _buildProductionCard(ProductionPlanItem planItem) {
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
          child: Text(planItem.quantityToProduce.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        title: Text('${planItem.sku} - ${planItem.productName}', style: const TextStyle(fontWeight: FontWeight.bold)),
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
  }

  Widget _buildStockOpportunityCard(StockOpportunity opportunity) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.green.shade50,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          child: Text(opportunity.mold.quantityAvailable.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        title: Text('Forma Ociosa: ${opportunity.mold.name}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          '${opportunity.mold.quantityAvailable} unidade(s) disponível(is) para adiantar produção para estoque.',
        ),
        isThreeLine: false,
        trailing: ElevatedButton(
          onPressed: () => _showProduceForStockDialog(opportunity),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('Usar Forma'),
        ),
      ),
    );
  }
}

class _StockOpportunityHeader extends StatelessWidget {
  const _StockOpportunityHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 24.0),
      child: Row(
        children: [
          Expanded(child: Divider()),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text("Oportunidades de Produção (Formas Ociosas)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _OrderFilterDialog extends StatefulWidget {
  final List<Order> candidateOrders;
  const _OrderFilterDialog({required this.candidateOrders});

  @override
  State<_OrderFilterDialog> createState() => _OrderFilterDialogState();
}

class _OrderFilterDialogState extends State<_OrderFilterDialog> {
  late List<Order> _filteredOrders;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredOrders = List.from(widget.candidateOrders);
    _searchController.addListener(_filterList);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterList);
    _searchController.dispose();
    super.dispose();
  }

  void _filterList() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredOrders = widget.candidateOrders.where((order) {
        final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? '';
        return order.clientName.toLowerCase().contains(query) ||
               orderIdShort.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filtrar por Pedido'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar por cliente ou ID...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredOrders.length,
                itemBuilder: (context, index) {
                  final order = _filteredOrders[index];
                  return ListTile(
                    title: Text(order.clientName),
                    subtitle: Text('Pedido #${order.id?.substring(0, 6).toUpperCase()}'),
                    onTap: () => Navigator.of(context).pop(order),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))],
    );
  }
}