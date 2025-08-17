// lib/services/firestore_service.dart

import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:rxdart/rxdart.dart';
import '../models/client_model.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/company_settings_model.dart';
import '../models/expense_model.dart';
import '../models/mold_model.dart';
import '../models/stock_item_model.dart';
import '../models/delivery_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

DateTime _calculateDeadline(DateTime startDate, int businessDays) {
  DateTime deadline = startDate;
  int daysAdded = 0;
  while (daysAdded < businessDays) {
    deadline = deadline.add(const Duration(days: 1));
    if (deadline.weekday != DateTime.saturday && deadline.weekday != DateTime.sunday) {
      daysAdded++;
    }
  }
  return deadline;
}

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Client>> getClientsStream() => _db.collection('clients').orderBy('name').snapshots().map((snapshot) => snapshot.docs.map((doc) => Client.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addClient(Client client) => _db.collection('clients').add(client.toJson());
  Future<void> updateClient(Client client) => _db.collection('clients').doc(client.id).update(client.toJson());
  Future<void> deleteClient(String clientId) => _db.collection('clients').doc(clientId).delete();
  Future<Client?> getClientById(String clientId) async {
    final doc = await _db.collection('clients').doc(clientId).get();
    return doc.exists ? Client.fromFirestore(doc.data()!, doc.id) : null;
  }
  Stream<List<Product>> getProductsStream() => _db.collection('products').orderBy('name').snapshots().map((snapshot) => snapshot.docs.map((doc) => Product.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addProduct(Product product) => _db.collection('products').add(product.toJson());
  Future<void> updateProduct(Product product) => _db.collection('products').doc(product.id).update(product.toJson());
  Future<Product?> getProductById(String productId) async {
    final doc = await _db.collection('products').doc(productId).get();
    return doc.exists ? Product.fromFirestore(doc.data()!, doc.id) : null;
  }
  Stream<List<Order>> getOrdersStream() => _db.collection('orders').orderBy('creationDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc.data(), doc.id)).toList());
  Stream<List<Order>> getOrdersForClientStream(String clientId) => _db.collection('orders').where('clientId', isEqualTo: clientId).orderBy('creationDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc.data(), doc.id)).toList());
  Future<DocumentReference> addOrder(Order order) => _db.collection('orders').add(order.toJson());
  Future<void> updateOrder(Order order) => _db.collection('orders').doc(order.id).update(order.toJson());
  Future<void> deleteOrder(String orderId) => _db.collection('orders').doc(orderId).delete();
  Future<void> deleteStockItemsForOrder(String orderId) async {
    final querySnapshot = await _db.collection('stock_items').where('orderId', isEqualTo: orderId).get();
    final batch = _db.batch();
    for (final doc in querySnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
  Future<Order?> getOrderById(String orderId) async {
    final doc = await _db.collection('orders').doc(orderId).get();
    return doc.exists ? Order.fromFirestore(doc.data()!, doc.id) : null;
  }
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus, {bool setConfirmationDate = false}) {
    final Map<String, dynamic> dataToUpdate = {'status': newStatus.name};
    if (setConfirmationDate) dataToUpdate['confirmationDate'] = Timestamp.now();
    return _db.collection('orders').doc(orderId).update(dataToUpdate);
  }
  Future<void> updateOrderPayment(String orderId, Map<String, dynamic> dataToUpdate) => _db.collection('orders').doc(orderId).update(dataToUpdate);
  Future<void> addAttachmentUrlToOrder(String orderId, String url) => _db.collection('orders').doc(orderId).update({'attachmentUrls': FieldValue.arrayUnion([url])});
  Future<void> createStockItemsForOrder(Order order) async {
    final batch = _db.batch();
    final confirmationTime = order.confirmationDate ?? Timestamp.now();
    final deadlineDate = _calculateDeadline(confirmationTime.toDate(), 10);
    final deadlineTimestamp = Timestamp.fromDate(deadlineDate);
    for (final orderItem in order.items) {
      int neededQuantity = orderItem.quantity;
      final availableStockQuery = await _db.collection('stock_items').where('productId', isEqualTo: orderItem.productId).where('logoType', isEqualTo: orderItem.logoType).where('status', isEqualTo: StockItemStatus.emEstoque.name).where('orderId', isNull: true).limit(neededQuantity).get();
      for (final doc in availableStockQuery.docs) {
        batch.update(doc.reference, {'orderId': order.id, 'clientName': order.clientName, 'deliveryDeadline': deadlineTimestamp});
        neededQuantity--;
      }
      if (neededQuantity > 0) {
        for (int i = 0; i < neededQuantity; i++) {
          final newStockItem = StockItem(
            productId: orderItem.productId, productName: orderItem.productName, sku: orderItem.sku,
            orderId: order.id, clientName: order.clientName, status: StockItemStatus.aguardandoProducao,
            logoType: orderItem.logoType, creationDate: confirmationTime, deliveryDeadline: deadlineTimestamp,
          );
          final docRef = _db.collection('stock_items').doc();
          batch.set(docRef, newStockItem.toJson());
        }
      }
    }
    await batch.commit();
  }
  Future<void> addManualStockItem(Product product, int quantity, String logoType) async {
    final batch = _db.batch();
    int remainingQty = quantity;
    final pendingItemsQuery = await _db.collection('stock_items').where('productId', isEqualTo: product.id!).where('logoType', isEqualTo: logoType).where('status', isEqualTo: StockItemStatus.aguardandoProducao.name).orderBy('deliveryDeadline').get();
    for (var doc in pendingItemsQuery.docs) {
      if (remainingQty == 0) break;
      final pendingItemData = doc.data();
      batch.update(doc.reference, {'status': StockItemStatus.emEstoque.name, 'creationDate': Timestamp.now(), 'orderId': pendingItemData['orderId'], 'clientName': pendingItemData['clientName'], 'deliveryDeadline': pendingItemData['deliveryDeadline']});
      remainingQty--;
    }
    if (remainingQty > 0) {
      for (int i = 0; i < remainingQty; i++) {
        final newStockItem = StockItem(productId: product.id!, productName: product.name, sku: product.sku, status: StockItemStatus.emEstoque, logoType: logoType, creationDate: Timestamp.now());
        final docRef = _db.collection('stock_items').doc();
        batch.set(docRef, newStockItem.toJson());
      }
    }
    await batch.commit();
  }
  
  // ===== FUNÇÃO CORRIGIDA =====
  Future<void> adjustStockQuantity(StockItem originalItem, int initialQuantity, int newQuantity, String reason) async {
    final batch = _db.batch();
    int difference = initialQuantity - newQuantity;

    if (difference <= 0) return; // Apenas para diminuição de estoque

    // Busca os itens exatos a serem removidos, garantindo que o orderId seja nulo se o original for nulo
    Query query = _db.collection('stock_items')
        .where('productId', isEqualTo: originalItem.productId)
        .where('logoType', isEqualTo: originalItem.logoType)
        .where('status', isEqualTo: originalItem.status.name)
        .where('orderId', isEqualTo: originalItem.orderId);
        
    final itemsToRemoveSnapshot = await query.limit(difference).get();

    for (var doc in itemsToRemoveSnapshot.docs) {
      batch.delete(doc.reference);
    }
    
    // Lógica inteligente: só repõe na produção se o item pertencia a um pedido
    if (originalItem.orderId != null && 
        (originalItem.status == StockItemStatus.aguardandoProducao || originalItem.status == StockItemStatus.emEstoque)) {
      
      for (int i = 0; i < difference; i++) {
        final newItem = StockItem(
          productId: originalItem.productId, productName: originalItem.productName, sku: originalItem.sku,
          orderId: originalItem.orderId, clientName: originalItem.clientName, status: StockItemStatus.aguardandoProducao,
          logoType: originalItem.logoType, creationDate: Timestamp.now(),
          deliveryDeadline: originalItem.deliveryDeadline,
        );
        final docRef = _db.collection('stock_items').doc();
        batch.set(docRef, newItem.toJson());
      }
    }
    
    await batch.commit();
  }

  Stream<List<StockItem>> getStockItemsStream() => _db.collection('stock_items').orderBy('creationDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => StockItem.fromFirestore(doc.data(), doc.id)).toList());
  Stream<List<StockItem>> getStockItemsByStatus(StockItemStatus status) => _db.collection('stock_items').where('status', isEqualTo: status.name).orderBy('deliveryDeadline').snapshots().map((snapshot) => snapshot.docs.map((doc) => StockItem.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> launchProductionRun(List<StockItem> itemsToLaunch) async {
    final writeBatch = _db.batch();
    for (final item in itemsToLaunch) {
      final docRef = _db.collection('stock_items').doc(item.id);
      writeBatch.update(docRef, {'status': StockItemStatus.emEstoque.name});
    }
    await writeBatch.commit();
  }
  Future<void> checkAndUpdateOrderStatusAfterProduction(String orderId) async {
    final order = await getOrderById(orderId);
    if (order == null || order.status == OrderStatus.finalizado || order.status == OrderStatus.cancelado) return;
    final totalItemsInOrder = order.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final producedItemsSnapshot = await _db.collection('stock_items').where('orderId', isEqualTo: orderId).where('status', whereIn: [StockItemStatus.emEstoque.name, StockItemStatus.emTransito.name, StockItemStatus.entregue.name]).get();
    if (producedItemsSnapshot.docs.length >= totalItemsInOrder) {
      await updateOrderStatus(orderId, OrderStatus.aguardandoEntrega);
    }
  }
  Future<void> createDeliveryAndUpdateStock(Delivery delivery, List<StockItem> stockItemsToUpdate) async {
    final batch = _db.batch();
    final deliveryData = delivery.toJson();
    deliveryData['status'] = DeliveryStatus.emTransito.name;
    final deliveryRef = _db.collection('deliveries').doc();
    batch.set(deliveryRef, deliveryData);
    for (final stockItem in stockItemsToUpdate) {
      final stockRef = _db.collection('stock_items').doc(stockItem.id);
      batch.update(stockRef, {'status': StockItemStatus.emTransito.name, 'deliveryId': deliveryRef.id});
    }
    await batch.commit();
  }
  Stream<List<Delivery>> getDeliveriesForOrderStream(String orderId) => _db.collection('deliveries').where('orderId', isEqualTo: orderId).orderBy('deliveryDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => Delivery.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> confirmDeliveryAsCompleted(String orderId, String deliveryId) async {
    final batch = _db.batch();
    final deliveryRef = _db.collection('deliveries').doc(deliveryId);
    batch.update(deliveryRef, {'status': DeliveryStatus.entregue.name});
    final stockItemsSnapshot = await _db.collection('stock_items').where('deliveryId', isEqualTo: deliveryId).get();
    for (final doc in stockItemsSnapshot.docs) {
      batch.update(doc.reference, {'status': StockItemStatus.entregue.name});
    }
    await batch.commit();
    await checkIfOrderIsFullyCompleted(orderId);
  }
  Future<void> confirmFinalPaymentAndUpdateStatus(String orderId) async {
    final order = await getOrderById(orderId);
    if (order == null) return;
    await updateOrderPayment(orderId, {'amountPaid': order.finalAmount, 'paymentStatus': PaymentStatus.pagoIntegralmente.name});
    await checkIfOrderIsFullyCompleted(orderId);
  }
  Future<void> checkIfOrderIsFullyCompleted(String orderId) async {
    final order = await getOrderById(orderId);
    if (order == null || order.status == OrderStatus.finalizado) return;
    final totalItemsInOrder = order.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final deliveredItemsSnapshot = await _db.collection('stock_items').where('orderId', isEqualTo: orderId).where('status', isEqualTo: StockItemStatus.entregue.name).get();
    final allItemsDelivered = deliveredItemsSnapshot.docs.length >= totalItemsInOrder;
    final isFullyPaid = order.paymentStatus == PaymentStatus.pagoIntegralmente;
    if (allItemsDelivered && isFullyPaid) {
      await updateOrderStatus(orderId, OrderStatus.finalizado);
    }
  }
  Stream<List<Mold>> getMoldsStream() => _db.collection('molds').orderBy('name').snapshots().map((snapshot) => snapshot.docs.map((doc) => Mold.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addMold(Mold mold) => _db.collection('molds').add(mold.toJson());
  Future<void> updateMold(Mold mold) => _db.collection('molds').doc(mold.id).update(mold.toJson());
  Future<void> deleteMold(String moldId) => _db.collection('molds').doc(moldId).delete();
  Future<void> saveCompanySettings(CompanySettings settings) => _db.collection('settings').doc('company_info').set(settings.toJson());
  Future<CompanySettings> getCompanySettings() async {
    final doc = await _db.collection('settings').doc('company_info').get();
    return CompanySettings.fromFirestore(doc.data());
  }
  Stream<List<Expense>> getExpensesStream() => _db.collection('expenses').orderBy('expenseDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => Expense.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addExpense(Expense expense) => _db.collection('expenses').add(expense.toJson());
  Future<void> updateExpense(Expense expense) => _db.collection('expenses').doc(expense.id).update(expense.toJson());
  Future<void> deleteExpense(String expenseId) => _db.collection('expenses').doc(expenseId).delete();
  Stream<Map<String, dynamic>> getDataForProductionPlanStream() {
    return Rx.combineLatest3(
      getMoldsStream(),
      getStockItemsByStatus(StockItemStatus.aguardandoProducao),
      getProductsStream(),
      (List<Mold> molds, List<StockItem> pendingItems, List<Product> products) {
        return {
          'molds': molds,
          'pendingItems': pendingItems,
          'products': {for (var p in products) p.id!: p},
        };
      },
    );
  }
  Stream<Map<String, dynamic>> getDashboardStream(DateTime start, DateTime end) {
    final validStatuses = [OrderStatus.pedido.name, OrderStatus.emFabricacao.name, OrderStatus.finalizado.name, OrderStatus.aguardandoEntrega.name];
    Stream<List<Order>> ordersStream = _db.collection('orders').where('status', whereIn: validStatuses).where('creationDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('creationDate', isLessThanOrEqualTo: Timestamp.fromDate(end)).snapshots().map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc.data(), doc.id)).toList());
    Stream<List<Expense>> expensesStream = _db.collection('expenses').where('expenseDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('expenseDate', isLessThanOrEqualTo: Timestamp.fromDate(end)).snapshots().map((snapshot) => snapshot.docs.map((doc) => Expense.fromFirestore(doc.data(), doc.id)).toList());
    return Rx.combineLatest2(
      ordersStream,
      expensesStream,
      (List<Order> orders, List<Expense> expenses) {
        return {
          'orders': orders,
          'expenses': expenses,
        };
      },
    );
  }
}