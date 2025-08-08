// lib/widgets/product_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product_model.dart';

class ProductDialog extends StatefulWidget {
  final Product? product;
  const ProductDialog({super.key, this.product});

  @override
  _ProductDialogState createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _name, _sku, _moldType;
  late double _basePrice, _clientLogoPrice;

  @override
  void initState() {
    super.initState();
    _name = widget.product?.name ?? '';
    _sku = widget.product?.sku ?? '';
    _moldType = widget.product?.moldType ?? '';
    _basePrice = widget.product?.basePrice ?? 0.0;
    _clientLogoPrice = widget.product?.clientLogoPrice ?? 0.0;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final newProduct = Product(
        id: widget.product?.id,
        name: _name,
        sku: _sku,
        moldType: _moldType,
        basePrice: _basePrice,
        clientLogoPrice: _clientLogoPrice,
      );
      Navigator.of(context).pop(newProduct);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Novo Produto' : 'Editar Produto'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(initialValue: _name, decoration: const InputDecoration(labelText: 'Nome/Descrição do Produto', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Obrigatório' : null, onSaved: (v) => _name = v!),
              const SizedBox(height: 16),
              TextFormField(initialValue: _sku, decoration: const InputDecoration(labelText: 'SKU (Código Único)', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Obrigatório' : null, onSaved: (v) => _sku = v!),
              const SizedBox(height: 16),
              TextFormField(initialValue: _moldType, decoration: const InputDecoration(labelText: 'Tipo de Forma Utilizada (Ex: T-50)', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Obrigatório' : null, onSaved: (v) => _moldType = v!),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildPriceField('Preço Base (Limpo)', (v) => _basePrice = v, _basePrice)),
                  const SizedBox(width: 16),
                  Expanded(child: _buildPriceField('Adicional Logo Cliente', (v) => _clientLogoPrice = v, _clientLogoPrice)),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _submit, child: const Text('Salvar')),
      ],
    );
  }

  Widget _buildPriceField(String label, Function(double) onSaved, double initialValue) {
    return TextFormField(
      initialValue: initialValue.toString().replaceAll('.', ','),
      decoration: InputDecoration(labelText: label, prefixText: 'R\$ ', border: const OutlineInputBorder()),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+[,.]?\d{0,2}'))],
      validator: (v) => (v == null || double.tryParse(v.replaceAll(',', '.')) == null) ? 'Inválido' : null,
      onSaved: (v) => onSaved(double.parse(v!.replaceAll(',', '.'))),
    );
  }
}