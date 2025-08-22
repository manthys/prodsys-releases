// lib/models/product_model.dart

import 'price_variation_model.dart'; // Importe o novo modelo

class Product {
  final String? id;
  final String name;
  final String sku;
  final String moldType;
  final double clientLogoPrice;
  // REMOVIDO: final double basePrice;
  // ADICIONADO: Uma lista de variações de preço
  final List<PriceVariation> priceVariations;

  Product({
    this.id,
    required this.name,
    required this.sku,
    required this.moldType,
    required this.clientLogoPrice,
    // REMOVIDO: required this.basePrice,
    required this.priceVariations,
  });

  // Adicionamos um getter para facilitar o acesso ao preço principal/padrão
  double get basePrice {
    if (priceVariations.isEmpty) {
      return 0.0;
    }
    // Retorna o preço da primeira variação como o preço "base"
    return priceVariations.first.price;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sku': sku,
      'moldType': moldType,
      'clientLogoPrice': clientLogoPrice,
      // Converte a lista de objetos para uma lista de Maps
      'priceVariations': priceVariations.map((v) => v.toJson()).toList(),
    };
  }

  factory Product.fromFirestore(Map<String, dynamic> data, String documentId) {
    // Lógica para carregar as variações de preço do Firestore
    var variationsData = data['priceVariations'] as List<dynamic>? ?? [];
    List<PriceVariation> variations = variationsData.map((v) => PriceVariation.fromJson(v)).toList();

    // Lógica de fallback para produtos antigos que só tinham 'basePrice'
    if (variations.isEmpty && data['basePrice'] != null) {
      variations.add(PriceVariation(
        description: 'Preço Padrão',
        price: (data['basePrice'] as num).toDouble()
      ));
    }
    
    return Product(
      id: documentId,
      name: data['name'] ?? '',
      sku: data['sku'] ?? '',
      moldType: data['moldType'] ?? '',
      clientLogoPrice: (data['clientLogoPrice'] as num? ?? 0).toDouble(),
      priceVariations: variations,
    );
  }
}