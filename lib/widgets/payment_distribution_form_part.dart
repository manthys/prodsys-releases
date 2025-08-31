// lib/widgets/payment_distribution_form_part.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/payment_distribution_model.dart';
import 'currency_input_formatter.dart';

class PaymentDistributionFormPart extends StatefulWidget {
  final double totalAmount;
  final List<PaymentDistribution> initialDistributions;

  const PaymentDistributionFormPart({
    super.key,
    // totalAmount agora é opcional. Se for 0, significa modo de entrada livre.
    this.totalAmount = 0,
    this.initialDistributions = const [],
  });

  @override
  State<PaymentDistributionFormPart> createState() => PaymentDistributionFormPartState();
}

class PaymentDistributionFormPartState extends State<PaymentDistributionFormPart> {
  late List<PaymentDistribution> _distributions;
  final List<TextEditingController> _controllers = [];
  final List<String> _recipients = ["Cristiano", "Cleiton", "Osmildo"];
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _initializeState();
  }

  @override
  void didUpdateWidget(covariant PaymentDistributionFormPart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.totalAmount != oldWidget.totalAmount) {
      _initializeState();
    }
  }

  void _initializeState() {
    if (widget.initialDistributions.isNotEmpty) {
      _distributions = widget.initialDistributions.map((d) => d.copyWith()).toList();
    } else {
      _distributions = [
        PaymentDistribution(
          recipient: _recipients.first,
          // Se o total for fixo, preenche com ele. Se não, começa com 0.
          amount: widget.totalAmount > 0 ? widget.totalAmount : 0,
        )
      ];
    }
    _updateControllers();
    setState(() {});
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

  double getCurrentTotal() {
    double total = 0;
    for (var controller in _controllers) {
      final cleanValue = controller.text.replaceAll('.', '').replaceAll(',', '.');
      total += double.tryParse(cleanValue) ?? 0.0;
    }
    return total;
  }
  
  List<PaymentDistribution>? getDistributions() {
    if (!_formKey.currentState!.validate()) {
      return null;
    }
    // Só valida a soma se um total foi fornecido
    if (widget.totalAmount > 0 && (getCurrentTotal() - widget.totalAmount).abs() > 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A soma dos valores deve ser igual ao total a ser pago!'), backgroundColor: Colors.red),
      );
      return null;
    }
    final result = <PaymentDistribution>[];
    for (int i = 0; i < _distributions.length; i++) {
      final cleanValue = _controllers[i].text.replaceAll('.', '').replaceAll(',', '.');
      final amount = double.tryParse(cleanValue) ?? 0;
      if(amount > 0) {
        result.add(PaymentDistribution(
          recipient: _distributions[i].recipient,
          amount: amount,
        ));
      }
    }
    // Se for modo de entrada livre e nada foi digitado, retorna erro
    if (widget.totalAmount == 0 && result.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione pelo menos um valor na distribuição.'), backgroundColor: Colors.red),
      );
      return null;
    }
    return result;
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
  
  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final currentTotal = getCurrentTotal();

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.totalAmount > 0)
            Text('Distribuir ${currencyFormatter.format(widget.totalAmount)} para:', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (widget.totalAmount == 0)
            const Text('Distribuição de Pagamento:', style: TextStyle(fontWeight: FontWeight.bold)),

          const SizedBox(height: 12),
          ..._buildDistributionFields(),
          const SizedBox(height: 10),
          
          if (widget.totalAmount > 0 && (currentTotal - widget.totalAmount).abs() > 0.01)
            Text(
              'Soma atual: ${currencyFormatter.format(currentTotal)} (Diferença: ${currencyFormatter.format(currentTotal - widget.totalAmount)})',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12, fontWeight: FontWeight.bold),
            ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
               TextButton.icon(
                icon: const Icon(Icons.add_circle_outline, size: 20),
                label: const Text('Adicionar'),
                onPressed: _addRecipient,
              ),
              if(widget.totalAmount == 0)
                Text('Total: ${currencyFormatter.format(currentTotal)}', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
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
                value: _distributions[index].recipient,
                items: _recipients.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                       _distributions[index] = PaymentDistribution(recipient: value, amount: _distributions[index].amount);
                    });
                  }
                },
                decoration: const InputDecoration(labelText: 'Conta', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: _controllers[index],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [CurrencyInputFormatter()],
                decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ ', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Obrigatório';
                  final cleanValue = value.replaceAll('.', '').replaceAll(',', '.');
                  if (double.tryParse(cleanValue) == null || double.parse(cleanValue) < 0) return 'Inválido';
                  return null;
                },
                onChanged: (value) => setState((){}),
              ),
            ),
            if (_distributions.length > 1 || widget.totalAmount == 0)
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