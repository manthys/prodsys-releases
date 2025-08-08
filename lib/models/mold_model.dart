// lib/models/mold_model.dart
class Mold {
  final String? id;
  final String name; // Ex: "T-50", "P-40"
  final int quantityAvailable;

  Mold({
    this.id,
    required this.name,
    required this.quantityAvailable,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantityAvailable': quantityAvailable,
    };
  }

  factory Mold.fromFirestore(Map<String, dynamic> data, String documentId) {
    return Mold(
      id: documentId,
      name: data['name'] ?? '',
      quantityAvailable: data['quantityAvailable'] ?? 0,
    );
  }
}