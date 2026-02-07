// lib/widgets/delivery_dialog.dart

import 'package:flutter/material.dart';
import '../models/order_model.dart';
import '../models/delivery_selection_item_model.dart';

class DeliveryDialog extends StatefulWidget {
  final Order order;
  final List<DeliverySelectionItem> itemsReadyForDelivery;

  const DeliveryDialog({
    super.key,
    required this.order,
    required this.itemsReadyForDelivery,
  });

  @override
  State<DeliveryDialog> createState() => _DeliveryDialogState();
}

class _DeliveryDialogState extends State<DeliveryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _driverNameController = TextEditingController();
  final _vehiclePlateController = TextEditingController();
  
  late List<DeliverySelectionItem> _selectionItems;

  @override
  void initState() {
    super.initState();
    _selectionItems = List.from(widget.itemsReadyForDelivery);
  }

  double get _totalWeight {
    return _selectionItems.fold(0.0, (sum, item) => sum + (item.quantityToDeliver * item.unitWeight));
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final itemsToDeliver = _selectionItems
          .where((item) => item.quantityToDeliver > 0)
          .toList();

      if (itemsToDeliver.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione pelo menos um item para a entrega.'), backgroundColor: Colors.red),
        );
        return;
      }

      Navigator.of(context).pop({
        'driverName': _driverNameController.text,
        'vehiclePlate': _vehiclePlateController.text,
        'selectedItems': itemsToDeliver,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Registrar Nova Entrega - Pedido #${widget.order.id?.substring(0, 6).toUpperCase()}'),
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
                  controller: _driverNameController,
                  decoration: const InputDecoration(labelText: 'Nome do Motorista/Responsável'),
                  validator: (value) => value == null || value.isEmpty ? 'Campo obrigatório' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _vehiclePlateController,
                  decoration: const InputDecoration(labelText: 'Placa do Veículo (Opcional)'),
                ),
                const Divider(height: 32),
                
                // BARRA DE PESO TOTAL
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Peso Total Estimado:', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('${_totalWeight.toStringAsFixed(1)} kg', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Text('Itens para esta entrega:', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._selectionItems.map((item) {
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('SKU: ${item.sku} | Disponível: ${item.maxQuantity}'),
                                Text('Peso un: ${item.unitWeight} kg', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              initialValue: item.quantityToDeliver.toString(),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(labelText: 'Qtd'),
                              onChanged: (value) {
                                final qty = int.tryParse(value) ?? 0;
                                setState(() {
                                  item.quantityToDeliver = qty;
                                });
                              },
                              validator: (value) {
                                final qty = int.tryParse(value ?? '') ?? 0;
                                if (qty > item.maxQuantity) {
                                  return 'Máx: ${item.maxQuantity}';
                                }
                                if(qty < 0){
                                  return 'Inválido';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
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
        ElevatedButton(onPressed: _submit, child: const Text('Confirmar Entrega')),
      ],
    );
  }
}