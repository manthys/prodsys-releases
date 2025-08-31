// lib/models/payment_distribution_model.dart

class PaymentDistribution {
  final String recipient;
  final double amount;
  
  PaymentDistribution({
    required this.recipient,
    required this.amount,
  });

  Map<String, dynamic> toJson() {
    return {
      'recipient': recipient,
      'amount': amount,
    };
  }

  factory PaymentDistribution.fromJson(Map<String, dynamic> json) {
    return PaymentDistribution(
      recipient: json['recipient'] as String,
      amount: (json['amount'] as num).toDouble(),
    );
  }

  PaymentDistribution copyWith({
    String? recipient,
    double? amount,
  }) {
    return PaymentDistribution(
      recipient: recipient ?? this.recipient,
      amount: amount ?? this.amount,
    );
  }
}