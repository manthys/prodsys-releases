// lib/screens/mobile_production_stock_screen.dart (VERSÃO CORRIGIDA COM "SANFONA")

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:rxdart/rxdart.dart';
import '../models/mold_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';
import '../services/firestore_service.dart';
import '../services/production_scheduler.dart';
// Removida a importação do stock_adjustment_dialog, pois não é usado aqui

class MobileProductionStockScreen extends StatefulWidget {
  const MobileProductionStockScreen({super.key});

  @override
  State<MobileProductionStockScreen> createState() => _MobileProductionStockScreenState();
}

class _MobileProductionStockScreenState extends State<MobileProductionStockScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Fila de Produção'),
              Tab(text: 'Conferir Estoque'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ProductionQueueTab(),
          StockCheckTab(),
        ],
      ),
    );
  }
}

// =======================================================================
// WIDGET DA ABA 1: FILA DE PRODUÇÃO
// =======================================================================
class ProductionQueueTab extends StatefulWidget {
  const ProductionQueueTab({super.key});

  @override
  State<ProductionQueueTab> createState() => _ProductionQueueTabState();
}

class _ProductionQueueTabState extends State<ProductionQueueTab> {
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
    _selectedDate = DateTime(now.year, now.month, now.day);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
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
        
        final productionForDay = fullPlan[_selectedDate] ?? [];

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text('Produção de: ${DateFormat('dd/MM/yyyy, EEEE', 'pt_BR').format(_selectedDate)}'),
                onPressed: () => _selectDate(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16),
                  // Ocupa a largura toda
                  minimumSize: const Size(double.infinity, 40), 
                ),
              ),
            ),
            if (productionForDay.isEmpty)
              const Expanded(
                child: Center(child: Text('Nenhuma produção agendada para esta data.'))
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                  itemCount: productionForDay.length,
                  itemBuilder: (context, index) {
                    return _buildProductionCard(productionForDay[index]);
                  },
                ),
              ),
          ],
        );
      },
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
        title: Text('${planItem.sku} - ${planItem.productName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          'Cliente: ${planItem.clientName} | Pedido: #${planItem.orderId}\nLogo: ${planItem.logoType} | Prazo: ${DateFormat('dd/MM/yy').format(planItem.deliveryDeadline)}',
          style: TextStyle(color: isLate ? Colors.red.shade900 : null, fontSize: 12),
        ),
        isThreeLine: true,
      ),
    );
  }
}

// =======================================================================
// WIDGET DA ABA 2: CONFERÊNCIA DE ESTOQUE (COM LÓGICA DE AGRUPAMENTO)
// =======================================================================
class StockCheckTab extends StatefulWidget {
  const StockCheckTab({super.key});

  @override
  State<StockCheckTab> createState() => _StockCheckTabState();
}

class _StockCheckTabState extends State<StockCheckTab> with SingleTickerProviderStateMixin {
  late TabController _stockTabController;
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _stockTabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      if (mounted) setState(() => _searchTerm = _searchController.text);
    });
  }

  @override
  void dispose() {
    _stockTabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por produto ou SKU...',
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
        TabBar(
          controller: _stockTabController,
          tabs: const [
            Tab(text: 'Estoque Geral'),
            Tab(text: 'Estoque Alocado'),
          ],
        ),
        Expanded(
          child: StreamBuilder<List<dynamic>>( // MUDADO PARA LISTA DINÂMICA
            stream: Rx.combineLatest2( // MUDADO PARA COMBINAR OS STREAMS
              _firestoreService.getStockItemsStream(),
              _firestoreService.getOrdersStream(), // PEGA OS PEDIDOS PARA SABER OS IDS FINALIZADOS
              (List<StockItem> items, List<Order> orders) => [items, orders]
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(child: Text('Nenhum item no estoque.'));
              }

              final allStockItems = snapshot.data![0] as List<StockItem>;
              final allOrders = snapshot.data![1] as List<Order>;

              // Identifica os pedidos que não devem mais aparecer no "Alocado"
              final finalizedOrderIds = allOrders
                  .where((order) => order.status == OrderStatus.finalizado || order.status == OrderStatus.cancelado)
                  .map((order) => order.id)
                  .toSet();

              List<StockItem> searchedItems = allStockItems;
              if (_searchTerm.isNotEmpty) {
                final query = _searchTerm.toLowerCase();
                searchedItems = allStockItems.where((item) {
                  return item.productName.toLowerCase().contains(query) ||
                          item.sku.toLowerCase().contains(query);
                }).toList();
              }

              final manualStock = searchedItems.where((item) => item.orderId == null).toList();
              // Filtra os alocados para não mostrar itens de pedidos já finalizados/cancelados
              final allocatedStock = searchedItems.where((item) => item.orderId != null && !finalizedOrderIds.contains(item.orderId)).toList();

              return TabBarView(
                controller: _stockTabController,
                children: [
                  _buildStockList(manualStock, isGeneralStock: true),
                  _buildStockList(allocatedStock, isGeneralStock: false),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // =================================================================
  // FUNÇÃO ATUALIZADA PARA LIDAR COM OS DOIS TIPOS DE LISTA
  // =================================================================
  Widget _buildStockList(List<StockItem> items, {required bool isGeneralStock}) {
    if (items.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('Nenhum item encontrado.'),
      ));
    }

    // Se for Estoque Geral, agrupa por produto (como antes)
    if (isGeneralStock) {
      final groupedItems = <String, Map<String, dynamic>>{};
      for (var item in items) {
        final key = '${item.productId}_${item.status.name}_${item.logoType}'; // Removido orderId da chave
        groupedItems.update(
          key, (value) { 
            (value['items'] as List<StockItem>).add(item);
            return value; 
          },
          ifAbsent: () => {'item': item, 'items': [item]},
        );
      }
      final groupedList = groupedItems.values.toList();
      groupedList.sort((a, b) => (a['item'] as StockItem).productName.compareTo((b['item'] as StockItem).productName));

      return ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: groupedList.length,
        itemBuilder: (context, index) {
          final group = groupedList[index];
          return _buildStockCard(group);
        },
      );
    } 
    
    // Se for Estoque Alocado, agrupa por Pedido (a "sanfona")
    else {
      final groupedByOrder = groupBy(items, (StockItem item) => item.orderId!);
      
      final sortedOrderIds = groupedByOrder.keys.toList()
        ..sort((a, b) {
          final clientA = groupedByOrder[a]!.first.clientName ?? '';
          final clientB = groupedByOrder[b]!.first.clientName ?? '';
          return clientA.compareTo(clientB);
        });

      return ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: sortedOrderIds.length,
        itemBuilder: (context, index) {
          final orderId = sortedOrderIds[index];
          final orderItems = groupedByOrder[orderId]!;
          final firstItem = orderItems.first;
          final orderIdShort = orderId.length >= 6 ? orderId.substring(0, 6).toUpperCase() : orderId.toUpperCase();
          
          // Agrupa os itens *dentro* do pedido por produto
          final itemsGroupedByProduct = groupBy(orderItems, (StockItem item) => '${item.productId}_${item.status.name}_${item.logoType}');
          
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              key: PageStorageKey(orderId),
              title: Text(
                'Pedido #$orderIdShort - ${firstItem.clientName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${orderItems.length} itens alocados'),
              children: itemsGroupedByProduct.values.map((productGroup) {
                // Para cada sub-grupo de produtos, cria o map e chama o _buildStockCard
                final group = {'item': productGroup.first, 'items': productGroup};
                return _buildStockCard(group);
              }).toList(),
            ),
          );
        },
      );
    }
  }

  // Widget de Card de Estoque (agora reutilizado por ambas as listas)
  Widget _buildStockCard(Map<String, dynamic> group) {
    final StockItem item = group['item'];
    final int count = (group['items'] as List<StockItem>).length;

    String orderText;
    if (item.orderId != null && item.orderId!.isNotEmpty) {
      String orderIdShort = item.orderId!.length >= 6 ? item.orderId!.substring(0, 6).toUpperCase() : item.orderId!.toUpperCase();
      orderText = 'Pedido: #$orderIdShort';
    } else {
      orderText = 'Estoque Geral';
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getStatusColor(item.status),
        foregroundColor: Colors.white,
        child: Text(count.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      title: Text('${item.sku} - ${item.productName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text('Status: ${_getStatusName(item.status)}\nLogo: ${item.logoType} | $orderText'),
      isThreeLine: true,
    );
  }

  Color _getStatusColor(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao: return Colors.orange;
      case StockItemStatus.emEstoque: return Colors.green;
      case StockItemStatus.emTransito: return Colors.blue;
      case StockItemStatus.entregue: return Colors.blueGrey;
    }
  }

  String _getStatusName(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao: return 'Aguardando Produção';
      case StockItemStatus.emEstoque: return 'Em Estoque';
      case StockItemStatus.emTransito: return 'Em Trânsito';
      case StockItemStatus.entregue: return 'Entregue';
    }
  }
}