// lib/models/delivery_selection_item_model.dart

class DeliverySelectionItem {
  final String productId;
  final String sku;
  final String productName;
  final String? logoType;
  final int maxQuantity;
  int quantityToDeliver;

  DeliverySelectionItem({
    required this.productId,
    required this.sku,
    required this.productName,
    this.logoType,
    required this.maxQuantity,
    this.quantityToDeliver = 0,
  });
}