// lib/models/order_item_model.dart
class OrderItem {
  final String productId;
  final String sku;
  final String productName;
  final int quantity;
  int quantityProduced;
  final double finalUnitPrice;
  final bool includesLid;
  final String logoType;

  OrderItem({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.quantity,
    this.quantityProduced = 0,
    required this.finalUnitPrice,
    required this.includesLid,
    required this.logoType,
  });

  int get remainingQuantity => quantity - quantityProduced;
  double get totalPrice => quantity * finalUnitPrice;

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'sku': sku,
      'productName': productName,
      'quantity': quantity,
      'quantityProduced': quantityProduced,
      'finalUnitPrice': finalUnitPrice,
      'includesLid': includesLid,
      'logoType': logoType,
    };
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: json['productId'] ?? '',
      sku: json['sku'] ?? '',
      productName: json['productName'] ?? '',
      quantity: json['quantity'] ?? 0,
      quantityProduced: json['quantityProduced'] ?? 0,
      finalUnitPrice: (json['finalUnitPrice'] ?? 0.0).toDouble(),
      includesLid: json['includesLid'] ?? false,
      logoType: json['logoType'] ?? 'Nenhum',
    );
  }
}