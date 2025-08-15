// lib/widgets/stock_adjustment_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/stock_item_model.dart';
import '../models/product_model.dart';

class StockAdjustmentDialog extends StatefulWidget {
  final Map<String, dynamic> stockGroup;

  const StockAdjustmentDialog({super.key, required this.stockGroup});

  @override
  _StockAdjustmentDialogState createState() => _StockAdjustmentDialogState();
}

class _StockAdjustmentDialogState extends State<StockAdjustmentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  
  late int _initialQuantity;

  @override
  void initState() {
    super.initState();
    _initialQuantity = widget.stockGroup['count'];
    _quantityController.text = _initialQuantity.toString();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final newQuantity = int.parse(_quantityController.text);
      Navigator.of(context).pop({
        'newQuantity': newQuantity,
        'reason': _reasonController.text,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final StockItem item = widget.stockGroup['item'];

    return AlertDialog(
      title: Text('Ajustar Estoque de ${item.productName}'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Produto: ${item.sku} - ${item.productName}'),
            Text('Status: ${_getStatusName(item.status)}'),
            Text('Pedido: ${item.orderId?.substring(0, 6).toUpperCase() ?? 'Estoque Manual'}'),
            const SizedBox(height: 20),
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(labelText: 'Nova Quantidade Correta', hintText: 'Quantidade atual: $_initialQuantity'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.isEmpty) return 'Obrigatório';
                if (int.tryParse(value) == null) return 'Número inválido';
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'Motivo do Ajuste'),
              validator: (value) => value!.isEmpty ? 'O motivo é obrigatório' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _submit, child: const Text('Confirmar Ajuste')),
      ],
    );
  }

  String _getStatusName(StockItemStatus status) {
    switch (status) {
      case StockItemStatus.aguardandoProducao: return 'Aguardando Produção';
      case StockItemStatus.emEstoque: return 'Em Estoque';
      case StockItemStatus.emTransito: return 'Em Trânsito';
      case StockItemStatus.entregue: return 'Entregue';
    }
  }
}