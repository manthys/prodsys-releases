// lib/services/production_scheduler.dart

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
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

  // =================================================================
  // LISTA DE FERIADOS (CAUCAIA, CEARÁ E NACIONAIS)
  // =================================================================
  final List<Map<String, dynamic>> fixedHolidays = [
    {'day': 1, 'month': 1},   // Confraternização Universal
    {'day': 19, 'month': 3},  // São José (Feriado CE)
    {'day': 25, 'month': 3},  // Data Magna (Feriado CE)
    {'day': 21, 'month': 4},  // Tiradentes
    {'day': 1, 'month': 5},   // Dia do Trabalho
    {'day': 7, 'month': 9},   // Independência
    {'day': 12, 'month': 10}, // Nossa Sra. Aparecida
    {'day': 15, 'month': 10}, // Emancipação de Caucaia
    {'day': 2, 'month': 11},  // Finados
    {'day': 15, 'month': 11}, // Proclamação da República
    {'day': 20, 'month': 11}, // Dia da Consciência Negra
    {'day': 8, 'month': 12},  // N. Sra. Imaculada Conceição (Caucaia)
    {'day': 25, 'month': 12}, // Natal
  ];

  DateTime _getEasterDate(int year) {
    int a = year % 19;
    int b = year ~/ 100;
    int c = year % 100;
    int d = b ~/ 4;
    int e = b % 4;
    int f = (b + 8) ~/ 25;
    int g = (b - f + 1) ~/ 3;
    int h = (19 * a + b - d - g + 15) % 30;
    int i = c ~/ 4;
    int k = c % 4;
    int l = (32 + 2 * e + 2 * i - h - k) % 7;
    int m = (a + 11 * h + 22 * l) ~/ 451;
    int month = (h + l - 7 * m + 114) ~/ 31;
    int day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  bool _isWorkingDay(DateTime date) {
    if (date.weekday == 6 || date.weekday == 7) return false;

    for (final h in fixedHolidays) {
      if (date.day == h['day'] && date.month == h['month']) return false;
    }

    final easter = _getEasterDate(date.year);
    final carnival = easter.subtract(const Duration(days: 47));
    final goodFriday = easter.subtract(const Duration(days: 2));
    final corpusChristi = easter.add(const Duration(days: 60));

    final dateCheck = DateTime(date.year, date.month, date.day);
    if (dateCheck == carnival || dateCheck == goodFriday || dateCheck == corpusChristi) return false;

    return true;
  }

  // ##### LÓGICA DE AGENDAMENTO ORIGINAL COM FERIADOS #####
  Map<DateTime, List<ProductionPlanItem>> scheduleProduction({
    required List<StockItem> allPendingItems,
    required List<Mold> allMolds,
    required Map<String, Product> productCatalog,
  }) {
    final demandList = _createDemandList(allPendingItems);

    final Map<DateTime, List<ProductionPlanItem>> fullProductionPlan = {};
    DateTime currentDate = DateTime.now().subtract(const Duration(days: 1));
    int loopGuard = 0; 

    while (demandList.any((d) => d['remaining'] as int > 0)) {
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
          final remainingForGroup = demandGroup['remaining'] as int;
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

            demandGroup['remaining'] = remainingForGroup - quantityToProduce;
            dailyMoldCapacity[moldType] = capacityForToday - quantityToProduce;
          }
        }
      }
      
      loopGuard++;
      if (loopGuard > 365) { 
        print("AVISO: Agendamento interrompido após 1 ano de planejamento para evitar loop infinito.");
        break;
      }
    }

    return fullProductionPlan;
  }

  List<Map<String, dynamic>> _createDemandList(List<StockItem> allPendingItems) {
      final groupedByOrder = groupBy(allPendingItems, (StockItem item) => item.orderId);
      final demandList = <Map<String, dynamic>>[];

      for (final orderId in groupedByOrder.keys) {
          final itemsForThisOrder = groupedByOrder[orderId]!;
          final groupedByProduct = groupBy(itemsForThisOrder, (StockItem item) => '${item.productId}_${item.logoType}');

          for (final productKey in groupedByProduct.keys) {
              final items = groupedByProduct[productKey]!;
              final firstItem = items.first;
              
              // =================================================================
              // CORREÇÃO: CONVERSÃO DIRETA DE TIMESTAMP PARA DATETIME
              // =================================================================
              final Timestamp? deadlineTimestamp = firstItem.deliveryDeadline;
              DateTime deadline;
              
              if (deadlineTimestamp != null) {
                 deadline = deadlineTimestamp.toDate();
              } else {
                 deadline = DateTime.now().add(const Duration(days: 90));
              }

              final Timestamp creationTimestamp = firstItem.creationDate;
              // Como creationDate é 'required' no seu modelo e é Timestamp, podemos converter direto
              DateTime creation = creationTimestamp.toDate();

              demandList.add({
                  'key': '${orderId}_$productKey',
                  'items': items,
                  'remaining': items.length,
                  'creationDate': creation,
                  'deadline': deadline,
              });
          }
      }

      demandList.sort((a, b) {
        int dateComp = (a['creationDate'] as DateTime).compareTo(b['creationDate'] as DateTime);
        if (dateComp != 0) return dateComp;
        return (a['deadline'] as DateTime).compareTo(b['deadline'] as DateTime);
      });

      return demandList;
  }

  // Função para pular feriados
  DateTime _getNextWorkday(DateTime date) {
    DateTime checkDate = DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
    while (!_isWorkingDay(checkDate)) {
      checkDate = checkDate.add(const Duration(days: 1));
    }
    return checkDate;
  }
}