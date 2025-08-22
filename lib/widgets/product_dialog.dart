// lib/widgets/product_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product_model.dart';
import '../models/price_variation_model.dart';

class ProductDialog extends StatefulWidget {
  final Product? product;
  const ProductDialog({super.key, this.product});

  @override
  State<ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _moldTypeController = TextEditingController();
  final _clientLogoPriceController = TextEditingController();

  // Controladores fixos para os dois tipos de preço
  final _priceWithoutNotaController = TextEditingController();
  final _priceWithNotaController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.product != null) {
      _nameController.text = widget.product!.name;
      _skuController.text = widget.product!.sku;
      _moldTypeController.text = widget.product!.moldType;
      _clientLogoPriceController.text = widget.product!.clientLogoPrice.toString();
      
      // Popula os campos de preço com base na descrição
      final priceWithNota = widget.product!.priceVariations.firstWhere(
        (v) => v.description == 'Com Nota',
        orElse: () => PriceVariation(description: 'Com Nota', price: 0.0),
      );
      final priceWithoutNota = widget.product!.priceVariations.firstWhere(
        (v) => v.description == 'Sem Nota',
        orElse: () => PriceVariation(description: 'Sem Nota', price: 0.0),
      );
      
      _priceWithNotaController.text = priceWithNota.price.toString();
      _priceWithoutNotaController.text = priceWithoutNota.price.toString();
      
    } else {
       // Valores padrão para um novo produto
      _priceWithNotaController.text = '0.0';
      _priceWithoutNotaController.text = '0.0';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _skuController.dispose();
    _moldTypeController.dispose();
    _clientLogoPriceController.dispose();
    _priceWithNotaController.dispose();
    _priceWithoutNotaController.dispose();
    super.dispose();
  }
  
  void _saveForm() {
    if (_formKey.currentState!.validate()) {
      // Cria a lista de variações com base nos controladores
      final List<PriceVariation> priceVariations = [
        PriceVariation(
          description: 'Sem Nota',
          price: double.tryParse(_priceWithoutNotaController.text.replaceAll(',', '.')) ?? 0.0,
        ),
        PriceVariation(
          description: 'Com Nota',
          price: double.tryParse(_priceWithNotaController.text.replaceAll(',', '.')) ?? 0.0,
        ),
      ];
      
      final product = Product(
        id: widget.product?.id,
        name: _nameController.text,
        sku: _skuController.text,
        moldType: _moldTypeController.text,
        clientLogoPrice: double.tryParse(_clientLogoPriceController.text.replaceAll(',', '.')) ?? 0.0,
        priceVariations: priceVariations,
      );
      Navigator.of(context).pop(product);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Novo Produto' : 'Editar Produto'),
      content: SizedBox(
        width: 500, // Largura ajustada
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nome/Descrição'), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
                const SizedBox(height: 16),
                TextFormField(controller: _skuController, decoration: const InputDecoration(labelText: 'SKU'), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
                const SizedBox(height: 16),
                TextFormField(controller: _moldTypeController, decoration: const InputDecoration(labelText: 'Tipo de Forma'), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
                const SizedBox(height: 16),
                TextFormField(controller: _clientLogoPriceController, decoration: const InputDecoration(labelText: 'Adicional por Logo do Cliente (R\$)'), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                const Divider(height: 32),
                Text('Tabela de Preços', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                // Campos fixos para os preços
                TextFormField(
                  controller: _priceWithoutNotaController,
                  decoration: const InputDecoration(labelText: 'Preço SEM Nota (R\$)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v!.isEmpty) return 'Obrigatório';
                    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _priceWithNotaController,
                  decoration: const InputDecoration(labelText: 'Preço COM Nota (R\$)'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) {
                    if (v!.isEmpty) return 'Obrigatório';
                    if (double.tryParse(v.replaceAll(',', '.')) == null) return 'Inválido';
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _saveForm, child: const Text('Salvar')),
      ],
    );
  }
}