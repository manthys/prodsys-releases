// lib/screens/delivery_route_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order; 
import 'package:collection/collection.dart';

import '../models/order_model.dart';
import '../models/vehicle_model.dart';
import '../models/delivery_model.dart';
import '../models/stock_item_model.dart';
import '../models/delivery_selection_item_model.dart';

import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../services/delivery_pdf_service.dart';
import 'vehicles_screen.dart';
import 'order_details_screen.dart'; 

class DeliveryRouteScreen extends StatefulWidget {
  const DeliveryRouteScreen({super.key});

  @override
  State<DeliveryRouteScreen> createState() => _DeliveryRouteScreenState();
}

class _DeliveryRouteScreenState extends State<DeliveryRouteScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

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
      appBar: AppBar(
        title: const Text('Logística e Rotas'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.directions_car, color: Colors.black87),
            label: const Text('Gerenciar Veículos', style: TextStyle(color: Colors.black87)),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => const VehiclesScreen()));
            },
          ),
          const SizedBox(width: 16),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'Rotas Ativas / Histórico'),
            Tab(icon: Icon(Icons.add_road), text: 'Nova Rota'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ActiveRoutesTab(),
          _CreateRouteTab(),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// ABA 1: ROTAS ATIVAS E HISTÓRICO
// -----------------------------------------------------------------------------
class _ActiveRoutesTab extends StatelessWidget {
  const _ActiveRoutesTab();

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();
    final DeliveryPdfService pdfService = DeliveryPdfService();

    return StreamBuilder<List<Delivery>>(
      stream: firestoreService.getRoutesStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text('Nenhuma rota registrada nos últimos 30 dias.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 8),
                const Text('Use a aba "Nova Rota" para começar.', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }

        final allDeliveries = snapshot.data!;
        // Agrupa por routeId para mostrar como "Viagens"
        final groupedRoutes = groupBy(allDeliveries, (Delivery d) => d.routeId);

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: groupedRoutes.length,
          itemBuilder: (context, index) {
            final routeId = groupedRoutes.keys.elementAt(index);
            final deliveriesInRoute = groupedRoutes[routeId]!;
            final firstDelivery = deliveriesInRoute.first;
            
            final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(firstDelivery.deliveryDate.toDate());
            final driver = firstDelivery.driverName;
            final plate = firstDelivery.vehiclePlate;

            // Verifica se todas as entregas dessa rota estão concluídas para mudar a cor do card
            final isRouteFullyCompleted = deliveriesInRoute.every((d) => d.status == DeliveryStatus.entregue);

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              elevation: 2,
              color: isRouteFullyCompleted ? Colors.grey.shade100 : null, // Cinza se tudo entregue
              child: ExpansionTile(
                initiallyExpanded: !isRouteFullyCompleted && index == 0, 
                leading: CircleAvatar(
                  backgroundColor: isRouteFullyCompleted ? Colors.grey : Colors.blue.shade800, 
                  child: Icon(Icons.route, color: Colors.white)
                ),
                title: Text('$driver - $plate', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Saída: $dateStr • ${deliveriesInRoute.length} Entregas'),
                children: [
                  const Divider(height: 1),
                  ...deliveriesInRoute.map((delivery) {
                    bool isDelivered = delivery.status == DeliveryStatus.entregue;
                    return ListTile(
                      leading: Icon(
                        isDelivered ? Icons.check_circle : Icons.local_shipping,
                        color: isDelivered ? Colors.green : Colors.orange,
                      ),
                      title: Text(delivery.clientName),
                      subtitle: Text('Pedido: #${delivery.orderId.substring(0,6).toUpperCase()} | ${delivery.items.length} itens'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. IMPRIMIR
                          IconButton(
                            icon: const Icon(Icons.print),
                            tooltip: 'Imprimir Nota Individual',
                            onPressed: () async {
                              final order = await firestoreService.getOrderById(delivery.orderId);
                              final client = await firestoreService.getClientById(order!.clientId);
                              final settings = await firestoreService.getCompanySettings();
                              if (client != null) {
                                await pdfService.generateAndShowPdf(delivery, order, client, settings);
                              }
                            },
                          ),
                          
                          // 2. VER PEDIDO / DEVOLUÇÃO
                          IconButton(
                            icon: const Icon(Icons.receipt_long, color: Colors.blueGrey),
                            tooltip: 'Ver Pedido / Registrar Devolução',
                            onPressed: () async {
                               final order = await firestoreService.getOrderById(delivery.orderId);
                               if (order != null) {
                                 Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)));
                               }
                            },
                          ),

                          // 3. AÇÕES DE STATUS (CONCLUIR OU CANCELAR)
                          if (!isDelivered) ...[
                            // BOTÃO CONCLUIR (NOVO)
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Colors.teal),
                              tooltip: 'Confirmar Entrega Realizada',
                              onPressed: () async {
                                 final confirm = await showDialog(
                                   context: context, 
                                   builder: (c) => AlertDialog(
                                     title: const Text('Confirmar Entrega'),
                                     content: Text('Marcar a entrega para ${delivery.clientName} como CONCLUÍDA?'),
                                     actions: [
                                       TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
                                       ElevatedButton(
                                         style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                         onPressed: () => Navigator.pop(c, true), 
                                         child: const Text('Confirmar')
                                       )
                                     ],
                                   )
                                 );
                                 if (confirm == true) {
                                   await firestoreService.confirmDeliveryAsCompleted(delivery.orderId, delivery.id!);
                                 }
                              },
                            ),
                            
                            // BOTÃO CANCELAR
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              tooltip: 'Cancelar/Retornar ao Estoque',
                              onPressed: () async {
                                 final confirm = await showDialog(
                                   context: context, 
                                   builder: (c) => AlertDialog(
                                     title: const Text('Cancelar Entrega?'),
                                     content: Text('Deseja cancelar a entrega para ${delivery.clientName}? Os itens voltarão para o estoque "Em Estoque".'),
                                     actions: [
                                       TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Não')),
                                       ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sim'))
                                     ],
                                   )
                                 );
                                 if (confirm == true) {
                                   await firestoreService.cancelDelivery(delivery.id!);
                                 }
                              },
                            ),
                          ]
                        ],
                      ),
                    );
                  }).toList(),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// ABA 2: CRIAR NOVA ROTA
// -----------------------------------------------------------------------------
class _CreateRouteTab extends StatefulWidget {
  const _CreateRouteTab();

  @override
  State<_CreateRouteTab> createState() => _CreateRouteTabState();
}

class _CreateRouteTabState extends State<_CreateRouteTab> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  final DeliveryPdfService _deliveryPdfService = DeliveryPdfService();
  
  List<Vehicle> _vehicles = [];
  Vehicle? _selectedVehicle;
  List<Order> _availableOrders = [];
  Map<String, double> _productWeights = {};
  Map<String, List<_RouteSelectionItem>> _selections = {};
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    _vehicles = await _firestoreService.getVehiclesStream().first;
    
    final molds = await _firestoreService.getMoldsStream().first;
    final products = await _firestoreService.getProductsStream().first;
    final moldWeights = {for (var m in molds) m.name: m.weight};
    for (var p in products) {
      _productWeights[p.id!] = moldWeights[p.moldType] ?? 0.0;
    }

    final stockSnapshot = await _firestoreService.db.collection('stock_items')
        .where('status', isEqualTo: StockItemStatus.emEstoque.name)
        .get();
    final allStock = stockSnapshot.docs.map((d) => StockItem.fromFirestore(d.data(), d.id)).toList();
    final grouped = groupBy(allStock, (StockItem i) => i.orderId);
    
    List<String> orderIds = [];
    Map<String, List<StockItem>> stockItemsByOrder = {};
    grouped.forEach((orderId, items) {
      if (orderId != null) {
        stockItemsByOrder[orderId] = items;
        orderIds.add(orderId);
      }
    });

    if (orderIds.isNotEmpty) {
      final allOrders = await _firestoreService.getOperationalOrdersStream().first;
      _availableOrders = allOrders.where((o) => orderIds.contains(o.id)).toList();
    }

    for (var order in _availableOrders) {
      final stockItems = stockItemsByOrder[order.id]!;
      final groupedItems = groupBy(stockItems, (item) => '${item.productId}-${item.logoType}');
      List<_RouteSelectionItem> selectionList = [];
      groupedItems.forEach((key, items) {
        final first = items.first;
        selectionList.add(_RouteSelectionItem(
          productId: first.productId,
          productName: first.productName,
          sku: first.sku,
          logoType: first.logoType,
          maxQuantity: items.length,
          weight: _productWeights[first.productId] ?? 0.0,
          selectedQuantity: 0,
        ));
      });
      _selections[order.id!] = selectionList;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  double get _currentTotalWeight {
    double total = 0.0;
    _selections.forEach((_, items) {
      for (var item in items) {
        total += item.selectedQuantity * item.weight;
      }
    });
    return total;
  }

  void _autoFillLoad() {
    if (_selectedVehicle == null) return;
    double remainingLoad = _selectedVehicle!.maxLoadKg - _currentTotalWeight;
    if (remainingLoad <= 0) return;

    setState(() {
      for (var order in _availableOrders) {
        final items = _selections[order.id]!;
        for (var item in items) {
          if (remainingLoad <= 0) break;
          int canAdd = item.maxQuantity - item.selectedQuantity;
          if (canAdd > 0) {
            double itemWeight = item.weight == 0 ? 0.1 : item.weight;
            int quantityToFill = (remainingLoad / itemWeight).floor();
            int toAdd = quantityToFill < canAdd ? quantityToFill : canAdd;
            if (toAdd > 0) {
              item.selectedQuantity += toAdd;
              remainingLoad -= (toAdd * itemWeight);
            }
          }
        }
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Carga preenchida automaticamente até o limite!')));
  }

  void _confirmRoute() async {
    if (_selectedVehicle == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione um veículo.')));
      return;
    }
    if (_currentTotalWeight <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione itens para entregar.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final currentUser = _authService.currentUser;
      final userName = currentUser?.displayName ?? currentUser?.email ?? 'N/A';
      List<Delivery> deliveriesToCreate = [];

      _selections.forEach((orderId, items) {
        final selectedItems = items.where((i) => i.selectedQuantity > 0).toList();
        if (selectedItems.isNotEmpty) {
          final order = _availableOrders.firstWhere((o) => o.id == orderId);
          final deliveryItems = selectedItems.map((sel) => DeliveryItem(
            productId: sel.productId,
            sku: sel.sku,
            productName: sel.productName,
            quantity: sel.selectedQuantity,
            logoType: sel.logoType,
          )).toList();

          final delivery = Delivery(
            orderId: orderId,
            clientName: order.clientName,
            deliveryDate: Timestamp.now(),
            items: deliveryItems,
            driverName: _selectedVehicle!.driverName,
            vehiclePlate: _selectedVehicle!.plate,
            createdByUserName: userName,
            status: DeliveryStatus.emTransito,
          );
          deliveriesToCreate.add(delivery);
        }
      });

      final createdDeliveries = await _firestoreService.registerRouteDeliveries(deliveriesToCreate);
      
      if (mounted) {
        setState(() => _isSaving = false);
        _showSuccessAndPrintDialog(createdDeliveries);
        _loadInitialData();
        _selectedVehicle = null;
      }

    } catch (e) {
      if (mounted) setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    }
  }

  void _showSuccessAndPrintDialog(List<Delivery> deliveries) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Rota Criada com Sucesso!'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: Column(
            children: [
              const Text('As entregas foram registradas. Imprima os comprovantes para cada cliente abaixo:'),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: deliveries.length,
                  itemBuilder: (context, index) {
                    final delivery = deliveries[index];
                    return ListTile(
                      leading: const Icon(Icons.print, color: Colors.blue),
                      title: Text(delivery.clientName),
                      subtitle: Text('${delivery.items.length} itens'),
                      trailing: ElevatedButton(
                        child: const Text('Imprimir'),
                        onPressed: () async {
                          final order = await _firestoreService.getOrderById(delivery.orderId);
                          final client = await _firestoreService.getClientById(order!.clientId);
                          final settings = await _firestoreService.getCompanySettings();
                          if (client != null) {
                            await _deliveryPdfService.generateAndShowPdf(delivery, order, client, settings);
                          }
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), 
            child: const Text('Fechar e Nova Rota'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double loadPercent = _selectedVehicle != null && _selectedVehicle!.maxLoadKg > 0 
        ? _currentTotalWeight / _selectedVehicle!.maxLoadKg 
        : 0.0;
    Color barColor = loadPercent > 1.0 ? Colors.red : (loadPercent > 0.9 ? Colors.orange : Colors.green);

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Vehicle>(
                      decoration: const InputDecoration(labelText: 'Selecione o Veículo para a Rota', border: OutlineInputBorder()),
                      value: _selectedVehicle,
                      items: _vehicles.map((v) => DropdownMenuItem(value: v, child: Text('${v.name} (${v.plate}) - Max: ${v.maxLoadKg}kg'))).toList(),
                      onChanged: (v) => setState(() => _selectedVehicle = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(Icons.add),
                    tooltip: 'Cadastrar Veículo',
                    onPressed: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (context) => const VehiclesScreen()));
                      _loadInitialData(); 
                    },
                  )
                ],
              ),
              const SizedBox(height: 16),
              if (_selectedVehicle != null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Carga Atual: ${_currentTotalWeight.toStringAsFixed(1)} kg', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: barColor)),
                    Text('Máx: ${_selectedVehicle!.maxLoadKg} kg'),
                  ],
                ),
                const SizedBox(height: 5),
                LinearProgressIndicator(value: loadPercent > 1 ? 1 : loadPercent, color: barColor, backgroundColor: Colors.grey.shade200, minHeight: 10),
                if (loadPercent > 1.0)
                  const Text('ALERTA: SOBRECARGA!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Preencher Carga Automaticamente'),
                  onPressed: _autoFillLoad,
                )
              ]
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _availableOrders.length,
            itemBuilder: (context, index) {
              final order = _availableOrders[index];
              final items = _selections[order.id]!;
              bool hasSelection = items.any((i) => i.selectedQuantity > 0);

              return Card(
                margin: const EdgeInsets.all(8),
                color: hasSelection ? Colors.green.shade50 : null,
                child: ExpansionTile(
                  title: Text(order.clientName, style: TextStyle(fontWeight: FontWeight.bold, color: hasSelection ? Colors.green.shade800 : Colors.black)),
                  subtitle: Text('${order.deliveryAddress.neighborhood} - ${order.deliveryAddress.city}'),
                  trailing: hasSelection ? const Icon(Icons.check_circle, color: Colors.green) : null,
                  children: items.map((item) {
                    return ListTile(
                      title: Text(item.productName),
                      subtitle: Text('${item.sku} | Peso Un: ${item.weight}kg | Disp: ${item.maxQuantity}'),
                      trailing: SizedBox(
                        width: 140,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                if (item.selectedQuantity > 0) {
                                  setState(() => item.selectedQuantity--);
                                }
                              },
                            ),
                            Text('${item.selectedQuantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
                              onPressed: () {
                                if (item.selectedQuantity < item.maxQuantity) {
                                  setState(() => item.selectedQuantity++);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5, offset: const Offset(0, -2))]),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.blue.shade900, foregroundColor: Colors.white),
              onPressed: _isSaving ? null : _confirmRoute,
              child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('CONFIRMAR ROTA E GERAR ENTREGAS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RouteSelectionItem {
  final String productId;
  final String productName;
  final String sku;
  final String logoType;
  final int maxQuantity;
  final double weight;
  int selectedQuantity;

  _RouteSelectionItem({required this.productId, required this.productName, required this.sku, required this.logoType, required this.maxQuantity, required this.weight, required this.selectedQuantity});
}