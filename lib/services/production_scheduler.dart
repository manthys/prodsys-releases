// lib/services/production_scheduler.dart

import '../models/mold_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';

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

  Map<DateTime, List<ProductionPlanItem>> scheduleProduction({
    required List<StockItem> allPendingItems,
    required List<Mold> allMolds,
    required Map<String, Product> productCatalog,
  }) {
    final demandByGroup = <String, List<StockItem>>{};
    for (var item in allPendingItems) {
      final key = '${item.orderId}_${item.productId}_${item.logoType}';
      demandByGroup.putIfAbsent(key, () => []).add(item);
    }

    var demandList = demandByGroup.entries.map((entry) {
      final firstItem = entry.value.first;
      return {
        'key': entry.key,
        'items': entry.value,
        'remaining': entry.value.length,
        'creationDate': firstItem.creationDate.toDate(),
        'deadline': firstItem.deliveryDeadline?.toDate() ?? DateTime.now().add(const Duration(days: 90)),
      };
    }).toList();

    demandList.sort((a, b) {
      int dateComp = (a['creationDate'] as DateTime).compareTo(b['creationDate'] as DateTime);
      if (dateComp != 0) return dateComp;
      return (a['deadline'] as DateTime).compareTo(b['deadline'] as DateTime);
    });
    
    final Map<DateTime, List<ProductionPlanItem>> fullProductionPlan = {};
    DateTime currentDate = DateTime.now().subtract(const Duration(days: 1));

    while (demandList.any((d) => (d['remaining'] as int) > 0)) {
      currentDate = _getNextWorkday(currentDate);

      final dailyMoldCapacity = {for (var mold in allMolds) mold.name: mold.quantityAvailable};
      
      for (var demandGroup in demandList) {
        if ((demandGroup['remaining'] as int) == 0) continue;

        final firstItem = (demandGroup['items'] as List<StockItem>).first;
        final product = productCatalog[firstItem.productId];
        if (product == null) continue;

        final moldType = product.moldType;
        int capacityForToday = dailyMoldCapacity[moldType] ?? 0;
        
        if (capacityForToday > 0) {
          final quantityToProduce = (demandGroup['remaining'] as int) < capacityForToday 
                                      ? (demandGroup['remaining'] as int)
                                      : capacityForToday;
          
          final int alreadyTakenCount = (demandGroup['items'] as List<StockItem>).length - (demandGroup['remaining'] as int);
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

            demandGroup['remaining'] = (demandGroup['remaining'] as int) - quantityToProduce;
            dailyMoldCapacity[moldType] = (dailyMoldCapacity[moldType] ?? 0) - quantityToProduce;
          }
        }
      }
      
      if (currentDate.isAfter(DateTime.now().add(const Duration(days: 365)))) {
        print("AVISO: Agendamento interrompido após 1 ano de planejamento.");
        break;
      }
    }
    
    // =================================================================
    // PRINT 2: ADICIONADO AQUI
    // =================================================================
    print('\n--- DEBUG: RESULTADO DO AGENDADOR ---');
    if (fullProductionPlan.isEmpty) {
      print('O plano gerado está VAZIO.');
    } else {
      print('O plano gerado contém as seguintes datas:');
      fullProductionPlan.forEach((date, items) {
        print('  - Dia: $date, Itens Agendados: ${items.length}');
      });
    }
    print('-------------------------------------\n');
    // =================================================================

    return fullProductionPlan;
  }

  DateTime _getNextWorkday(DateTime date) {
    DateTime nextDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
    
    while (nextDay.weekday == DateTime.saturday || nextDay.weekday == DateTime.sunday) {
      nextDay = nextDay.add(const Duration(days: 1));
    }
    return nextDay;
  }
}