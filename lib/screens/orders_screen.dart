// lib/screens/orders_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import 'order_details_screen.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      body: StreamBuilder<List<Order>>(
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

          final orders = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? 'N/A';

              // ##### ALTERAÇÃO AQUI: LÓGICA PARA VERIFICAR O REEMBOLSO #####
              final bool needsRefund =
                  order.notes?.contains('Valor a devolver ao cliente:') == true &&
                  order.status != OrderStatus.finalizado &&
                  order.status != OrderStatus.cancelado;

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
                  // ##### ALTERAÇÃO AQUI: ATUALIZA O SUBTÍTULO PARA MOSTRAR O SELO #####
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Data: ${DateFormat('dd/MM/yyyy').format(order.creationDate.toDate())}\n'
                          'Status: ${_getStatusName(order.status)}'),
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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => OrderDetailsScreen(order: order),
                      ),
                    );
                  },
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Color _getStatusColor(OrderStatus status) {
  switch (status) {
    case OrderStatus.cotacao: return Colors.blueGrey;
    case OrderStatus.pedido: return Colors.orange;
    case OrderStatus.emFabricacao: return Colors.blue;
    case OrderStatus.aguardandoEntrega: return Colors.purple; 
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
    case OrderStatus.finalizado: return 'Finalizado';
    case OrderStatus.cancelado: return 'Cancelado';
  }
}