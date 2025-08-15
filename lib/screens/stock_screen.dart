// lib/screens/stock_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';
import '../services/firestore_service.dart';
import '../widgets/stock_adjustment_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Adiciona um listener para limpar os filtros ao trocar de aba, evitando confusão
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        _clearFilters();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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
        allProducts: allProducts,
        initialProduct: _selectedProductFilter,
        initialStatuses: _selectedStatusFilters,
        isAllocated: isAllocatedTab, // Passa o contexto da aba para o dialog
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Estoque Disponível (Manual)'),
            Tab(text: 'Estoque Alocado (Pedidos)'),
          ],
        ),
        actions: [
          if (_selectedProductFilter != null || _selectedStatusFilters.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.filter_alt_off_outlined),
              tooltip: 'Limpar Filtros',
              onPressed: _clearFilters,
            ),
          StreamBuilder<List<Product>>(
            stream: _firestoreService.getProductsStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();
              return IconButton(
                icon: const Icon(Icons.filter_alt_outlined),
                tooltip: 'Filtrar Estoque',
                onPressed: () => _showFilterDialog(snapshot.data!),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<StockItem>>(
        stream: _firestoreService.getStockItemsStream(),
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

          List<StockItem> filteredItems = snapshot.data!;

          if (_selectedProductFilter != null) {
            filteredItems = filteredItems.where((item) => item.productId == _selectedProductFilter!.id).toList();
          }
          if (_selectedStatusFilters.isNotEmpty) {
            filteredItems = filteredItems.where((item) => _selectedStatusFilters.contains(item.status)).toList();
          }

          final manualStock = filteredItems.where((item) => item.orderId == null).toList();
          final allocatedStock = filteredItems.where((item) => item.orderId != null).toList();

          return TabBarView(
            controller: _tabController,
            children: [
              _buildStockList(manualStock, isAllocated: false),
              _buildStockList(allocatedStock, isAllocated: true),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStockList(List<StockItem> items, {required bool isAllocated}) {
    if (items.isEmpty) {
      return const Center(child: Text('Nenhum item encontrado com os filtros aplicados.'));
    }

    final groupedItems = <String, Map<String, dynamic>>{};
    for (var item in items) {
      final key = '${item.productId}_${item.status.name}_${item.logoType}';
      groupedItems.update(
        key, (value) { value['count'] = (value['count'] as int) + 1; return value; },
        ifAbsent: () => {'item': item, 'count': 1},
      );
    }
    final groupedList = groupedItems.values.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: groupedList.length,
      itemBuilder: (context, index) {
        final group = groupedList[index];
        return _buildStockCard(context, group, isAllocated: isAllocated);
      },
    );
  }

  Widget _buildStockCard(BuildContext context, Map<String, dynamic> group, {required bool isAllocated}) {
    final StockItem item = group['item'];
    final int count = group['count'];
    
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(item.status),
          foregroundColor: Colors.white,
          child: Tooltip(message: _getStatusName(item.status), child: Icon(_getStatusIcon(item.status))),
        ),
        title: Text('${item.sku} - ${item.productName}', style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Status: ${_getStatusName(item.status)} | Logo: ${item.logoType}\nPedido: ${isAllocated ? ('#' + (item.orderId?.substring(0, 6).toUpperCase() ?? '')) : 'Estoque Manual'}'),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${count.toString()} un.', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.build_circle_outlined, color: Colors.grey),
              tooltip: 'Ajustar Quantidade',
              onPressed: () => _showAdjustmentDialog(group),
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
  final bool isAllocated; // <-- NOVO PARÂMETRO

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
    // Define quais status mostrar com base na aba atual
    final availableStatuses = widget.isAllocated
        ? [StockItemStatus.aguardandoProducao, StockItemStatus.emTransito, StockItemStatus.entregue]
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
              children: availableStatuses.map((status) { // Usa a lista de status filtrada
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
        TextButton(
          onPressed: () => Navigator.of(context).pop(), // Cancela sem salvar
          child: const Text('Cancelar'),
        ),
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

  // Copiado para cá para ser acessível
  String _getStatusName(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao: return 'Aguardando Produção';
      case StockItemStatus.emEstoque: return 'Em Estoque';
      case StockItemStatus.emTransito: return 'Em Trânsito';
      case StockItemStatus.entregue: return 'Entregue';
    }
  }
}