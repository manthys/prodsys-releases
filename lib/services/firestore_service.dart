// lib/services/firestore_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:flutter/material.dart' hide Order;
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../models/client_model.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';
import '../models/company_settings_model.dart';
import '../models/expense_model.dart';
import '../models/mold_model.dart';
import '../models/stock_item_model.dart';
import '../models/delivery_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class GroupedStockResult {
  final Map<String, List<StockItem>> stockByOrderId;
  GroupedStockResult({required this.stockByOrderId});
}

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

  Future<void> reallocateStockItem({
    required StockItem stockItemToMove,
    required Order targetOrder,
    required int quantity,
  }) async {
    const projectId = "sistema-gestao-cliente";
    const region = "us-central1";
    const functionName = "reallocateStockItem";
    const mySecretKey = "COLOQUE-AQUI-SUA-SENHA-LONGA-E-ALEATORIA";

    final url = Uri.parse('https://$region-$projectId.cloudfunctions.net/$functionName');
    final body = json.encode({
      'data': {
        'productId': stockItemToMove.productId,
        'logoType': stockItemToMove.logoType,
        'sourceOrderId': stockItemToMove.orderId,
        'targetOrderId': targetOrder.id,
        'targetOrderClientName': targetOrder.clientName,
        'targetOrderDeliveryDate': targetOrder.deliveryDate?.toDate().toIso8601String(),
        'quantity': quantity,
      }
    });

    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $mySecretKey',
        },
        body: body,
      );
      if (response.statusCode == 200) {
        debugPrint('Cloud Function executada com sucesso!');
      } else {
        throw Exception('Falha na Cloud Function. Status: ${response.statusCode}, Corpo: ${response.body}');
      }
    } catch (e) {
      debugPrint('Ocorreu um erro inesperado na chamada HTTP: $e');
      throw Exception('Falha na comunicação com o servidor de realocação.');
    }
  }
  
  Future<void> confirmRefundAndFinalizeOrder(String orderId) async {
    final orderRef = _db.collection('orders').doc(orderId);
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    final doc = await orderRef.get();
    if (!doc.exists) {
      throw Exception("Pedido não encontrado.");
    }
    
    String currentNotes = (doc.data() as Map<String, dynamic>)['notes'] ?? '';
    
    currentNotes = currentNotes.replaceAll(RegExp(r'\n\[SISTEMA\] Valor a devolver ao cliente: R\$\d+\.\d{2}\.'), '');
    
    String newNotes = currentNotes.trim() + '\n[SISTEMA] Devolução confirmada em $formattedDate.';
    
    await orderRef.update({'notes': newNotes});

    await checkIfOrderIsFullyCompleted(orderId);
  }

  Future<void> addStockItemsToProductionQueue({
    required Product product,
    required int quantity,
    required String logoType,
  }) async {
    final batch = _db.batch();
    final stockItemsCollection = _db.collection('stock_items');

    for (int i = 0; i < quantity; i++) {
      final newStockItem = StockItem(
        productId: product.id!,
        productName: product.name,
        sku: product.sku,
        status: StockItemStatus.aguardandoProducao,
        logoType: logoType,
        orderId: null,
        clientName: 'Estoque Interno',
        creationDate: Timestamp.now(),
        deliveryDeadline: Timestamp.fromDate(DateTime.now().add(const Duration(days: 90))),
      );
      final docRef = stockItemsCollection.doc();
      batch.set(docRef, newStockItem.toJson());
    }
    await batch.commit();
  }

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
  Future<void> updateInProductionOrder(Order originalOrder, Order updatedOrder) async {
    final batch = _db.batch();
    final stockItemsCollection = _db.collection('stock_items');
    final originalItemsMap = {for (var item in originalOrder.items) '${item.productId}-${item.logoType}': item};
    final updatedItemsMap = {for (var item in updatedOrder.items) '${item.productId}-${item.logoType}': item};
    for (final key in updatedItemsMap.keys) {
      final updatedItem = updatedItemsMap[key]!;
      final originalItem = originalItemsMap[key];
      if (originalItem == null) {
        for (int i = 0; i < updatedItem.quantity; i++) {
          final newStockItem = StockItem(
            productId: updatedItem.productId, productName: updatedItem.productName, sku: updatedItem.sku,
            orderId: originalOrder.id, clientName: originalOrder.clientName, status: StockItemStatus.aguardandoProducao,
            logoType: updatedItem.logoType, creationDate: Timestamp.now(), deliveryDeadline: originalOrder.deliveryDate,
          );
          final docRef = stockItemsCollection.doc();
          batch.set(docRef, newStockItem.toJson());
        }
      } else if (updatedItem.quantity > originalItem.quantity) {
        final difference = updatedItem.quantity - originalItem.quantity;
        for (int i = 0; i < difference; i++) {
          final newStockItem = StockItem(
            productId: updatedItem.productId, productName: updatedItem.productName, sku: updatedItem.sku,
            orderId: originalOrder.id, clientName: originalOrder.clientName, status: StockItemStatus.aguardandoProducao,
            logoType: updatedItem.logoType, creationDate: Timestamp.now(), deliveryDeadline: originalOrder.deliveryDate,
          );
          final docRef = stockItemsCollection.doc();
          batch.set(docRef, newStockItem.toJson());
        }
      }
    }
    for (final key in originalItemsMap.keys) {
      final originalItem = originalItemsMap[key]!;
      final updatedItem = updatedItemsMap[key];
      int quantityToRemove = 0;
      if (updatedItem == null) {
        quantityToRemove = originalItem.quantity;
      } else if (updatedItem.quantity < originalItem.quantity) {
        quantityToRemove = originalItem.quantity - updatedItem.quantity;
      }
      if (quantityToRemove > 0) {
        final pendingItemsQuery = await stockItemsCollection.where('orderId', isEqualTo: originalOrder.id).where('productId', isEqualTo: originalItem.productId).where('logoType', isEqualTo: originalItem.logoType).where('status', isEqualTo: StockItemStatus.aguardandoProducao.name).limit(quantityToRemove).get();
        for (final doc in pendingItemsQuery.docs) {
          batch.delete(doc.reference);
          quantityToRemove--;
        }
        if (quantityToRemove > 0) {
          final producedItemsQuery = await stockItemsCollection.where('orderId', isEqualTo: originalOrder.id).where('productId', isEqualTo: originalItem.productId).where('logoType', isEqualTo: originalItem.logoType).where('status', whereIn: [StockItemStatus.emEstoque.name, StockItemStatus.emTransito.name]).limit(quantityToRemove).get();
          for (final doc in producedItemsQuery.docs) {
            batch.update(doc.reference, {'orderId': null, 'clientName': null, 'deliveryDeadline': null, 'status': StockItemStatus.emEstoque.name});
          }
        }
      }
    }
    final orderRef = _db.collection('orders').doc(originalOrder.id);
    double newAmountPaid = originalOrder.amountPaid;
    PaymentStatus newPaymentStatus = originalOrder.paymentStatus;
    if (updatedOrder.finalAmount < originalOrder.amountPaid) {
        double refundAmount = originalOrder.amountPaid - updatedOrder.finalAmount;
        newAmountPaid = updatedOrder.finalAmount;
        newPaymentStatus = PaymentStatus.pagoIntegralmente;
        String newNotes = (updatedOrder.notes ?? '') + '\n[SISTEMA] Valor a devolver ao cliente: R\$${refundAmount.toStringAsFixed(2)}.';
        updatedOrder = updatedOrder.copyWith(notes: newNotes);
    }
    batch.update(orderRef, {'items': updatedOrder.items.map((item) => item.toJson()).toList(),'totalItemsAmount': updatedOrder.totalItemsAmount,'shippingCost': updatedOrder.shippingCost,'discount': updatedOrder.discount,'finalAmount': updatedOrder.finalAmount,'notes': updatedOrder.notes,'paymentMethod': updatedOrder.paymentMethod,'deliveryAddress': updatedOrder.deliveryAddress.toJson(),'amountPaid': newAmountPaid,'paymentStatus': newPaymentStatus.name});
    await batch.commit();
    await checkAndUpdateOrderStatusAfterProduction(originalOrder.id!);
  }
  Future<void> deleteOrder(String orderId) => _db.collection('orders').doc(orderId).delete();

  Future<void> handleOrderCancellation(String orderId) async {
    final batch = _db.batch();
    final stockItemsCollection = _db.collection('stock_items');

    final querySnapshot = await stockItemsCollection.where('orderId', isEqualTo: orderId).get();

    for (final doc in querySnapshot.docs) {
      final stockItem = StockItem.fromFirestore(doc.data(), doc.id);
      
      if (stockItem.status == StockItemStatus.emEstoque) {
        batch.update(doc.reference, {
          'orderId': null,
          'clientName': null,
          'deliveryDeadline': null,
          'reallocatedFrom': 'Cancelado do Pedido #${orderId.substring(0, 6).toUpperCase()}',
        });
      } else {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }
  
  // ##### FUNÇÃO RE-ADICIONADA AQUI #####
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
  Future<void> addManualStockItem(Product product, int quantity, String logoType, {required bool fulfillPendingOrders}) async {
    final batch = _db.batch();
    int remainingQty = quantity;
    if (fulfillPendingOrders) {
      final pendingItemsQuery = await _db.collection('stock_items').where('productId', isEqualTo: product.id!).where('logoType', isEqualTo: logoType).where('status', isEqualTo: StockItemStatus.aguardandoProducao.name).orderBy('deliveryDeadline').get();
      for (var doc in pendingItemsQuery.docs) {
        if (remainingQty == 0) break;
        final pendingItemData = doc.data();
        batch.update(doc.reference, {'status': StockItemStatus.emEstoque.name, 'creationDate': Timestamp.now(), 'orderId': pendingItemData['orderId'], 'clientName': pendingItemData['clientName'], 'deliveryDeadline': pendingItemData['deliveryDeadline']});
        remainingQty--;
      }
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
  Future<void> adjustStockQuantity(StockItem originalItem, int initialQuantity, int newQuantity, String reason) async {
    final batch = _db.batch();
    int difference = initialQuantity - newQuantity;
    if (difference <= 0) return;
    Query query = _db.collection('stock_items').where('productId', isEqualTo: originalItem.productId).where('logoType', isEqualTo: originalItem.logoType).where('status', isEqualTo: originalItem.status.name).where('orderId', isEqualTo: originalItem.orderId);
    final itemsToRemoveSnapshot = await query.limit(difference).get();
    for (var doc in itemsToRemoveSnapshot.docs) {
      batch.delete(doc.reference);
    }
    if (originalItem.orderId != null && (originalItem.status == StockItemStatus.aguardandoProducao || originalItem.status == StockItemStatus.emEstoque)) {
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
    if (order == null || order.status == OrderStatus.finalizado || order.status == OrderStatus.cancelado || order.status == OrderStatus.aguardandoEntrega) return;
    final totalItemsInOrder = order.items.fold<int>(0, (sum, item) => sum + item.quantity);
    if (totalItemsInOrder == 0) {
        await updateOrderStatus(orderId, OrderStatus.aguardandoEntrega);
        return;
    }
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
    if (totalItemsInOrder == 0) {
      if (order.paymentStatus == PaymentStatus.pagoIntegralmente) {
        await updateOrderStatus(orderId, OrderStatus.finalizado);
      }
      return;
    }
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
        return {'molds': molds, 'pendingItems': pendingItems, 'products': {for (var p in products) p.id!: p},};
      },
    );
  }
  Stream<Map<String, dynamic>> getDashboardStream(DateTime start, DateTime end) {
    final validStatuses = [OrderStatus.pedido.name, OrderStatus.emFabricacao.name, OrderStatus.finalizado.name, OrderStatus.aguardandoEntrega.name];
    Stream<List<Order>> ordersStream = _db.collection('orders').where('status', whereIn: validStatuses).where('creationDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('creationDate', isLessThanOrEqualTo: Timestamp.fromDate(end)).snapshots().map((snapshot) => snapshot.docs.map((doc) => Order.fromFirestore(doc.data(), doc.id)).toList());
    Stream<List<Expense>> expensesStream = _db.collection('expenses').where('expenseDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start)).where('expenseDate', isLessThanOrEqualTo: Timestamp.fromDate(end)).snapshots().map((snapshot) => snapshot.docs.map((doc) => Expense.fromFirestore(doc.data(), doc.id)).toList());
    return Rx.combineLatest2(
      ordersStream, expensesStream,
      (List<Order> orders, List<Expense> expenses) {
        return {'orders': orders,'expenses': expenses,};
      },
    );
  }

  Future<GroupedStockResult> findAvailableStockForOrder(Order order) async {
    final Map<String, List<StockItem>> stockByOrderId = {};
    final neededItems = { for (var item in order.items) '${item.productId}-${item.logoType}' };

    for (var key in neededItems) {
      final parts = key.split('-');
      final productId = parts[0];
      final logoType = parts[1];

      final broadQuery = await _db
          .collection('stock_items')
          .where('productId', isEqualTo: productId)
          .where('logoType', isEqualTo: logoType)
          .where('status', isEqualTo: StockItemStatus.emEstoque.name)
          .get();

      for (final doc in broadQuery.docs) {
        final item = StockItem.fromFirestore(doc.data(), doc.id);
        if (item.orderId == null) {
          stockByOrderId.putIfAbsent('general', () => []).add(item);
        } else if (item.orderId != order.id) {
          stockByOrderId.putIfAbsent(item.orderId!, () => []).add(item);
        }
      }
    }
    return GroupedStockResult(stockByOrderId: stockByOrderId);
  }

  Future<void> processSmartAllocationForOrder(
    Order forOrder,
    List<StockItem> chosenItems,
  ) async {
    if (chosenItems.isEmpty) {
      await _createProductionItemsForOrder(forOrder);
      return;
    }

    final stockItemsCollection = _db.collection('stock_items');
    final batch = _db.batch();
    
    Map<String, int> neededQtyMap = {
      for (var item in forOrder.items) '${item.productId}-${item.logoType}': item.quantity
    };

    for (final stockItem in chosenItems) {
      final key = '${stockItem.productId}-${stockItem.logoType}';
      if ((neededQtyMap[key] ?? 0) > 0) {
        
        batch.delete(stockItemsCollection.doc(stockItem.id!));

        final newItemForNewOrder = StockItem(
          productId: stockItem.productId, productName: stockItem.productName, sku: stockItem.sku,
          orderId: forOrder.id, clientName: forOrder.clientName, status: StockItemStatus.emEstoque,
          logoType: stockItem.logoType, creationDate: stockItem.creationDate,
          deliveryDeadline: forOrder.deliveryDate,
          reallocatedFrom: stockItem.orderId == null ? 'Estoque Geral' : 'Pedido #${stockItem.orderId?.substring(0,6).toUpperCase()}'
        );
        batch.set(stockItemsCollection.doc(), newItemForNewOrder.toJson());
        
        if (stockItem.orderId != null) {
          final replacementItem = StockItem(
            productId: stockItem.productId, productName: stockItem.productName, sku: stockItem.sku,
            orderId: stockItem.orderId, clientName: stockItem.clientName, 
            status: StockItemStatus.aguardandoProducao, logoType: stockItem.logoType,
            creationDate: Timestamp.now(), deliveryDeadline: stockItem.deliveryDeadline,
            reallocatedFrom: 'Emprestado para Pedido #${forOrder.id?.substring(0, 6).toUpperCase()}'
          );
          batch.set(stockItemsCollection.doc(), replacementItem.toJson());
        }

        neededQtyMap[key] = neededQtyMap[key]! - 1;
      }
    }
    
    for (final orderItem in forOrder.items) {
      final key = '${orderItem.productId}-${orderItem.logoType}';
      final remainingQty = neededQtyMap[key] ?? 0;
      if (remainingQty > 0) {
        for (int i = 0; i < remainingQty; i++) {
          final newStockItem = StockItem(
            productId: orderItem.productId, productName: orderItem.productName, sku: orderItem.sku,
            orderId: forOrder.id, clientName: forOrder.clientName, status: StockItemStatus.aguardandoProducao,
            logoType: orderItem.logoType, creationDate: Timestamp.now(), 
            deliveryDeadline: forOrder.deliveryDate,
          );
          batch.set(stockItemsCollection.doc(), newStockItem.toJson());
        }
      }
    }
    
    await batch.commit();
    await checkAndUpdateOrderStatusAfterProduction(forOrder.id!);
  }

  Future<void> _createProductionItemsForOrder(Order order) async {
    final batch = _db.batch();
    final stockItemsCollection = _db.collection('stock_items');

    for (final item in order.items) {
      for (int i = 0; i < item.quantity; i++) {
        final newStockItem = StockItem(
          productId: item.productId,
          productName: item.productName,
          sku: item.sku,
          orderId: order.id,
          clientName: order.clientName,
          status: StockItemStatus.aguardandoProducao,
          logoType: item.logoType,
          creationDate: Timestamp.now(),
          deliveryDeadline: order.deliveryDate,
        );
        batch.set(stockItemsCollection.doc(), newStockItem.toJson());
      }
    }
    await batch.commit();
  }

  Future<void> deallocateStockItems({
    required StockItem stockItemToDeallocate,
    required int quantity,
  }) async {
    final batch = _db.batch();
    final stockItemsCollection = _db.collection('stock_items');

    final querySnapshot = await stockItemsCollection
      .where('orderId', isEqualTo: stockItemToDeallocate.orderId)
      .where('productId', isEqualTo: stockItemToDeallocate.productId)
      .where('logoType', isEqualTo: stockItemToDeallocate.logoType)
      .where('status', isEqualTo: StockItemStatus.emEstoque.name)
      .limit(quantity)
      .get();
    
    final itemsToDeallocateIds = querySnapshot.docs.map((doc) => doc.id).toList();

    for (final itemId in itemsToDeallocateIds) {
      batch.update(stockItemsCollection.doc(itemId), {
        'orderId': null,
        'clientName': null,
        'deliveryDeadline': null,
        'reallocatedFrom': 'Retornado do Pedido #${stockItemToDeallocate.orderId?.substring(0,6).toUpperCase()}'
      });
    }

    for (int i = 0; i < quantity; i++) {
      final replacementItem = StockItem(
        productId: stockItemToDeallocate.productId,
        productName: stockItemToDeallocate.productName,
        sku: stockItemToDeallocate.sku,
        orderId: stockItemToDeallocate.orderId,
        clientName: stockItemToDeallocate.clientName,
        status: StockItemStatus.aguardandoProducao,
        logoType: stockItemToDeallocate.logoType,
        creationDate: Timestamp.now(),
        deliveryDeadline: stockItemToDeallocate.deliveryDeadline,
      );
      batch.set(stockItemsCollection.doc(), replacementItem.toJson());
    }

    await batch.commit();
    await checkAndUpdateOrderStatusAfterProduction(stockItemToDeallocate.orderId!);
  }
}