// lib/widgets/delivery_dialog.dart

import 'package:flutter/material.dart';
import '../models/order_model.dart';
import '../models/stock_item_model.dart';
import '../models/product_model.dart';

// Classe auxiliar para gerenciar a contagem de itens na UI
class DeliverySelectionItem {
  final String productId;
  final String sku;
  final String productName;
  final int maxQuantity; // Máximo que pode ser enviado
  int quantityToDeliver; // Quantidade selecionada para esta entrega

  DeliverySelectionItem({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.maxQuantity,
    this.quantityToDeliver = 0,
  });
}

class DeliveryDialog extends StatefulWidget {
  final Order order;
  final List<StockItem> itemsReadyForDelivery;

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
    _initializeSelectionItems();
  }

  void _initializeSelectionItems() {
    final groupedByProduct = <String, int>{};
    for (var stockItem in widget.itemsReadyForDelivery) {
      final key = '${stockItem.productId}|${stockItem.sku}|${stockItem.productName}';
      groupedByProduct.update(key, (value) => value + 1, ifAbsent: () => 1);
    }

    _selectionItems = groupedByProduct.entries.map((entry) {
      final parts = entry.key.split('|');
      return DeliverySelectionItem(
        productId: parts[0],
        sku: parts[1],
        productName: parts[2],
        maxQuantity: entry.value,
        quantityToDeliver: entry.value, // Começa com todos selecionados
      );
    }).toList();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // Filtra apenas os itens que o usuário quer entregar (quantidade > 0)
      final itemsToDeliver = _selectionItems
          .where((item) => item.quantityToDeliver > 0)
          .toList();

      if (itemsToDeliver.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecione pelo menos um item para a entrega.'), backgroundColor: Colors.red),
        );
        return;
      }

      // Retorna os dados para a tela de detalhes do pedido
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
                                Text('SKU: ${item.sku} | Em estoque: ${item.maxQuantity}'),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              initialValue: item.quantityToDeliver.toString(),
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              decoration: const InputDecoration(labelText: 'Qtd.'),
                              onChanged: (value) {
                                final qty = int.tryParse(value) ?? 0;
                                if (qty <= item.maxQuantity) {
                                  item.quantityToDeliver = qty;
                                }
                              },
                              validator: (value) {
                                final qty = int.tryParse(value ?? '') ?? 0;
                                if (qty > item.maxQuantity) {
                                  return 'Máx: ${item.maxQuantity}';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
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