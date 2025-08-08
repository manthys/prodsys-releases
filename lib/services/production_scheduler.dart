// lib/services/production_scheduler.dart

import '../models/mold_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';

// Classe auxiliar para agrupar os itens do plano de produção
class ProductionPlanItem {
  final String productName;
  final String sku;
  final String logoType;
  final String clientName;
  final String orderId;
  final DateTime deliveryDeadline;
  final int totalPendingForGroup; // Total original do agrupamento
  final int quantityToProduce; // Quantidade para este dia específico
  final List<StockItem> sourceItems; // Itens originais que compõem este lote

  ProductionPlanItem({
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

  // O método principal que faz a mágica do agendamento
  Map<DateTime, List<ProductionPlanItem>> scheduleProduction({
    required List<StockItem> allPendingItems,
    required List<Mold> allMolds,
    required Map<String, Product> productCatalog,
  }) {
    // 1. Agrupar itens pendentes por uma chave única
    // A chave combina o pedido, o produto e a customização
    final demandByGroup = <String, List<StockItem>>{};
    for (var item in allPendingItems) {
      final key = '${item.orderId}_${item.productId}_${item.logoType}';
      demandByGroup.putIfAbsent(key, () => []).add(item);
    }

    // 2. Criar uma lista de 'Demand' que podemos manipular e ordenar
    var demandList = demandByGroup.entries.map((entry) {
      final firstItem = entry.value.first;
      return {
        'key': entry.key,
        'items': entry.value,
        'remaining': entry.value.length,
        // Usa o prazo do primeiro item (todos no grupo terão o mesmo prazo)
        'deadline': firstItem.deliveryDeadline?.toDate() ?? DateTime.now().add(const Duration(days: 90)),
      };
    }).toList();

    // 3. Priorizar: os com prazo final mais próximo vêm primeiro.
    demandList.sort((a, b) => (a['deadline'] as DateTime).compareTo(b['deadline'] as DateTime));
    
    final Map<DateTime, List<ProductionPlanItem>> fullProductionPlan = {};
    DateTime currentDate = DateTime.now();

    // 4. Simular os dias de produção até que toda a demanda seja agendada
    while (demandList.any((d) => (d['remaining'] as int) > 0)) {
      currentDate = _getNextWorkday(currentDate);

      // Reseta a capacidade dos moldes para o dia atual
      final dailyMoldCapacity = {for (var mold in allMolds) mold.name: mold.quantityAvailable};
      
      // 5. Itera sobre a demanda priorizada e aloca a produção
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
          
          final List<StockItem> itemsForThisRun = (demandGroup['items'] as List<StockItem>)
              // Filtro lógico para pegar apenas os itens que ainda não foram "reservados" simbolicamente
              .where((item) => item.status == StockItemStatus.aguardandoProducao)
              .take(quantityToProduce)
              .toList();

          if (itemsForThisRun.isNotEmpty) {
            final planItem = ProductionPlanItem(
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

            // Adiciona o item ao plano do dia
            fullProductionPlan.putIfAbsent(currentDate, () => []).add(planItem);

            // Atualiza os valores restantes para o próximo dia
            demandGroup['remaining'] = (demandGroup['remaining'] as int) - quantityToProduce;
            dailyMoldCapacity[moldType] = (dailyMoldCapacity[moldType] ?? 0) - quantityToProduce;

            // Marca os itens como "agendados" para não serem pegos de novo (simbolicamente)
            for (var item in itemsForThisRun) {
                // Em um cenário real mais complexo, você poderia ter um status 'agendado'
                // Aqui, a lógica de 'take' e 'remaining' já controla isso.
            }
          }
        }
      }
      
      // Salvaguarda contra loop infinito
      if (currentDate.isAfter(DateTime.now().add(const Duration(days: 365)))) {
        print("AVISO: Agendamento interrompido após 1 ano de planejamento.");
        break;
      }
    }

    return fullProductionPlan;
  }

  // Função auxiliar para obter o próximo dia útil (ignorando sábados e domingos)
  DateTime _getNextWorkday(DateTime date) {
    DateTime nextDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
    while (nextDay.weekday == DateTime.saturday || nextDay.weekday == DateTime.sunday) {
      nextDay = nextDay.add(const Duration(days: 1));
    }
    return nextDay;
  }
}