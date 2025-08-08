// lib/screens/client_order_history_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/client_model.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import 'order_details_screen.dart';

class ClientOrderHistoryScreen extends StatelessWidget {
  final Client client;
  
  const ClientOrderHistoryScreen({super.key, required this.client});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico de ${client.name}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: StreamBuilder<List<Order>>(
        stream: firestoreService.getOrdersForClientStream(client.id!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Text('Nenhum pedido encontrado para este cliente.'),
            );
          }

          final orders = snapshot.data!;

          return ListView.builder(
            padding: const EdgeInsets.all(8.0),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final orderIdShort = order.id?.substring(0, 6).toUpperCase() ?? 'N/A';

              return Card(
                elevation: 2.0,
                margin: const EdgeInsets.symmetric(vertical: 8.0),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(order.status),
                    child: const Icon(Icons.receipt_long, color: Colors.white),
                  ),
                  title: Text(
                    'Pedido #$orderIdShort',
                    style: const TextStyle(fontWeight: FontWeight.bold)
                  ),
                  subtitle: Text(
                      'Data: ${DateFormat('dd/MM/yyyy').format(order.creationDate.toDate())}\n'
                      'Status: ${_getStatusName(order.status)}'),
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