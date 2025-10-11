// lib/widgets/payment_confirmation_dialog.dart

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../models/payment_distribution_model.dart';
import 'payment_distribution_form_part.dart';

class PaymentConfirmationDialog extends StatefulWidget {
  final double totalAmount;
  final double alreadyPaidAmount;

  const PaymentConfirmationDialog({
    super.key,
    required this.totalAmount,
    this.alreadyPaidAmount = 0.0,
  });

  @override
  State<PaymentConfirmationDialog> createState() => _PaymentConfirmationDialogState();
}

class _PaymentConfirmationDialogState extends State<PaymentConfirmationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _distributionFormKey = GlobalKey<PaymentDistributionFormPartState>();

  int _paymentOption = 0;
  PlatformFile? _pickedFile;

  @override
  void initState() {
    super.initState();
    // Se já foi pago algo, a opção padrão vira "Pagar o Restante" (valor 1)
    if (widget.alreadyPaidAmount > 0) {
      _paymentOption = 1;
    }
  }

  double get _amountToConfirm {
    // Para "Outro Valor", o total é calculado dinamicamente pelo sub-widget
    if (_paymentOption == 3) {
      return _distributionFormKey.currentState?.getCurrentTotal() ?? 0.0;
    }
    
    switch (_paymentOption) {
      case 0:
        return widget.totalAmount / 2;
      case 1:
        final remaining = widget.totalAmount - widget.alreadyPaidAmount;
        return remaining > 0 ? remaining : 0;
      case 2:
        return 0.0;
      default:
        return 0.0;
    }
  }

  void _onConfirm() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    List<PaymentDistribution> distributionsToReturn = [];

    // Se alguma opção de pagamento foi selecionada (exceto "Nenhum")
    if (_amountToConfirm > 0 || _paymentOption == 3) {
      final distributions = _distributionFormKey.currentState?.getDistributions();
      if (distributions == null) {
        // A validação interna do sub-widget já deve ter mostrado o erro
        return;
      }
      distributionsToReturn = distributions;
    }

    Navigator.of(context).pop({
      'amount': _amountToConfirm,
      'distributions': distributionsToReturn,
      'proof': _pickedFile,
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    String integralLabel = widget.alreadyPaidAmount > 0 ? 'Restante (${currencyFormatter.format(widget.totalAmount - widget.alreadyPaidAmount)})' : 'Valor Integral (100%)';
    bool showSinalOption = widget.alreadyPaidAmount == 0;

    return AlertDialog(
      title: const Text('Confirmar Pagamento'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Selecione o valor pago:'),
                
                if (showSinalOption)
                  RadioListTile<int>(title: const Text('Sinal (50%)'), value: 0, groupValue: _paymentOption, onChanged: (v) => setState(() => _paymentOption = v!)),
                
                RadioListTile<int>(title: Text(integralLabel), value: 1, groupValue: _paymentOption, onChanged: (v) => setState(() => _paymentOption = v!)),
                RadioListTile<int>(title: const Text('Nenhum Pagamento Agora'), value: 2, groupValue: _paymentOption, onChanged: (v) => setState(() => _paymentOption = v!)),
                RadioListTile<int>(title: const Text('Outro Valor'), value: 3, groupValue: _paymentOption, onChanged: (v) => setState(() => _paymentOption = v!)),
                
                const Divider(height: 24),

                // A seção de distribuição agora aparece para TODAS as opções de pagamento > 0
                if ((_paymentOption != 2))
                  PaymentDistributionFormPart(
                    key: _distributionFormKey,
                    // Se for "Outro Valor", passamos 0 e o widget se autogerencia
                    totalAmount: _paymentOption == 3 ? 0 : _amountToConfirm,
                  ),

                const SizedBox(height: 16),
                const Text('Deseja anexar um comprovante? (Opcional)'),
                const SizedBox(height: 8),
                Center(child: ElevatedButton.icon(icon: const Icon(Icons.attach_file), label: const Text('Anexar'), onPressed: () async {
                  final result = await FilePicker.platform.pickFiles();
                  if (result != null) setState(() => _pickedFile = result.files.first);
                })),
                if (_pickedFile != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Center(child: Text('Arquivo: ${_pickedFile!.name}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))))
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _onConfirm, child: const Text('Confirmar'))
      ],
    );
  }
}