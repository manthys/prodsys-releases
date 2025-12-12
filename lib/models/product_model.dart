// lib/models/product_model.dart

import 'price_variation_model.dart';

class Product {
  final String? id;
  final String name;
  final String sku;
  final String moldType;
  final double clientLogoPrice;
  final List<PriceVariation> priceVariations;
  final bool isCompanyLogoProduct;
  // NOVO CAMPO: Tempo de ciclo em segundos (padrão 30s se não informado)
  final int cycleTimeSeconds; 

  Product({
    this.id,
    required this.name,
    required this.sku,
    required this.moldType,
    required this.clientLogoPrice,
    required this.priceVariations,
    this.isCompanyLogoProduct = false,
    this.cycleTimeSeconds = 30, 
  });

  double get basePrice {
    if (priceVariations.isEmpty) {
      return 0.0;
    }
    return priceVariations.first.price;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'sku': sku,
      'moldType': moldType,
      'clientLogoPrice': clientLogoPrice,
      'priceVariations': priceVariations.map((v) => v.toJson()).toList(),
      'isCompanyLogoProduct': isCompanyLogoProduct,
      'cycleTimeSeconds': cycleTimeSeconds,
    };
  }

  factory Product.fromFirestore(Map<String, dynamic> data, String documentId) {
    var variationsData = data['priceVariations'] as List<dynamic>? ?? [];
    List<PriceVariation> variations = variationsData.map((v) => PriceVariation.fromJson(v)).toList();

    if (variations.isEmpty && data['basePrice'] != null) {
      variations.add(PriceVariation(
        description: 'Preço Padrão',
        price: (data['basePrice'] as num).toDouble()
      ));
    }

    bool isCompanyLogo = data['isCompanyLogoProduct'] ?? false;
    if (data['isCompanyLogoProduct'] == null) {
      if ((data['sku'] as String? ?? '').toLowerCase().contains('cleiton premoldados')) {
        isCompanyLogo = true;
      }
    }
    
    return Product(
      id: documentId,
      name: data['name'] ?? '',
      sku: data['sku'] ?? '',
      moldType: data['moldType'] ?? '',
      clientLogoPrice: (data['clientLogoPrice'] as num? ?? 0).toDouble(),
      priceVariations: variations,
      isCompanyLogoProduct: isCompanyLogo,
      cycleTimeSeconds: data['cycleTimeSeconds'] ?? 30,
    );
  }
}