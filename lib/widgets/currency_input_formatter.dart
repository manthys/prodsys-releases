import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.currency(locale: 'pt_BR', symbol: '', decimalDigits: 2);

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Se o novo valor for vazio, retorna vazio
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // 1. Pega apenas os dígitos do texto
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    
    // 2. Converte a string de dígitos para um número (tratando como centavos)
    double value = double.parse(digitsOnly) / 100.0;

    // 3. Formata o número como moeda brasileira
    String newText = _formatter.format(value).trim();

    // 4. Retorna o novo valor formatado e posiciona o cursor no final
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}