class Mold {
  final String? id;
  final String name; // Ex: "T-50", "P-40"
  final int quantityAvailable;
  final double weight; // NOVO CAMPO: Peso em KG

  Mold({
    this.id,
    required this.name,
    required this.quantityAvailable,
    this.weight = 0.0,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantityAvailable': quantityAvailable,
      'weight': weight,
    };
  }

  factory Mold.fromFirestore(Map<String, dynamic> data, String documentId) {
    return Mold(
      id: documentId,
      name: data['name'] ?? '',
      quantityAvailable: data['quantityAvailable'] ?? 0,
      weight: (data['weight'] as num?)?.toDouble() ?? 0.0,
    );
  }
}