// lib/services/production_simulator.dart

import '../models/mold_model.dart';
import '../models/order_item_model.dart';
import '../models/product_model.dart';
import '../models/stock_item_model.dart';
import './firestore_service.dart';

class ProductionSimulator {
  final FirestoreService _firestoreService;

  ProductionSimulator(this._firestoreService);

  Future<DateTime> estimateCompletionDate(List<OrderItem> newItems) async {
    // 1. CALCULA A DATA MÍNIMA (REGRA DOS 10 DIAS ÚTEIS)
    final minimumLeadTimeDate = _calculateFutureWorkday(DateTime.now(), 10);

    // 2. OBTÉM O ESTADO ATUAL DA PRODUÇÃO
    final productionData = await _firestoreService.getDataForProductionPlanStream().first;
    final List<Mold> allMolds = productionData['molds'];
    final List<StockItem> pendingStockItems = productionData['pendingItems'];
    final Map<String, Product> productCatalog = productionData['products'];

    if (newItems.isEmpty) {
      return minimumLeadTimeDate;
    }

    // 3. IDENTIFICA OS MOLDES NECESSÁRIOS PARA OS NOVOS ITENS
    final requiredMoldTypes = newItems
        .map((item) => productCatalog[item.productId]?.moldType)
        .where((moldType) => moldType != null)
        .toSet();

    DateTime latestDate = DateTime(1970); // Data inicial bem antiga

    // 4. PARA CADA MOLDE NECESSÁRIO, CALCULA A DATA DE CONCLUSÃO DA SUA FILA
    for (var moldType in requiredMoldTypes) {
      // Encontra o molde correspondente para saber a capacidade
      final mold = allMolds.firstWhere((m) => m.name == moldType, orElse: () => Mold(name: moldType!, quantityAvailable: 1));
      final capacity = mold.quantityAvailable > 0 ? mold.quantityAvailable : 1;

      // Calcula a demanda PENDENTE para este tipo de molde
      int pendingDemand = pendingStockItems
          .where((item) => productCatalog[item.productId]?.moldType == moldType)
          .length;
      
      // Calcula a demanda NOVA para este tipo de molde
      int newDemand = newItems
          .where((item) => productCatalog[item.productId]?.moldType == moldType)
          .fold(0, (sum, item) => sum + item.quantity);
      
      int totalDemandForMold = pendingDemand + newDemand;

      if (totalDemandForMold > 0) {
        int daysNeeded = (totalDemandForMold / capacity).ceil();
        DateTime moldCompletionDate = _calculateFutureWorkday(DateTime.now(), daysNeeded);
        
        if (moldCompletionDate.isAfter(latestDate)) {
          latestDate = moldCompletionDate;
        }
      }
    }

    final simulatedDate = latestDate;
    
    // 5. A DATA FINAL É A MAIS LONGA ENTRE A DATA SIMULADA E A DATA MÍNIMA
    if (simulatedDate.isAfter(minimumLeadTimeDate)) {
      return simulatedDate;
    } else {
      return minimumLeadTimeDate;
    }
  }
  
  DateTime _calculateFutureWorkday(DateTime startDate, int businessDays) {
    DateTime futureDate = startDate;
    int daysAdded = 0;
    while (daysAdded < businessDays) {
      futureDate = futureDate.add(const Duration(days: 1));
      if (futureDate.weekday != DateTime.saturday && futureDate.weekday != DateTime.sunday) {
        daysAdded++;
      }
    }
    return futureDate;
  }
}