// lib/screens/mobile_orders_screen.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import 'mobile_order_details_screen.dart';
// Ainda não vamos importar a tela de detalhes, faremos isso no próximo passo
// import 'mobile_order_details_screen.dart'; 

class MobileOrdersScreen extends StatefulWidget {
  const MobileOrdersScreen({super.key});

  @override
  State<MobileOrdersScreen> createState() => _MobileOrdersScreenState();
}

class _MobileOrdersScreenState extends State<MobileOrdersScreen> with SingleTickerProviderStateMixin {
  
  // =================================================================
  // ESTA É A LINHA QUE ESTAVA FALTANDO
  // =================================================================
  final FirestoreService firestoreService = FirestoreService();

  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  late TabController _tabController;

  final List<OrderStatus> _selectedStatusFilters = [];
  bool _filterByPendingRefund = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _searchController.addListener(() {
      if (mounted) setState(() => _searchTerm = _searchController.text);
    });
    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          if (_tabController.indexIsChanging) {
            _selectedStatusFilters.clear();
            _filterByPendingRefund = false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }
  
  Widget _buildStatusFilters() {
    const availableFilters = [
      OrderStatus.cotacao,
      OrderStatus.pedido,
      OrderStatus.emFabricacao,
      OrderStatus.aguardandoEntrega,
      OrderStatus.aguardandoPagamentoFinal,
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (_selectedStatusFilters.isNotEmpty || _filterByPendingRefund)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  avatar: const Icon(Icons.clear, size: 16),
                  label: const Text('Limpar Filtros'),
                  onPressed: () => setState(() {
                    _selectedStatusFilters.clear();
                    _filterByPendingRefund = false;
                  }),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: FilterChip(
                label: const Text('Reemb. Pendente'),
                avatar: Icon(Icons.request_quote_outlined, color: Colors.orange.shade800),
                selectedColor: Colors.orange.shade100,
                selected: _filterByPendingRefund,
                onSelected: (selected) {
                  setState(() {
                    _filterByPendingRefund = selected;
                    if(selected) _selectedStatusFilters.clear();
                  });
                },
              ),
            ),
            const VerticalDivider(),
            ...availableFilters.map((status) {
              final isSelected = _selectedStatusFilters.contains(status);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: FilterChip(
                  label: Text(_getStatusName(status)),
                  selected: isSelected,
                  onSelected: (bool selected) {
                    setState(() {
                      if (selected) {
                        _selectedStatusFilters.add(status);
                        _filterByPendingRefund = false;
                      } else {
                        _selectedStatusFilters.remove(status);
                      }
                    });
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // O AppBar agora é um TabBar + Barra de Busca
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110.0),
        child: AppBar(
          automaticallyImplyLeading: false, // Remove o botão de voltar
          flexibleSpace: Padding(
            padding: const EdgeInsets.only(left: 12.0, right: 12.0, top: 8.0, bottom: 4.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por cliente, ID ou comprador...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).colorScheme.background,
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
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Pedidos Ativos'),
              Tab(text: 'Finalizados & Cancelados'),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          _buildStatusFilters(),
          Expanded(
            child: StreamBuilder<List<Order>>(
              stream: firestoreService.getOrdersStream(), // Agora esta linha funciona
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erro: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Nenhum pedido encontrado.'));
                }
                
                final allOrders = snapshot.data!;
                
                List<Order> filteredOrders = allOrders.where((order) {
                  final query = _searchTerm.toLowerCase();
                  final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? '';
                  final buyerName = order.buyerName?.toLowerCase() ?? '';

                  return order.clientName.toLowerCase().contains(query) ||
                        orderIdShort.toLowerCase().contains(query) ||
                        buyerName.contains(query);
                }).toList();

                if (_filterByPendingRefund) {
                  filteredOrders = filteredOrders.where((order) => order.notes?.contains('[SISTEMA] Valor a devolver ao cliente:') ?? false).toList();
                } else if (_selectedStatusFilters.isNotEmpty) {
                  filteredOrders = filteredOrders.where((order) => _selectedStatusFilters.contains(order.status)).toList();
                }
                
                final activeOrders = filteredOrders.where((o) => o.status != OrderStatus.finalizado && o.status != OrderStatus.cancelado).toList();
                final archivedOrders = filteredOrders.where((o) => o.status == OrderStatus.finalizado || o.status == OrderStatus.cancelado).toList();

                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrdersList(activeOrders, isArchived: false),
                    _buildOrdersList(archivedOrders, isArchived: true),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersList(List<Order> orders, {required bool isArchived}) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    if (orders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Nenhum pedido encontrado com os filtros aplicados.', textAlign: TextAlign.center),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0, bottom: 16.0),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? 'N/A';
        final bool needsRefund = order.notes?.contains('[SISTEMA] Valor a devolver ao cliente:') == true;

        return Card(
          elevation: 2.0,
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(order.status),
              child: Text(
                '${orders.length - index}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            title: Text(
              '${order.clientName} - #$orderIdShort',
              style: const TextStyle(fontWeight: FontWeight.bold)
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Data: ${DateFormat('dd/MM/yyyy').format(order.creationDate.toDate())}'),
                Text('Status: ${_getStatusName(order.status)}'),
                if (order.buyerName != null && order.buyerName!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      'Comprador: ${order.buyerName}',
                      style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ),
                if (needsRefund)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Chip(
                      label: const Text('Reembolso Pendente', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                      backgroundColor: Colors.orange.shade100,
                      side: BorderSide(color: Colors.orange.shade300),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  ),
              ],
            ),
            trailing: Text(
              currencyFormatter.format(order.finalAmount),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            isThreeLine: (order.buyerName != null && order.buyerName!.isNotEmpty) || needsRefund,
            onTap: () {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => MobileOrderDetailsScreen(order: order),
    ),
  );
            },
          ),
        );
      },
    );
  }
}

// Funções de ajuda (copiadas do arquivo desktop)
Color _getStatusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.cotacao: return Colors.blueGrey;
    case OrderStatus.pedido: return Colors.orange;
    case OrderStatus.emFabricacao: return Colors.blue;
    case OrderStatus.aguardandoEntrega: return Colors.purple; 
    case OrderStatus.aguardandoPagamentoFinal: return Colors.amber.shade700;
    case OrderStatus.finalizado: return Colors.green;
    case OrderStatus.cancelado: return Colors.red;
  }
}

String _getStatusName(OrderStatus status) {
  switch (status) {
    case OrderStatus.cotacao: return 'Cotação';
    case OrderStatus.pedido: return 'Pedido';
    case OrderStatus.emFabricacao: return 'Em Fabricação';
    case OrderStatus.aguardandoEntrega: return 'Aguardando Entrega'; 
    case OrderStatus.aguardandoPagamentoFinal: return 'Aguardando Pagamento Final';
    case OrderStatus.finalizado: return 'Finalizado';
    case OrderStatus.cancelado: return 'Cancelado';
  }
}