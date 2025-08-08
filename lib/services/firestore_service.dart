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

  // --- CLIENTES ---
  Stream<List<Client>> getClientsStream() => _db.collection('clients').orderBy('name').snapshots().map((snapshot) => snapshot.docs.map((doc) => Client.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addClient(Client client) => _db.collection('clients').add(client.toJson());
  Future<void> updateClient(Client client) => _db.collection('clients').doc(client.id).update(client.toJson());
  Future<void> deleteClient(String clientId) => _db.collection('clients').doc(clientId).delete();
  Future<Client?> getClientById(String clientId) async {
    final doc = await _db.collection('clients').doc(clientId).get();
    return doc.exists ? Client.fromFirestore(doc.data()!, doc.id) : null;
  }

  // --- PRODUTOS (CATÁLOGO) ---
  Stream<List<Product>> getProductsStream() => _db.collection('products').orderBy('name').snapshots().map((snapshot) => snapshot.docs.map((doc) => Product.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addProduct(Product product) => _db.collection('products').add(product.toJson());
  Future<void> updateProduct(Product product) => _db.collection('products').doc(product.id).update(product.toJson());
  Future<Product?> getProductById(String productId) async {
    final doc = await _db.collection('products').doc(productId).get();
    return doc.exists ? Product.fromFirestore(doc.data()!, doc.id) : null;
  }
  
  // --- PEDIDOS ---
  Stream<List<Order>> getOrdersStream() => _db.collection('orders').orderBy('creationDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc.data(), doc.id)).toList());
  
  // NOVA FUNÇÃO PARA BUSCAR PEDIDOS DE UM CLIENTE ESPECÍFICO
  Stream<List<Order>> getOrdersForClientStream(String clientId) {
    return _db
        .collection('orders')
        .where('clientId', isEqualTo: clientId)
        .orderBy('creationDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc.data(), doc.id)).toList());
  }

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
    if (setConfirmationDate) {
      dataToUpdate['confirmationDate'] = Timestamp.now();
    }
    return _db.collection('orders').doc(orderId).update(dataToUpdate);
  }
  Future<void> updateOrderPayment(String orderId, Map<String, dynamic> dataToUpdate) {
    return _db.collection('orders').doc(orderId).update(dataToUpdate);
  }
  Future<void> addAttachmentUrlToOrder(String orderId, String url) => _db.collection('orders').doc(orderId).update({'attachmentUrls': FieldValue.arrayUnion([url])});
  Future<List<Order>> getOrdersInDateRange(DateTime start, DateTime end) async {
    final validStatuses = [OrderStatus.pedido.name, OrderStatus.emFabricacao.name, OrderStatus.finalizado.name, OrderStatus.aguardandoEntrega.name];
    final snapshot = await _db.collection('orders').where('status', whereIn: validStatuses).where('creationDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('creationDate', isLessThanOrEqualTo: Timestamp.fromDate(end)).get();
    return snapshot.docs.map((doc) => Order.fromFirestore(doc.data(), doc.id)).toList();
  }

  // --- ITENS DE ESTOQUE E PRODUÇÃO ---
  Future<void> createStockItemsForOrder(Order order) {
    final batch = _db.batch();
    final confirmationTime = order.confirmationDate ?? Timestamp.now();
    final deadlineDate = _calculateDeadline(confirmationTime.toDate(), 10);
    final deadlineTimestamp = Timestamp.fromDate(deadlineDate);
    for (final orderItem in order.items) {
      for (int i = 0; i < orderItem.quantity; i++) {
        final newStockItem = StockItem(productId: orderItem.productId, productName: orderItem.productName, sku: orderItem.sku, orderId: order.id, clientName: order.clientName, status: StockItemStatus.aguardandoProducao, logoType: orderItem.logoType, creationDate: confirmationTime, deliveryDeadline: deadlineTimestamp);
        final docRef = _db.collection('stock_items').doc();
        batch.set(docRef, newStockItem.toJson());
      }
    }
    return batch.commit();
  }
  Future<void> addManualStockItem(Product product, int quantity, String logoType) {
    final batch = _db.batch();
    for (int i = 0; i < quantity; i++) {
      final newStockItem = StockItem(productId: product.id!, productName: product.name, sku: product.sku, status: StockItemStatus.emEstoque, logoType: logoType, creationDate: Timestamp.now());
      final docRef = _db.collection('stock_items').doc();
      batch.set(docRef, newStockItem.toJson());
    }
    return batch.commit();
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
    if (order == null) return;
    if (order.status == OrderStatus.finalizado || order.status == OrderStatus.cancelado) {
      return;
    }
    final totalItemsInOrder = order.items.fold<int>(0, (sum, item) => sum + item.quantity);
    final producedItemsSnapshot = await _db.collection('stock_items').where('orderId', isEqualTo: orderId).where('status', isEqualTo: StockItemStatus.emEstoque.name).get();
    final producedItemsCount = producedItemsSnapshot.docs.length;
    if (producedItemsCount >= totalItemsInOrder) {
      await updateOrderStatus(orderId, OrderStatus.aguardandoEntrega);
    }
  }

  // --- FORMAS (MOLDS) ---
  Stream<List<Mold>> getMoldsStream() => _db.collection('molds').orderBy('name').snapshots().map((snapshot) => snapshot.docs.map((doc) => Mold.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addMold(Mold mold) => _db.collection('molds').add(mold.toJson());
  Future<void> updateMold(Mold mold) => _db.collection('molds').doc(mold.id).update(mold.toJson());
  Future<void> deleteMold(String moldId) => _db.collection('molds').doc(moldId).delete();

  // --- CONFIGURAÇÕES ---
  Future<void> saveCompanySettings(CompanySettings settings) => _db.collection('settings').doc('company_info').set(settings.toJson());
  Future<CompanySettings> getCompanySettings() async {
    final doc = await _db.collection('settings').doc('company_info').get();
    return CompanySettings.fromFirestore(doc.data());
  }
  
  // --- DESPESAS ---
  Stream<List<Expense>> getExpensesStream() => _db.collection('expenses').orderBy('expenseDate', descending: true).snapshots().map((snapshot) => snapshot.docs.map((doc) => Expense.fromFirestore(doc.data(), doc.id)).toList());
  Future<void> addExpense(Expense expense) => _db.collection('expenses').add(expense.toJson());
  Future<void> updateExpense(Expense expense) => _db.collection('expenses').doc(expense.id).update(expense.toJson());
  Future<void> deleteExpense(String expenseId) => _db.collection('expenses').doc(expenseId).delete();
  
  // --- QUERIES COMPOSTAS ---
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