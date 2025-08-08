// lib/widgets/stock_item_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // <-- A CORREÇÃO ESTAVA NESTA LINHA
import '../models/product_model.dart';
import '../services/firestore_service.dart';

class StockItemDialog extends StatefulWidget {
  const StockItemDialog({super.key});

  @override
  _StockItemDialogState createState() => _StockItemDialogState();
}

class _StockItemDialogState extends State<StockItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _qtyController = TextEditingController(text: '1');
  
  Product? _selectedProduct;
  String _logoType = 'Nenhum';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Adicionar Estoque Manual'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<List<Product>>(
                stream: _firestoreService.getProductsStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final products = snapshot.data!;
                  return DropdownButtonFormField<Product>(
                    value: _selectedProduct,
                    hint: const Text('Selecione um Produto'),
                    isExpanded: true,
                    items: products.map((product) => DropdownMenuItem<Product>(
                      value: product,
                      child: Text(product.name, overflow: TextOverflow.ellipsis),
                    )).toList(),
                    onChanged: (product) => setState(() => _selectedProduct = product),
                    validator: (value) => value == null ? 'Selecione um produto' : null,
                  );
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _qtyController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(labelText: 'Quantidade'),
                validator: (v) => (int.tryParse(v ?? '0') ?? 0) <= 0 ? 'Inválido' : null,
              ),
              const SizedBox(height: 16),
              const Text('Tipo de Logo:'),
              RadioListTile<String>(
                title: const Text('Nenhuma'), value: 'Nenhum', groupValue: _logoType,
                onChanged: (value) => setState(() => _logoType = value!),
              ),
              RadioListTile<String>(
                title: const Text('Logomarca da Empresa'), value: 'Própria', groupValue: _logoType,
                onChanged: (value) => setState(() => _logoType = value!),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _isLoading ? null : () async {
            if (_formKey.currentState!.validate()) {
              setState(() => _isLoading = true);
              await _firestoreService.addManualStockItem(
                _selectedProduct!,
                int.parse(_qtyController.text),
                _logoType,
              );
              if (mounted) Navigator.of(context).pop(true);
            }
          },
          child: _isLoading 
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
            : const Text('Adicionar'),
        ),
      ],
    );
  }
}