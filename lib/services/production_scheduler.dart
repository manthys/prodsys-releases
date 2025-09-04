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
    DateTime? startDate,
  }) {
    final Map<DateTime, List<ProductionPlanItem>> plan = {};
    if (allPendingItems.isEmpty) return plan;

    allPendingItems.sort((a, b) => 
      (a.deliveryDeadline?.toDate() ?? DateTime(2099)).compareTo(b.deliveryDeadline?.toDate() ?? DateTime(2099))
    );
    
    final Map<String, List<StockItem>> groupedByProduct = {};
    for (var item in allPendingItems) {
      final key = '${item.productId}-${item.logoType}';
      groupedByProduct.putIfAbsent(key, () => []).add(item);
    }

    final sortedGroupEntries = groupedByProduct.entries.toList()
      ..sort((a, b) {
        final deadlineA = a.value.first.deliveryDeadline?.toDate() ?? DateTime(2099);
        final deadlineB = b.value.first.deliveryDeadline?.toDate() ?? DateTime(2099);
        return deadlineA.compareTo(deadlineB);
      });
    
    final Map<String, int> moldCapacity = {for (var mold in allMolds) mold.name: mold.quantityAvailable};
    final Map<String, DateTime> moldNextAvailableDate = {
      for (var mold in allMolds) 
        mold.name: _getNextWorkday((startDate ?? DateTime.now()).subtract(const Duration(days: 1)))
    };

    for (var entry in sortedGroupEntries) {
      List<StockItem> itemsToSchedule = List.from(entry.value);
      int totalPendingForGroup = itemsToSchedule.length;

      while (itemsToSchedule.isNotEmpty) {
        final firstItem = itemsToSchedule.first;
        final product = productCatalog[firstItem.productId];
        if (product == null) {
          itemsToSchedule.removeAt(0);
          continue;
        }

        final moldType = product.moldType;
        if (moldType.isEmpty || !moldCapacity.containsKey(moldType)) {
          itemsToSchedule.removeAt(0);
          continue;
        }

        DateTime productionDate = moldNextAvailableDate[moldType]!;
        int capacity = moldCapacity[moldType] ?? 1;
        int quantityForThisRun = itemsToSchedule.length > capacity ? capacity : itemsToSchedule.length;
        
        final itemsForThisRun = itemsToSchedule.sublist(0, quantityForThisRun);

        plan.putIfAbsent(productionDate, () => []).add(ProductionPlanItem(
          productId: firstItem.productId,
          productName: firstItem.productName,
          sku: firstItem.sku,
          logoType: firstItem.logoType,
          quantityToProduce: quantityForThisRun,
          clientName: firstItem.clientName ?? 'Estoque',
          orderId: firstItem.orderId?.substring(0,6).toUpperCase() ?? 'N/A',
          deliveryDeadline: firstItem.deliveryDeadline?.toDate() ?? DateTime(2099),
          totalPendingForGroup: totalPendingForGroup,
          sourceItems: itemsForThisRun,
        ));
        
        itemsToSchedule.removeRange(0, quantityForThisRun);
        moldNextAvailableDate[moldType] = _getNextWorkday(productionDate);
      }
    }
    return plan;
  }

  DateTime _getNextWorkday(DateTime date) {
    DateTime nextDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
    
    while (nextDay.weekday == DateTime.saturday || nextDay.weekday == DateTime.sunday) {
      nextDay = nextDay.add(const Duration(days: 1));
    }
    return nextDay;
  }
}