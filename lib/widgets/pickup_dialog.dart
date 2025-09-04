// lib/widgets/pickup_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/order_model.dart';
import '../models/delivery_selection_item_model.dart';

class PickupDialog extends StatefulWidget {
  final Order order;
  final List<DeliverySelectionItem> itemsReadyForPickup; // TIPO CORRIGIDO AQUI

  const PickupDialog({
    super.key,
    required this.order,
    required this.itemsReadyForPickup, // TIPO CORRIGIDO AQUI
  });

  @override
  State<PickupDialog> createState() => _PickupDialogState();
}

class _PickupDialogState extends State<PickupDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pickupPersonNameController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  late List<DeliverySelectionItem> _selectionItems;

  @override
  void initState() {
    super.initState();
    // Apenas copiamos a lista que já vem pronta
    _selectionItems = List.from(widget.itemsReadyForPickup);
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      final itemsToReturn = _selectionItems
          .where((item) => item.quantityToDeliver > 0)
          .toList();
      
      if (itemsToReturn.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione pelo menos um item para retirar.'), backgroundColor: Colors.red)
        );
        return;
      }

      Navigator.of(context).pop({
        'selectedItems': itemsToReturn,
        'pickupPersonName': _pickupPersonNameController.text,
        'vehiclePlate': _vehiclePlateController.text,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Registrar Retirada - Pedido #${widget.order.id?.substring(0, 6).toUpperCase()}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _pickupPersonNameController,
                  decoration: const InputDecoration(labelText: 'Nome de quem está retirando'),
                  validator: (value) => value == null || value.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _vehiclePlateController,
                  decoration: const InputDecoration(labelText: 'Placa do Veículo (Opcional)'),
                ),
                const Divider(height: 24),
                const Text('Selecione a quantidade de cada item que está sendo retirado:'),
                const SizedBox(height: 16),
                ..._selectionItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                              Text('SKU: ${item.sku} | Logo: ${item.logoType}', style: Theme.of(context).textTheme.bodySmall),
                              Text('Disponível p/ Retirada: ${item.maxQuantity}', style: const TextStyle(color: Colors.green, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 100,
                          child: TextFormField(
                            initialValue: item.quantityToDeliver.toString(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Qtd'),
                            textAlign: TextAlign.center,
                            onSaved: (value) {
                              item.quantityToDeliver = int.tryParse(value ?? '0') ?? 0;
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Req.';
                              final qty = int.tryParse(value);
                              if (qty == null) return 'Inv.';
                              if (qty < 0) return '> 0';
                              if (qty > item.maxQuantity) return 'Máx ${item.maxQuantity}';
                              return null;
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _submit, child: const Text('Registrar Retirada')),
      ],
    );
  }
}