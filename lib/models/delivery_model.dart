// lib/models/delivery_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum DeliveryStatus { emTransito, entregue }
enum DeliveryType { saida, devolucao } 

class DeliveryItem {
  final String productId;
  final String sku;
  final String productName;
  final int quantity;
  final String logoType;
  final int returnQuantity;
  final String? returnReason;

  DeliveryItem({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.quantity,
    required this.logoType,
    this.returnQuantity = 0,
    this.returnReason,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId, 
    'sku': sku, 
    'productName': productName, 
    'quantity': quantity,
    'logoType': logoType,
    'returnQuantity': returnQuantity,
    'returnReason': returnReason,
  };
  
  factory DeliveryItem.fromJson(Map<String, dynamic> json) => DeliveryItem(
    productId: json['productId'], 
    sku: json['sku'], 
    productName: json['productName'], 
    quantity: json['quantity'],
    logoType: json['logoType'] ?? 'Nenhum',
    returnQuantity: json['returnQuantity'] ?? 0,
    returnReason: json['returnReason'],
  );
}

class Delivery {
  final String? id;
  final String? routeId; // NOVO: Identificador da Rota
  final String orderId;
  final String clientName;
  final Timestamp deliveryDate;
  final List<DeliveryItem> items;
  final String driverName;
  final String vehiclePlate;
  final String createdByUserName;
  final DeliveryStatus status;
  final DeliveryType type; 

  Delivery({
    this.id,
    this.routeId, // NOVO
    required this.orderId,
    required this.clientName,
    required this.deliveryDate,
    required this.items,
    this.driverName = '',
    this.vehiclePlate = '',
    required this.createdByUserName,
    this.status = DeliveryStatus.emTransito,
    this.type = DeliveryType.saida,
  });

  Delivery copyWith({String? id}) {
    return Delivery(
      id: id ?? this.id,
      routeId: routeId,
      orderId: orderId,
      clientName: clientName,
      deliveryDate: deliveryDate,
      items: items,
      driverName: driverName,
      vehiclePlate: vehiclePlate,
      createdByUserName: createdByUserName,
      status: status,
      type: type,
    );
  }

  Map<String, dynamic> toJson() => {
    'routeId': routeId, // Salva o ID da rota
    'orderId': orderId,
    'clientName': clientName,
    'deliveryDate': deliveryDate,
    'items': items.map((item) => item.toJson()).toList(),
    'driverName': driverName,
    'vehiclePlate': vehiclePlate,
    'createdByUserName': createdByUserName,
    'status': status.name,
    'type': type.name,
  };

  factory Delivery.fromFirestore(Map<String, dynamic> data, String documentId) {
    var itemsList = (data['items'] as List<dynamic>?)?.map((itemJson) => DeliveryItem.fromJson(itemJson as Map<String, dynamic>)).toList() ?? [];
    
    return Delivery(
      id: documentId,
      routeId: data['routeId'], // Lê o ID da rota
      orderId: data['orderId'] ?? '',
      clientName: data['clientName'] ?? 'Desconhecido',
      deliveryDate: data['deliveryDate'] ?? Timestamp.now(),
      items: itemsList,
      driverName: data['driverName'] ?? '',
      vehiclePlate: data['vehiclePlate'] ?? '',
      createdByUserName: data['createdByUserName'] ?? '',
      status: DeliveryStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => DeliveryStatus.emTransito,
      ),
      type: DeliveryType.values.firstWhere(
        (e) => e.name == (data['type'] ?? 'saida'),
        orElse: () => DeliveryType.saida,
      ),
    );
  }
}