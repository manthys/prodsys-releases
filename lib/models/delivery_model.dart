// lib/models/delivery_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum DeliveryStatus { emTransito, entregue }
// NOVO ENUM PARA O TIPO DE MOVIMENTAÇÃO
enum DeliveryType { saida, devolucao } 

class DeliveryItem {
  final String productId;
  final String sku;
  final String productName;
  final int quantity;
  final String logoType;
  final int returnQuantity; // Usado na entrega (recusa imediata)
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
  final String orderId;
  final String clientName;
  final Timestamp deliveryDate;
  final List<DeliveryItem> items;
  final String driverName;
  final String vehiclePlate;
  final String createdByUserName;
  final DeliveryStatus status;
  // NOVO CAMPO
  final DeliveryType type; 

  Delivery({
    this.id,
    required this.orderId,
    required this.clientName,
    required this.deliveryDate,
    required this.items,
    this.driverName = '',
    this.vehiclePlate = '',
    required this.createdByUserName,
    this.status = DeliveryStatus.emTransito,
    this.type = DeliveryType.saida, // Padrão é saída
  });

  Delivery copyWith({String? id}) {
    return Delivery(
      id: id ?? this.id,
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
    'orderId': orderId,
    'clientName': clientName,
    'deliveryDate': deliveryDate,
    'items': items.map((item) => item.toJson()).toList(),
    'driverName': driverName,
    'vehiclePlate': vehiclePlate,
    'createdByUserName': createdByUserName,
    'status': status.name,
    'type': type.name, // Salva o tipo
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
      status: DeliveryStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => DeliveryStatus.emTransito,
      ),
      // Lê o tipo, com fallback para 'saida' para compatibilidade antiga
      type: DeliveryType.values.firstWhere(
        (e) => e.name == (data['type'] ?? 'saida'),
        orElse: () => DeliveryType.saida,
      ),
    );
  }
}