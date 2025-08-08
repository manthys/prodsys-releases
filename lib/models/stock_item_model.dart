// lib/models/stock_item_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

enum StockItemStatus { aguardandoProducao, emEstoque, entregue }

class StockItem {
  final String? id;
  final String productId;
  final String productName;
  final String sku;
  final String? orderId;
  final String? clientName;
  final StockItemStatus status;
  final String logoType;
  final Timestamp creationDate;
  final Timestamp? deliveryDeadline; // <-- O CAMPO IMPORTANTE

  StockItem({
    this.id,
    required this.productId,
    required this.productName,
    required this.sku,
    this.orderId,
    this.clientName,
    required this.status,
    required this.logoType,
    required this.creationDate,
    this.deliveryDeadline, // <-- O PARÂMETRO NO CONSTRUTOR
  });

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'sku': sku,
      'orderId': orderId,
      'clientName': clientName,
      'status': status.name,
      'logoType': logoType,
      'creationDate': creationDate,
      'deliveryDeadline': deliveryDeadline, // <-- A CHAVE NO JSON
    };
  }

  factory StockItem.fromFirestore(Map<String, dynamic> data, String documentId) {
    return StockItem(
      id: documentId,
      productId: data['productId'] ?? '',
      productName: data['productName'] ?? '',
      sku: data['sku'] ?? '',
      orderId: data['orderId'],
      clientName: data['clientName'],
      status: StockItemStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => StockItemStatus.aguardandoProducao
      ),
      logoType: data['logoType'] ?? 'Nenhum',
      creationDate: data['creationDate'] ?? Timestamp.now(),
      deliveryDeadline: data['deliveryDeadline'], // <-- A LEITURA DO FIREBASE
    );
  }
}