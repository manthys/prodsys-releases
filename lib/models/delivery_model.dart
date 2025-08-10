// lib/models/delivery_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

// NOVO ENUM
enum DeliveryStatus { emTransito, entregue }

class DeliveryItem {
  final String productId;
  final String sku;
  final String productName;
  final int quantity;

  DeliveryItem({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.quantity,
  });

  Map<String, dynamic> toJson() => {'productId': productId, 'sku': sku, 'productName': productName, 'quantity': quantity};
  factory DeliveryItem.fromJson(Map<String, dynamic> json) => DeliveryItem(productId: json['productId'], sku: json['sku'], productName: json['productName'], quantity: json['quantity']);
}

class Delivery {
  final String? id;
  final String orderId;
  final String clientName;
  final Timestamp deliveryDate;
  final List<DeliveryItem> items;
  final String driverName;
  final String vehiclePlate;
  final String createdByUserName;
  final DeliveryStatus status; // <-- NOVO CAMPO

  Delivery({
    this.id,
    required this.orderId,
    required this.clientName,
    required this.deliveryDate,
    required this.items,
    this.driverName = '',
    this.vehiclePlate = '',
    required this.createdByUserName,
    this.status = DeliveryStatus.emTransito, // <-- NOVO CAMPO
  });

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'clientName': clientName,
    'deliveryDate': deliveryDate,
    'items': items.map((item) => item.toJson()).toList(),
    'driverName': driverName,
    'vehiclePlate': vehiclePlate,
    'createdByUserName': createdByUserName,
    'status': status.name, // <-- NOVO CAMPO
  };

  factory Delivery.fromFirestore(Map<String, dynamic> data, String documentId) {
    var itemsList = (data['items'] as List<dynamic>?)?.map((itemJson) => DeliveryItem.fromJson(itemJson as Map<String, dynamic>)).toList() ?? [];
    
    return Delivery(
      id: documentId,
      orderId: data['orderId'],
      clientName: data['clientName'],
      deliveryDate: data['deliveryDate'],
      items: itemsList,
      driverName: data['driverName'],
      vehiclePlate: data['vehiclePlate'],
      createdByUserName: data['createdByUserName'],
      status: DeliveryStatus.values.firstWhere( // <-- NOVO CAMPO
        (e) => e.name == data['status'],
        orElse: () => DeliveryStatus.emTransito,
      ),
    );
  }
}