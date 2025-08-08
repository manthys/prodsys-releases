// lib/models/order_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'order_item_model.dart';
import 'address_model.dart';

enum OrderStatus { cotacao, pedido, emFabricacao, aguardandoEntrega, finalizado, cancelado }
enum PaymentStatus { aguardandoSinal, sinalPago, pagoIntegralmente }

class Order {
  final String? id;
  final String clientId;
  final String clientName;
  final List<OrderItem> items;
  OrderStatus status;
  PaymentStatus paymentStatus;
  final Timestamp creationDate;
  Timestamp? confirmationDate;
  Timestamp? deliveryDate;
  
  final double totalItemsAmount;
  final double shippingCost;
  final double discount; // <-- NOVO CAMPO
  final double finalAmount;
  double amountPaid;

  final String? paymentTerms;
  final String paymentMethod;
  final String? notes;
  
  final List<String> attachmentUrls;
  final String createdByUserId;
  final String createdByUserName;
  final Address deliveryAddress;

  Order({
    this.id,
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
    this.discount = 0.0, // <-- NOVO CAMPO
    required this.finalAmount,
    this.amountPaid = 0.0,
    this.paymentTerms,
    required this.paymentMethod,
    this.notes,
    this.attachmentUrls = const [],
    required this.createdByUserId,
    required this.createdByUserName,
    required this.deliveryAddress,
  });

  Order copyWith({
    String? clientId, String? clientName, List<OrderItem>? items, OrderStatus? status, PaymentStatus? paymentStatus,
    double? totalItemsAmount, double? shippingCost, double? discount, double? finalAmount, double? amountPaid,
    String? paymentTerms, String? paymentMethod, String? notes, Address? deliveryAddress,
  }) {
    return Order(
      id: id,
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      items: items ?? this.items,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      creationDate: creationDate,
      confirmationDate: confirmationDate,
      deliveryDate: deliveryDate,
      totalItemsAmount: totalItemsAmount ?? this.totalItemsAmount,
      shippingCost: shippingCost ?? this.shippingCost,
      discount: discount ?? this.discount, // <-- NOVO CAMPO
      finalAmount: finalAmount ?? this.finalAmount,
      amountPaid: amountPaid ?? this.amountPaid,
      paymentTerms: paymentTerms ?? this.paymentTerms,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      notes: notes ?? this.notes,
      attachmentUrls: attachmentUrls,
      createdByUserId: createdByUserId,
      createdByUserName: createdByUserName,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
    );
  }

  Order duplicateAsQuote({required User currentUser}) {
    return Order(
      id: null,
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
      discount: 0, // Zera o desconto na duplicação
      finalAmount: finalAmount,
      amountPaid: 0,
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
      'clientId': clientId, 'clientName': clientName, 'items': items.map((item) => item.toJson()).toList(),
      'status': status.name, 'paymentStatus': paymentStatus.name, 'creationDate': creationDate,
      'confirmationDate': confirmationDate, 'deliveryDate': deliveryDate, 'totalItemsAmount': totalItemsAmount,
      'shippingCost': shippingCost, 'discount': discount, 'finalAmount': finalAmount, // <-- NOVO CAMPO
      'amountPaid': amountPaid, 'paymentTerms': paymentTerms, 'paymentMethod': paymentMethod,
      'notes': notes, 'attachmentUrls': attachmentUrls, 'createdByUserId': createdByUserId,
      'createdByUserName': createdByUserName, 'deliveryAddress': deliveryAddress.toJson(),
    };
  }

  factory Order.fromFirestore(Map<String, dynamic> data, String documentId) {
    var itemsList = (data['items'] as List<dynamic>?)?.map((itemJson) => OrderItem.fromJson(itemJson as Map<String, dynamic>)).toList() ?? [];
    var attachmentsList = (data['attachmentUrls'] as List<dynamic>?)?.map((url) => url as String).toList() ?? [];

    return Order(
      id: documentId,
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'] ?? '',
      items: itemsList,
      status: OrderStatus.values.firstWhere((e) => e.name == data['status'], orElse: () => OrderStatus.cotacao),
      paymentStatus: PaymentStatus.values.firstWhere((e) => e.name == data['paymentStatus'], orElse: () => PaymentStatus.aguardandoSinal),
      creationDate: data['creationDate'] ?? Timestamp.now(),
      confirmationDate: data['confirmationDate'],
      deliveryDate: data['deliveryDate'],
      totalItemsAmount: (data['totalItemsAmount'] ?? 0.0).toDouble(),
      shippingCost: (data['shippingCost'] ?? 0.0).toDouble(),
      discount: (data['discount'] ?? 0.0).toDouble(), // <-- NOVO CAMPO
      finalAmount: (data['finalAmount'] ?? 0.0).toDouble(),
      amountPaid: (data['amountPaid'] ?? 0.0).toDouble(),
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