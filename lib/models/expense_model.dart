// lib/models/expense_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class Expense {
  final String? id;
  final String description;
  final double amount;
  final String category;
  final Timestamp expenseDate;
  final String? attachmentUrl;

  Expense({
    this.id,
    required this.description,
    required this.amount,
    required this.category,
    required this.expenseDate,
    this.attachmentUrl,
  });

  Map<String, dynamic> toJson() {
    return {
      'description': description,
      'amount': amount,
      'category': category,
      'expenseDate': expenseDate,
      'attachmentUrl': attachmentUrl,
    };
  }

  factory Expense.fromFirestore(Map<String, dynamic> data, String documentId) {
    return Expense(
      id: documentId,
      description: data['description'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      category: data['category'] ?? 'Outros',
      expenseDate: data['expenseDate'] ?? Timestamp.now(),
      attachmentUrl: data['attachmentUrl'],
    );
  }
}