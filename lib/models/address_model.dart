// lib/models/address_model.dart
class Address {
  final String street;
  final String neighborhood;
  final String city;
  final String state;
  final String cep;

  Address({
    this.street = '',
    this.neighborhood = '',
    this.city = '',
    this.state = '',
    this.cep = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'street': street,
      'neighborhood': neighborhood,
      'city': city,
      'state': state,
      'cep': cep,
    };
  }

  factory Address.fromJson(Map<String, dynamic>? json) {
    if (json == null) return Address();
    return Address(
      street: json['street'] ?? '',
      neighborhood: json['neighborhood'] ?? '',
      city: json['city'] ?? '',
      state: json['state'] ?? '',
      cep: json['cep'] ?? '',
    );
  }
}