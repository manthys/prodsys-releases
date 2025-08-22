// lib/models/price_variation_model.dart

class PriceVariation {
  String description;
  double price;

  PriceVariation({
    required this.description,
    required this.price,
  });

  // Converte um objeto PriceVariation para um Map (para salvar no Firestore)
  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'price': price,
    };
  }

  // Cria um objeto PriceVariation a partir de um Map (vindo do Firestore)
  factory PriceVariation.fromJson(Map<String, dynamic> json) {
    return PriceVariation(
      description: json['description'] as String? ?? 'Preço Padrão',
      price: (json['price'] as num? ?? 0).toDouble(),
    );
  }
}