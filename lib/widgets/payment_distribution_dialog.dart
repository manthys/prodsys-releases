// lib/widgets/payment_distribution_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/payment_distribution_model.dart';
import '../widgets/currency_input_formatter.dart';

class PaymentDistributionDialog extends StatefulWidget {
  final double totalAmount;
  final List<PaymentDistribution> initialDistributions;

  const PaymentDistributionDialog({
    super.key,
    required this.totalAmount,
    this.initialDistributions = const [],
  });

  @override
  _PaymentDistributionDialogState createState() => _PaymentDistributionDialogState();
}

class _PaymentDistributionDialogState extends State<PaymentDistributionDialog> {
  final _formKey = GlobalKey<FormState>();
  late List<PaymentDistribution> _distributions;
  final List<TextEditingController> _controllers = [];

  final List<String> _recipients = ["Cristiano", "Cleiton", "Osmildo", "Nota"];

  @override
  void initState() {
    super.initState();
    if (widget.initialDistributions.isNotEmpty) {
      _distributions = widget.initialDistributions.map((d) => d.copyWith()).toList();
    } else {
      _distributions = [PaymentDistribution(recipient: _recipients.first, amount: widget.totalAmount)];
    }
    
    _updateControllers();
  }

  void _updateControllers() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _controllers.clear();
    
    for (var dist in _distributions) {
      final formattedValue = NumberFormat("##0.00", "pt_BR").format(dist.amount);
      _controllers.add(TextEditingController(text: formattedValue));
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _addRecipient() {
    setState(() {
      _distributions.add(PaymentDistribution(recipient: _recipients.first, amount: 0));
      _controllers.add(TextEditingController(text: '0,00'));
    });
  }

  void _removeRecipient(int index) {
    setState(() {
      _distributions.removeAt(index);
      _updateControllers();
    });
  }

  double get _currentTotalDistributed {
    double total = 0;
    for (int i = 0; i < _controllers.length; i++) {
      final cleanValue = _controllers[i].text.replaceAll('.', '').replaceAll(',', '.');
      total += double.tryParse(cleanValue) ?? 0.0;
    }
    return total;
  }

  void _validateAndSubmit() {
    if (_formKey.currentState!.validate()) {
      if ((_currentTotalDistributed - widget.totalAmount).abs() > 0.01) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('A soma dos valores deve ser igual ao total a distribuir!'), backgroundColor: Colors.red),
        );
        return;
      }

      final result = <PaymentDistribution>[];
      for(int i = 0; i < _distributions.length; i++) {
         final cleanValue = _controllers[i].text.replaceAll('.', '').replaceAll(',', '.');
         result.add(PaymentDistribution(
           recipient: _distributions[i].recipient,
           amount: double.parse(cleanValue),
         ));
      }
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return AlertDialog(
      title: const Text('Distribuir Pagamento'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total a distribuir: ${currencyFormatter.format(widget.totalAmount)}', style: Theme.of(context).textTheme.titleMedium),
                const Divider(height: 20),
                ..._buildDistributionFields(),
                const SizedBox(height: 10),
                if ((_currentTotalDistributed - widget.totalAmount).abs() > 0.01)
                  Text(
                    'Soma atual: ${currencyFormatter.format(_currentTotalDistributed)} (Diferença: ${currencyFormatter.format(_currentTotalDistributed - widget.totalAmount)})',
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                const SizedBox(height: 10),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar recebedor'),
                  onPressed: _addRecipient,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _validateAndSubmit, child: const Text('Confirmar')),
      ],
    );
  }

  List<Widget> _buildDistributionFields() {
    return List.generate(_distributions.length, (index) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: _distributions[index].recipient,
                items: _recipients.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                       _distributions[index] = PaymentDistribution(recipient: value, amount: _distributions[index].amount);
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Conta', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _controllers[index],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CurrencyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ ', border: OutlineInputBorder()),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Obrigatório';
                  final cleanValue = value.replaceAll('.', '').replaceAll(',', '.');
                  if (double.tryParse(cleanValue) == null || double.parse(cleanValue) < 0) return 'Inválido';
                  return null;
                },
                onChanged: (value) => setState((){}),
              ),
            ),
            if (_distributions.length > 1)
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                onPressed: () => _removeRecipient(index),
                tooltip: 'Remover',
              )
          ],
        ),
      );
    });
  }
}