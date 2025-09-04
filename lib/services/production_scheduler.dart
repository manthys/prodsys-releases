// lib/services/production_scheduler.dart

import 'package:collection/collection.dart';
import '../models/mold_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';

// Classe auxiliar para agrupar os itens do plano de produção
class ProductionPlanItem {
  final String productId;
  final String productName;
  final String sku;
  final String logoType;
  final String clientName;
  final String orderId;
  final DateTime deliveryDeadline;
  final int totalPendingForGroup;
  final int quantityToProduce;
  final List<StockItem> sourceItems;

  ProductionPlanItem({
    required this.productId,
    required this.productName,
    required this.sku,
    required this.logoType,
    required this.clientName,
    required this.orderId,
    required this.deliveryDeadline,
    required this.totalPendingForGroup,
    required this.quantityToProduce,
    required this.sourceItems,
  });
}

class ProductionScheduler {

  // ##### LÓGICA DE AGENDAMENTO COMPLETAMENTE REESCRITA #####
  Map<DateTime, List<ProductionPlanItem>> scheduleProduction({
    required List<StockItem> allPendingItems,
    required List<Mold> allMolds,
    required Map<String, Product> productCatalog,
  }) {
    // 1. Cria uma lista de "demandas" a partir dos itens pendentes.
    //    Cada demanda é um grupo de itens idênticos para um pedido específico.
    final demandList = _createDemandList(allPendingItems);

    final Map<DateTime, List<ProductionPlanItem>> fullProductionPlan = {};
    DateTime currentDate = DateTime.now().subtract(const Duration(days: 1));
    int loopGuard = 0; // Para evitar loops infinitos

    // 2. Continua agendando enquanto houver demanda restante.
    while (demandList.any((d) => d['remaining'] as int > 0)) {
      currentDate = _getNextWorkday(currentDate);

      // Reseta a capacidade diária das formas para cada novo dia.
      final dailyMoldCapacity = {for (var mold in allMolds) mold.name: mold.quantityAvailable};
      
      // 3. Itera sobre a lista de demandas para tentar agendar a produção.
      for (var demandGroup in demandList) {
        if ((demandGroup['remaining'] as int) == 0) continue;

        final firstItem = (demandGroup['items'] as List<StockItem>).first;
        final product = productCatalog[firstItem.productId];
        if (product == null) continue;

        final moldType = product.moldType;
        int capacityForToday = dailyMoldCapacity[moldType] ?? 0;
        
        if (capacityForToday > 0) {
          final remainingForGroup = demandGroup['remaining'] as int;
          // A quantidade a produzir é o menor valor entre a capacidade da forma e o que falta para aquele lote.
          final quantityToProduce = remainingForGroup < capacityForToday ? remainingForGroup : capacityForToday;
          
          final int alreadyTakenCount = (demandGroup['items'] as List<StockItem>).length - remainingForGroup;
          final List<StockItem> itemsForThisRun = (demandGroup['items'] as List<StockItem>)
              .skip(alreadyTakenCount)
              .take(quantityToProduce)
              .toList();

          if (itemsForThisRun.isNotEmpty) {
            final planItem = ProductionPlanItem(
              productId: firstItem.productId,
              productName: firstItem.productName,
              sku: firstItem.sku,
              logoType: firstItem.logoType,
              clientName: firstItem.clientName ?? 'N/A',
              orderId: firstItem.orderId?.substring(0,6).toUpperCase() ?? 'N/A',
              deliveryDeadline: demandGroup['deadline'] as DateTime,
              totalPendingForGroup: (demandGroup['items'] as List<StockItem>).length,
              quantityToProduce: quantityToProduce,
              sourceItems: itemsForThisRun,
            );

            fullProductionPlan.putIfAbsent(currentDate, () => []).add(planItem);

            // Atualiza o que resta da demanda e da capacidade da forma.
            demandGroup['remaining'] = remainingForGroup - quantityToProduce;
            dailyMoldCapacity[moldType] = capacityForToday - quantityToProduce;
          }
        }
      }
      
      loopGuard++;
      if (loopGuard > 365) { // Se o agendamento passar de 1 ano, algo está errado.
        print("AVISO: Agendamento interrompido após 1 ano de planejamento para evitar loop infinito.");
        break;
      }
    }

    return fullProductionPlan;
  }

  // Novo método auxiliar para criar a lista de demandas de forma organizada
  List<Map<String, dynamic>> _createDemandList(List<StockItem> allPendingItems) {
      // Agrupa primeiro por pedido, depois por tipo de produto dentro de cada pedido.
      final groupedByOrder = groupBy(allPendingItems, (StockItem item) => item.orderId);
      final demandList = <Map<String, dynamic>>[];

      for (final orderId in groupedByOrder.keys) {
          final itemsForThisOrder = groupedByOrder[orderId]!;
          final groupedByProduct = groupBy(itemsForThisOrder, (StockItem item) => '${item.productId}_${item.logoType}');

          for (final productKey in groupedByProduct.keys) {
              final items = groupedByProduct[productKey]!;
              final firstItem = items.first;
              demandList.add({
                  'key': '${orderId}_$productKey',
                  'items': items,
                  'remaining': items.length,
                  'creationDate': firstItem.creationDate.toDate(),
                  'deadline': firstItem.deliveryDeadline?.toDate() ?? DateTime.now().add(const Duration(days: 90)),
              });
          }
      }

      // Ordena a lista de demandas para priorizar os pedidos mais antigos e com prazo mais curto.
      demandList.sort((a, b) {
        int dateComp = (a['creationDate'] as DateTime).compareTo(b['creationDate'] as DateTime);
        if (dateComp != 0) return dateComp;
        return (a['deadline'] as DateTime).compareTo(b['deadline'] as DateTime);
      });

      return demandList;
  }

  DateTime _getNextWorkday(DateTime date) {
    DateTime nextDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
    
    while (nextDay.weekday == DateTime.saturday || nextDay.weekday == DateTime.sunday) {
      nextDay = nextDay.add(const Duration(days: 1));
    }
    return nextDay;
  }
}