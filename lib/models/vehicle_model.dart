class Vehicle {
  final String? id;
  final String name; // Ex: "Caminhão Toco", "Fiat Strada"
  final String plate;
  final String driverName;
  final double maxLoadKg; // Carga Máxima em KG

  Vehicle({
    this.id,
    required this.name,
    required this.plate,
    required this.driverName,
    required this.maxLoadKg,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'plate': plate,
    'driverName': driverName,
    'maxLoadKg': maxLoadKg,
  };

  factory Vehicle.fromFirestore(Map<String, dynamic> data, String id) {
    return Vehicle(
      id: id,
      name: data['name'] ?? '',
      plate: data['plate'] ?? '',
      driverName: data['driverName'] ?? '',
      maxLoadKg: (data['maxLoadKg'] as num?)?.toDouble() ?? 0.0,
    );
  }
}