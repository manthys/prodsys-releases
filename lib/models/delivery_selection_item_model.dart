class DeliverySelectionItem {
  final String productId;
  final String sku;
  final String productName;
  final String? logoType;
  final int maxQuantity;
  int quantityToDeliver;
  final double unitWeight; // NOVO: Peso unitário herdado da forma

  DeliverySelectionItem({
    required this.productId,
    required this.sku,
    required this.productName,
    this.logoType,
    required this.maxQuantity,
    this.quantityToDeliver = 0,
    this.unitWeight = 0.0,
  });
}