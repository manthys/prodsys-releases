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
      case StockItemStatus.entregue:
        return 'Entregue';
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

          // ===== LÓGICA DE AGRUPAMENTO COMEÇA AQUI =====
          final groupedItems = <String, Map<String, dynamic>>{};

          for (var item in allStockItems) {
            // Cria uma chave única para agrupar itens idênticos do mesmo pedido e status
            final key = '${item.orderId}_${item.productId}_${item.status.name}_${item.logoType}';
            
            groupedItems.update(
              key,
              (value) {
                // Se o grupo já existe, apenas incrementa a contagem
                value['count'] = value['count'] + 1;
                return value;
              },
              // Se o grupo não existe, cria um novo
              ifAbsent: () => {
                'item': item, // Guarda o primeiro item como referência
                'count': 1,   // Inicia a contagem em 1
              },
            );
          }

          final groupedList = groupedItems.values.toList();
          // =================================================

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
                    child: Text(
                      count.toString(), 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                  title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    'Status: ${_getStatusName(item.status)}\n'
                    'Pedido: #${item.orderId?.substring(0, 6).toUpperCase() ?? 'N/A'} | Logo: ${item.logoType}'
                  ),
                  isThreeLine: true,
                  trailing: Text(
                    'Criado em:\n${DateFormat('dd/MM/yy').format(item.creationDate.toDate())}',
                    textAlign: TextAlign.right,
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