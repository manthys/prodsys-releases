import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'order_item_model.dart';
import 'address_model.dart';
import 'payment_distribution_model.dart';

enum OrderStatus { 
  cotacao, 
  pedido, 
  emFabricacao, 
  aguardandoEntrega, 
  aguardandoPagamentoFinal,
  finalizado, 
  cancelado 
}
enum PaymentStatus { aguardandoSinal, sinalPago, pagoIntegralmente }

class Order {
  final String? id;
  final String? buyerName; // <-- ADICIONADO
  final String? buyerPhone; // <-- ADICIONADO
  final String? buyerEmail; // <-- ADICIONADO
  final String clientId;
  final String clientName;
  final List<OrderItem> items;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final Timestamp creationDate;
  final Timestamp? confirmationDate;
  final Timestamp? deliveryDate;
  
  final double totalItemsAmount;
  final double shippingCost;
  final double discount;
  final double finalAmount;
  
  final List<PaymentDistribution> paymentDistributions;

  final String? paymentTerms;
  final String paymentMethod;
  final String? notes;
  
  final List<String> attachmentUrls;
  final String createdByUserId;
  final String createdByUserName;
  final Address deliveryAddress;

  Order({
    this.id,
    this.buyerName, // <-- ADICIONADO
    this.buyerPhone, // <-- ADICIONADO
    this.buyerEmail, // <-- ADICIONADO
    required this.clientId,
    required this.clientName,
    required this.items,
    this.status = OrderStatus.cotacao,
    this.paymentStatus = PaymentStatus.aguardandoSinal,
    required this.creationDate,
    this.confirmationDate,
    this.deliveryDate,
    required this.totalItemsAmount,
    this.shippingCost = 0.0,
    this.discount = 0.0,
    required this.finalAmount,
    this.paymentDistributions = const [],
    this.paymentTerms,
    required this.paymentMethod,
    this.notes,
    this.attachmentUrls = const [],
    required this.createdByUserId,
    required this.createdByUserName,
    required this.deliveryAddress,
  });

  double get amountPaid => paymentDistributions.fold(0.0, (sum, item) => sum + item.amount);

  Order copyWith({
    String? buyerName, // <-- ADICIONADO
    String? buyerPhone, // <-- ADICIONADO
    String? buyerEmail, // <-- ADICIONADO
    String? clientId, String? clientName, List<OrderItem>? items, OrderStatus? status, PaymentStatus? paymentStatus,
    double? totalItemsAmount, double? shippingCost, double? discount, double? finalAmount, List<PaymentDistribution>? paymentDistributions,
    String? paymentTerms, String? paymentMethod, String? notes, Address? deliveryAddress,
    Timestamp? deliveryDate, Timestamp? confirmationDate, List<String>? attachmentUrls,
  }) {
    return Order(
      id: id,
      buyerName: buyerName ?? this.buyerName, // <-- ADICIONADO
      buyerPhone: buyerPhone ?? this.buyerPhone, // <-- ADICIONADO
      buyerEmail: buyerEmail ?? this.buyerEmail, // <-- ADICIONADO
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      items: items ?? this.items,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      creationDate: creationDate,
      confirmationDate: confirmationDate ?? this.confirmationDate,
      deliveryDate: deliveryDate ?? this.deliveryDate,
      totalItemsAmount: totalItemsAmount ?? this.totalItemsAmount,
      shippingCost: shippingCost ?? this.shippingCost,
      discount: discount ?? this.discount,
      finalAmount: finalAmount ?? this.finalAmount,
      paymentDistributions: paymentDistributions ?? this.paymentDistributions,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      attachmentUrls: attachmentUrls ?? this.attachmentUrls,
      createdByUserId: createdByUserId,
      createdByUserName: createdByUserName,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
    );
  }

  Order duplicateAsQuote({required User currentUser}) {
    return Order(
      id: null,
      buyerName: buyerName, // <-- ADICIONADO
      buyerPhone: buyerPhone, // <-- ADICIONADO
      buyerEmail: buyerEmail, // <-- ADICIONADO
      clientId: clientId,
      clientName: clientName,
      items: items,
      status: OrderStatus.cotacao,
      paymentStatus: PaymentStatus.aguardandoSinal,
      creationDate: Timestamp.now(),
      confirmationDate: null,
      deliveryDate: null,
      totalItemsAmount: totalItemsAmount,
      shippingCost: shippingCost,
      discount: 0,
      finalAmount: finalAmount,
      paymentDistributions: [],
      paymentTerms: paymentTerms,
      paymentMethod: paymentMethod,
      notes: notes,
      attachmentUrls: [],
      createdByUserId: currentUser.uid,
      createdByUserName: currentUser.displayName ?? currentUser.email!,
      deliveryAddress: deliveryAddress,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'buyerName': buyerName, // <-- ADICIONADO
      'buyerPhone': buyerPhone, // <-- ADICIONADO
      'buyerEmail': buyerEmail, // <-- ADICIONADO
      'clientId': clientId, 'clientName': clientName, 'items': items.map((item) => item.toJson()).toList(),
      'status': status.name, 'paymentStatus': paymentStatus.name, 'creationDate': creationDate,
      'confirmationDate': confirmationDate, 'deliveryDate': deliveryDate, 'totalItemsAmount': totalItemsAmount,
      'shippingCost': shippingCost, 'discount': discount, 'finalAmount': finalAmount,
      'paymentDistributions': paymentDistributions.map((pd) => pd.toJson()).toList(),
      'paymentTerms': paymentTerms, 'paymentMethod': paymentMethod,
      'notes': notes, 'attachmentUrls': attachmentUrls, 'createdByUserId': createdByUserId,
      'createdByUserName': createdByUserName, 'deliveryAddress': deliveryAddress.toJson(),
    };
  }

  factory Order.fromFirestore(Map<String, dynamic> data, String documentId) {
    var itemsList = (data['items'] as List<dynamic>?)?.map((itemJson) => OrderItem.fromJson(itemJson as Map<String, dynamic>)).toList() ?? [];
    var attachmentsList = (data['attachmentUrls'] as List<dynamic>?)?.map((url) => url as String).toList() ?? [];
    final status = OrderStatus.values.firstWhere((e) => e.name == data['status'], orElse: () => OrderStatus.cotacao);
    List<PaymentDistribution> distributionsList = [];
    if (data['paymentDistributions'] != null && (data['paymentDistributions'] as List).isNotEmpty) {
      distributionsList = (data['paymentDistributions'] as List<dynamic>).map((distJson) => PaymentDistribution.fromJson(distJson as Map<String, dynamic>)).toList();
    } 
    else if (status != OrderStatus.cancelado && data.containsKey('amountPaid') && (data['amountPaid'] as num? ?? 0) > 0) {
      distributionsList.add(PaymentDistribution(recipient: 'Cristiano', amount: (data['amountPaid'] as num).toDouble()));
    }

    return Order(
      id: documentId,
      buyerName: data['buyerName'], // <-- ADICIONADO
      buyerPhone: data['buyerPhone'], // <-- ADICIONADO
      buyerEmail: data['buyerEmail'], // <-- ADICIONADO
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'] ?? '',
      items: itemsList,
      status: status,
      paymentStatus: PaymentStatus.values.firstWhere((e) => e.name == data['paymentStatus'], orElse: () => PaymentStatus.aguardandoSinal),
      creationDate: data['creationDate'] ?? Timestamp.now(),
      confirmationDate: data['confirmationDate'],
      deliveryDate: data['deliveryDate'],
      totalItemsAmount: (data['totalItemsAmount'] ?? 0.0).toDouble(),
      shippingCost: (data['shippingCost'] ?? 0.0).toDouble(),
      discount: (data['discount'] ?? 0.0).toDouble(),
      finalAmount: (data['finalAmount'] ?? 0.0).toDouble(),
      paymentDistributions: distributionsList,
      paymentTerms: data['paymentTerms'],
      paymentMethod: data['paymentMethod'] ?? 'PIX',
      notes: data['notes'],
      attachmentUrls: attachmentsList,
      createdByUserId: data['createdByUserId'] ?? 'desconhecido',
      createdByUserName: data['createdByUserName'] ?? 'Usuário Desconhecido',
      deliveryAddress: Address.fromJson(data['deliveryAddress']),
    );
  }
}