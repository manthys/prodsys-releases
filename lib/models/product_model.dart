// lib/models/product_model.dart
class Product {
  final String? id;
  final String name; // Descrição completa, ex: "TAMPA 50X50 ELÉTRICA"
  final String sku;
  final double basePrice; // Preço da peça "limpa"
  final double clientLogoPrice; // Custo ADICIONAL para logo do cliente
  final String moldType; // Tipo de forma que usa, ex: "T-50"

  Product({
    this.id,
    required this.name,
    required this.sku,
    required this.basePrice,
    required this.clientLogoPrice,
    required this.moldType,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sku': sku,
      'basePrice': basePrice,
      'clientLogoPrice': clientLogoPrice,
      'moldType': moldType,
    };
  }

  factory Product.fromFirestore(Map<String, dynamic> data, String documentId) {
    return Product(
      id: documentId,
      name: data['name'] ?? '',
      sku: data['sku'] ?? '',
      basePrice: (data['basePrice'] ?? 0.0).toDouble(),
      clientLogoPrice: (data['clientLogoPrice'] ?? 0.0).toDouble(),
      moldType: data['moldType'] ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Product && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}