// lib/screens/orders_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  final FirestoreService firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';
  late TabController _tabController;

  final List<OrderStatus> _selectedStatusFilters = [];
  
  // ##### NOVO FILTRO #####
  bool _filterByPendingRefund = false;
  
  bool _isSyncing = false;

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
            _filterByPendingRefund = false; // Limpa o novo filtro também
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
  
  Future<void> _runGlobalSync() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sincronizar Pedidos?'),
        content: const Text(
            'Isso irá verificar todos os pedidos em andamento, recontar os itens entregues e corrigir o status automaticamente.\n\nPode levar alguns segundos. Deseja continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sim, Sincronizar')),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSyncing = true);
    try {
      final count = await firestoreService.resynchronizeAllOrderStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count pedidos foram verificados e/ou atualizados com sucesso!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na sincronização: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
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
            // ##### NOVO BOTÃO DE FILTRO #####
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
                    if(selected) _selectedStatusFilters.clear(); // Limpa outros filtros
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
                        _filterByPendingRefund = false; // Limpa o filtro de reembolso
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
      appBar: AppBar(
        title: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pedidos Ativos'),
            Tab(text: 'Finalizados & Cancelados'),
          ],
        ),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sincronizar Status de Pedidos Ativos',
              onPressed: _runGlobalSync,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por cliente ou ID...',
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
      body: Column(
        children: [
          _buildStatusFilters(), // Movido para fora da TabBarView para aplicar a ambas
          Expanded(
            child: StreamBuilder<List<Order>>(
              stream: firestoreService.getOrdersStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Erro: ${snapshot.error}'));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text('Nenhuma cotação ou pedido encontrado.'));
                }
                
                final allOrders = snapshot.data!;
                
                // ##### LÓGICA DE FILTRO ATUALIZADA #####
                List<Order> filteredOrders = allOrders.where((order) {
                  final query = _searchTerm.toLowerCase();
                  final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? '';
                  return order.clientName.toLowerCase().contains(query) ||
                         orderIdShort.toLowerCase().contains(query);
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
          child: Text(
            'Nenhum pedido encontrado com os filtros aplicados.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(left: 8.0, right: 8.0, top: 8.0, bottom: 80.0),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? 'N/A';
        final bool needsRefund =
            order.notes?.contains('[SISTEMA] Valor a devolver ao cliente:') == true;

        String paymentInfo = '';
        if (isArchived && order.status == OrderStatus.finalizado && order.paymentDistributions.isNotEmpty) {
          final recipients = order.paymentDistributions.map((d) => d.recipient).toSet().join(', ');
          paymentInfo = '\nRecebido por: $recipients';
        }

        return Card(
          elevation: 2.0,
          margin: const EdgeInsets.symmetric(vertical: 8.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getStatusColor(order.status),
              child: Text(
                '${orders.length - index}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              '${order.clientName} - Pedido #$orderIdShort',
              style: const TextStyle(fontWeight: FontWeight.bold)
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data: ${DateFormat('dd/MM/yyyy').format(order.creationDate.toDate())}\n'
                  'Status: ${_getStatusName(order.status)}$paymentInfo',
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
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16),
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => OrderDetailsScreen(order: order),
                ),
              );
              if (mounted) {
                setState(() {});
              }
            },
            isThreeLine: true,
          ),
        );
      },
    );
  }
}

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