// lib/models/company_settings_model.dart

import 'address_model.dart';

class CompanySettings {
  final String companyName;
  final String cnpj;
  final String phone;
  final String email;
  final Address address;
  final String paymentInfo;
  final String defaultPaymentTerms; // <-- NOVO CAMPO

  CompanySettings({
    this.companyName = '',
    this.cnpj = '',
    this.phone = '',
    this.email = '',
    required this.address,
    this.paymentInfo = '',
    this.defaultPaymentTerms = '', // <-- NOVO CAMPO
  });

  Map<String, dynamic> toJson() {
    return {
      'companyName': companyName,
      'cnpj': cnpj,
      'phone': phone,
      'email': email,
      'address': address.toJson(),
      'paymentInfo': paymentInfo,
      'defaultPaymentTerms': defaultPaymentTerms, // <-- NOVO CAMPO
    };
  }

  factory CompanySettings.fromFirestore(Map<String, dynamic>? data) {
    if (data == null) {
      return CompanySettings(address: Address());
    }
    return CompanySettings(
      companyName: data['companyName'] ?? '',
      cnpj: data['cnpj'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] ?? '',
      address: Address.fromJson(data['address']),
      paymentInfo: data['paymentInfo'] ?? '',
      defaultPaymentTerms: data['defaultPaymentTerms'] ?? '50% de entrada para iniciar a produção e 50% na entrega.', // <-- NOVO CAMPO COM VALOR PADRÃO
    );
  }
}