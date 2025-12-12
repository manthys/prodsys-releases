// lib/models/client_model.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'address_model.dart';

class Client {
  final String? id;
  final String name;
  final String? cnpj;
  final String? ie;
  final String phone;
  final String? email;
  final Address billingAddress;
  final Address deliveryAddress;

  Client({
    this.id,
    required this.name,
    this.cnpj,
    this.ie,
    required this.phone,
    this.email,
    required this.billingAddress,
    required this.deliveryAddress,
  });

  // =================================================================
  // MÉTODO "copyWith" QUE ESTAVA FALTANDO
  // =================================================================
  Client copyWith({
    String? id,
    String? name,
    String? cnpj,
    String? ie,
    String? phone,
    String? email,
    Address? billingAddress,
    Address? deliveryAddress,
  }) {
    return Client(
      id: id ?? this.id,
      name: name ?? this.name,
      cnpj: cnpj ?? this.cnpj,
      ie: ie ?? this.ie,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      billingAddress: billingAddress ?? this.billingAddress,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'cnpj': cnpj,
      'ie': ie,
      'phone': phone,
      'email': email,
      'billingAddress': billingAddress.toJson(),
      'deliveryAddress': deliveryAddress.toJson(),
    };
  }

  factory Client.fromFirestore(Map<String, dynamic> data, String documentId) {
    return Client(
      id: documentId,
      name: data['name'] ?? '',
      cnpj: data['cnpj'] ?? '',
      ie: data['ie'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      billingAddress: Address.fromJson(data['billingAddress']),
      deliveryAddress: Address.fromJson(data['deliveryAddress']),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Client && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}