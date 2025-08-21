import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';
import '../services/firestore_service.dart';
import '../widgets/stock_adjustment_dialog.dart';
import 'package:rxdart/rxdart.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  _StockScreenState createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();
  Product? _selectedProductFilter;
  List<StockItemStatus> _selectedStatusFilters = [];

  // Variável para forçar a reconstrução do StreamBuilder
  final BehaviorSubject<void> _reloadSubject = BehaviorSubject<void>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) _clearFilters();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _reloadSubject.close(); // Fechar o subject para evitar memory leaks
    super.dispose();
  }

  void _showAdjustmentDialog(Map<String, dynamic> stockGroup) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StockAdjustmentDialog(stockGroup: stockGroup),
    );

    if (result != null) {
      final StockItem item = stockGroup['item'];
      final int initialQuantity = stockGroup['count'];
      final int newQuantity = result['newQuantity'];
      final String reason = result['reason'];

      await _firestoreService.adjustStockQuantity(item, initialQuantity, newQuantity, reason);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Estoque ajustado com sucesso!'), backgroundColor: Colors.green),
        );
      }
    }
  }
  
  void _showFilterDialog(List<Product> allProducts) async {
    final isAllocatedTab = _tabController.index == 1;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _FilterDialog(
        allProducts: allProducts, initialProduct: _selectedProductFilter,
        initialStatuses: _selectedStatusFilters, isAllocated: isAllocatedTab,
      ),
    );

    if (result != null) {
      setState(() {
        _selectedProductFilter = result['product'];
        _selectedStatusFilters = result['statuses'];
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedProductFilter = null;
      _selectedStatusFilters = [];
    });
  }

  void _showManualAllocationDialog(StockItem stockItem, int maxQuantity) async {
    final allOrders = await _firestoreService.getOrdersStream().first;
    final List<Order> candidateOrders = [];

    for (final order in allOrders) {
      if (order.status == OrderStatus.emFabricacao) {
        if (order.items.any((orderItem) => 
            orderItem.productId == stockItem.productId && 
            orderItem.logoType == stockItem.logoType &&
            orderItem.remainingQuantity > 0)) {
          candidateOrders.add(order);
        }
      }
    }

    if (candidateOrders.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum pedido na fila de produção precisa deste item no momento.'), backgroundColor: Colors.orange),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    Order? selectedOrder;
    final qtyController = TextEditingController(text: maxQuantity.toString());

    final Map<String, dynamic>? result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Alocar ${stockItem.productName}'),
          content: Form(
            key: formKey,
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Selecione o pedido de destino para este item:'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Order>(
                    hint: const Text('Escolha um pedido...'),
                    isExpanded: true,
                    items: candidateOrders.map((order) {
                      final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? 'N/A';
                      return DropdownMenuItem<Order>(
                        value: order,
                        child: Text('Pedido #$orderIdShort - ${order.clientName}', overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (value) {
                      selectedOrder = value;
                    },
                    validator: (value) => selectedOrder == null ? 'Selecione um pedido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: qtyController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Quantidade a Alocar',
                      hintText: 'Máx: $maxQuantity',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Obrigatório';
                      final qty = int.tryParse(value);
                      if (qty == null || qty <= 0) return 'Inválido';
                      if (qty > maxQuantity) return 'Máximo é $maxQuantity';
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  formKey.currentState!.save();
                  Navigator.of(context).pop({
                    'order': selectedOrder,
                    'quantity': int.parse(qtyController.text)
                  });
                }
              },
              child: const Text('Alocar'),
            ),
          ],
        );
      },
    );

    if (result != null && mounted) {
      final Order order = result['order'];
      final int quantity = result['quantity'];
      
      await _firestoreService.reallocateStockItem(
        stockItemToMove: stockItem, 
        targetOrder: order, 
        quantity: quantity
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$quantity item(ns) alocados para o Pedido #${order.id?.substring(0,6).toUpperCase()} com sucesso!'), backgroundColor: Colors.green),
      );
      
      // Força a recarga da tela
      _reloadSubject.add(null);
    }
  }
  
  void _showDeallocateDialog(StockItem stockItem, int maxQuantity) async {
    final qtyController = TextEditingController(text: maxQuantity.toString());
    final formKey = GlobalKey<FormState>();

    final int? quantityToDeallocate = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Devolver ${stockItem.productName} ao Estoque Geral'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Quantidade a Devolver',
              hintText: 'Máx: $maxQuantity',
            ),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Obrigatório';
              final qty = int.tryParse(value);
              if (qty == null || qty <= 0) return 'Inválido';
              if (qty > maxQuantity) return 'Máximo é $maxQuantity';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop(int.parse(qtyController.text));
              }
            },
            child: const Text('Confirmar Devolução'),
          ),
        ],
      ),
    );

    if (quantityToDeallocate != null && mounted) {
      await _firestoreService.deallocateStockItems(
        stockItemToDeallocate: stockItem, 
        quantity: quantityToDeallocate
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$quantityToDeallocate item(ns) devolvidos ao estoque geral.'), backgroundColor: Colors.orange),
      );

      // Força a recarga da tela
      _reloadSubject.add(null);
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TabBar(
          controller: _tabController,
          tabs: const [Tab(text: 'Estoque Disponível (Geral)'), Tab(text: 'Estoque Alocado (Pedidos)')],
        ),
        actions: [
          // ##### NOVO BOTÃO DE RECARREGAR #####
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar Lista',
            onPressed: () {
              _reloadSubject.add(null);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lista de estoque atualizada.'), duration: Duration(seconds: 1)),
              );
            },
          ),
          if (_selectedProductFilter != null || _selectedStatusFilters.isNotEmpty)
            IconButton(icon: const Icon(Icons.filter_alt_off_outlined), tooltip: 'Limpar Filtros', onPressed: _clearFilters),
          StreamBuilder<List<Product>>(
            stream: _firestoreService.getProductsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              return IconButton(icon: const Icon(Icons.filter_alt_outlined), tooltip: 'Filtrar Estoque', onPressed: () => _showFilterDialog(snapshot.data!));
            },
          ),
        ],
      ),
      body: StreamBuilder(
        // O StreamBuilder agora escuta a combinação dos streams e do nosso gatilho de recarga
        stream: Rx.combineLatest3(
          _firestoreService.getStockItemsStream(),
          _firestoreService.getOrdersStream(),
          _reloadSubject.stream.startWith(null), // startWith(null) garante que o stream emita um valor inicial
          (List<StockItem> items, List<Order> orders, _) => {'items': items, 'orders': orders}
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData) return const Center(child: Text('Nenhum item no estoque.'));

          final allStockItems = snapshot.data!['items'] as List<StockItem>;
          final allOrders = snapshot.data!['orders'] as List<Order>;

          final finalizedOrderIds = allOrders
              .where((order) => order.status == OrderStatus.finalizado || order.status == OrderStatus.cancelado)
              .map((order) => order.id)
              .toSet();

          List<StockItem> filteredItems = allStockItems;
          if (_selectedProductFilter != null) {
            filteredItems = filteredItems.where((item) => item.productId == _selectedProductFilter!.id).toList();
          }
          if (_selectedStatusFilters.isNotEmpty) {
            filteredItems = filteredItems.where((item) => _selectedStatusFilters.contains(item.status)).toList();
          }

          final manualStock = filteredItems.where((item) => item.orderId == null).toList();
          final allocatedStock = filteredItems.where((item) => item.orderId != null && !finalizedOrderIds.contains(item.orderId)).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildStockList(manualStock),
              _buildStockList(allocatedStock),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStockList(List<StockItem> items) {
    if (items.isEmpty) {
      return const Center(child: Text('Nenhum item encontrado.'));
    }
    final groupedItems = <String, Map<String, dynamic>>{};
    for (var item in items) {
      final key = '${item.productId}_${item.status.name}_${item.logoType}_${item.orderId}';
      groupedItems.update(
        key, (value) { 
          (value['items'] as List<StockItem>).add(item);
          return value; 
        },
        ifAbsent: () => {'item': item, 'items': [item]},
      );
    }
    final groupedList = groupedItems.values.toList();
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: groupedList.length,
      itemBuilder: (context, index) {
        final group = groupedList[index];
        return _buildStockCard(context, group);
      },
    );
  }

  Widget _buildStockCard(BuildContext context, Map<String, dynamic> group) {
    final StockItem item = group['item'];
    final int count = (group['items'] as List<StockItem>).length;
    final bool canBeReallocated = item.status == StockItemStatus.emEstoque;
    
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(item.status),
          foregroundColor: Colors.white,
          child: Tooltip(message: _getStatusName(item.status), child: Icon(_getStatusIcon(item.status))),
        ),
        title: Text('${item.sku} - ${item.productName}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Status: ${_getStatusName(item.status)} | Logo: ${item.logoType}\nPedido: ${item.orderId != null ? ('#' + (item.orderId?.substring(0, 6).toUpperCase() ?? '')) : 'Estoque Geral'}'),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canBeReallocated)
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'allocate') {
                    _showManualAllocationDialog(item, count);
                  } else if (value == 'deallocate') {
                    _showDeallocateDialog(item, count);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'allocate',
                    child: ListTile(leading: Icon(Icons.redo, color: Colors.blue), title: Text('Alocar para Pedido')),
                  ),
                  if (item.orderId != null)
                    const PopupMenuItem<String>(
                      value: 'deallocate',
                      child: ListTile(leading: Icon(Icons.undo, color: Colors.orange), title: Text('Devolver ao Geral')),
                    ),
                ],
                icon: const Icon(Icons.more_vert),
              ),
            Text('${count.toString()} un.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.build_circle_outlined, color: Colors.grey),
              tooltip: 'Ajustar Quantidade',
              onPressed: () {
                final adjustmentGroup = {
                  'item': item,
                  'count': count,
                };
                _showAdjustmentDialog(adjustmentGroup);
              },
            )
          ],
        ),
      ),
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
  IconData _getStatusIcon(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao: return Icons.watch_later_outlined;
      case StockItemStatus.emEstoque: return Icons.inventory_2_outlined;
      case StockItemStatus.emTransito: return Icons.local_shipping_outlined;
      case StockItemStatus.entregue: return Icons.check_circle_outline;
    }
  }
}

class _FilterDialog extends StatefulWidget {
  final List<Product> allProducts;
  final Product? initialProduct;
  final List<StockItemStatus> initialStatuses;
  final bool isAllocated;

  const _FilterDialog({
    required this.allProducts,
    this.initialProduct,
    required this.initialStatuses,
    required this.isAllocated,
  });

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  Product? _selectedProduct;
  late List<StockItemStatus> _selectedStatuses;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
    _selectedStatuses = List.from(widget.initialStatuses);
  }

  @override
  Widget build(BuildContext context) {
    final availableStatuses = widget.isAllocated
        ? [StockItemStatus.aguardandoProducao, StockItemStatus.emEstoque, StockItemStatus.emTransito, StockItemStatus.entregue]
        : [StockItemStatus.emEstoque];

    return AlertDialog(
      title: const Text('Filtrar Estoque'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<Product>(
              value: _selectedProduct,
              hint: const Text('Todos os produtos'),
              items: widget.allProducts.map((product) => DropdownMenuItem(
                value: product,
                child: Text('${product.sku} - ${product.name}', overflow: TextOverflow.ellipsis),
              )).toList(),
              onChanged: (value) => setState(() => _selectedProduct = value),
              decoration: const InputDecoration(labelText: 'Filtrar por Produto'),
            ),
            const SizedBox(height: 20),
            Text('Filtrar por Status:', style: Theme.of(context).textTheme.titleSmall),
            Wrap(
              spacing: 8.0,
              children: availableStatuses.map((status) {
                final isSelected = _selectedStatuses.contains(status);
                return FilterChip(
                  label: Text(_getStatusName(status)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedStatuses.add(status);
                      } else {
                        _selectedStatuses.remove(status);
                      }
                    });
                  },
                );
              }).toList(),
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop({
              'product': _selectedProduct,
              'statuses': _selectedStatuses,
            });
          },
          child: const Text('Aplicar Filtros'),
        ),
      ],
    );
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