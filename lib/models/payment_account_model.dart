// lib/models/payment_account_model.dart

class PaymentAccount {
  final String id;
  final String name;
  final bool isActive;

  PaymentAccount({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  factory PaymentAccount.fromMap(String id, Map<String, dynamic> map) {
    return PaymentAccount(
      id: id,
      name: map['name'] ?? '',
      isActive: map['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'isActive': isActive,
    };
  }
}