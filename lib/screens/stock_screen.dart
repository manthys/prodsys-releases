// lib/screens/stock_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/stock_item_model.dart';
import '../services/firestore_service.dart';

class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  Color _getStatusColor(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao:
        return Colors.orange;
      case StockItemStatus.emEstoque:
        return Colors.green;
      // ===== NOVO STATUS ADICIONADO =====
      case StockItemStatus.emTransito:
        return Colors.blue;
      case StockItemStatus.entregue:
        return Colors.blueGrey;
    }
  }

  String _getStatusName(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao:
        return 'Aguardando Produção';
      case StockItemStatus.emEstoque:
        return 'Em Estoque';
      // ===== NOVO STATUS ADICIONADO =====
      case StockItemStatus.emTransito:
        return 'Em Trânsito';
      case StockItemStatus.entregue:
        return 'Entregue';
    }
  }
  
  IconData _getStatusIcon(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao:
        return Icons.watch_later_outlined;
      case StockItemStatus.emEstoque:
        return Icons.inventory_2_outlined;
      // ===== NOVO ÍCONE ADICIONADO =====
      case StockItemStatus.emTransito:
        return Icons.local_shipping_outlined;
      case StockItemStatus.entregue:
        return Icons.check_circle_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    return Scaffold(
      body: StreamBuilder<List<StockItem>>(
        stream: firestoreService.getStockItemsStream(),
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

          final allStockItems = snapshot.data!;

          final groupedItems = <String, Map<String, dynamic>>{};

          for (var item in allStockItems) {
            final key = '${item.orderId}_${item.productId}_${item.status.name}_${item.logoType}';
            
            groupedItems.update(
              key,
              (value) {
                value['count'] = value['count'] + 1;
                return value;
              },
              ifAbsent: () => {
                'item': item,
                'count': 1,
              },
            );
          }

          final groupedList = groupedItems.values.toList();
          
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groupedList.length,
            itemBuilder: (context, index) {
              final group = groupedList[index];
              final StockItem item = group['item'];
              final int count = group['count'];

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(item.status),
                    foregroundColor: Colors.white,
                    child: Tooltip( // Tooltip para mostrar o nome do status
                      message: _getStatusName(item.status),
                      child: Icon(_getStatusIcon(item.status)),
                    ),
                  ),
                  title: Text('${item.sku} - ${item.productName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Status: ${_getStatusName(item.status)}\nPedido: #${item.orderId?.substring(0, 6).toUpperCase() ?? 'Estoque Manual'}'),
                  isThreeLine: true,
                  trailing: Text(
                    '${count.toString()} un.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
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