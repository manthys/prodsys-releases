// lib/widgets/stock_item_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  
  // ##### ALTERAÇÃO: Controller para o campo de texto do produto #####
  final _productController = TextEditingController();
  
  Product? _selectedProduct;
  String _logoType = 'Nenhum';
  bool _isLoading = false;
  bool _fulfillPendingOrders = true;

  @override
  void dispose() {
    _qtyController.dispose();
    _productController.dispose();
    super.dispose();
  }

  // ##### ALTERAÇÃO: Nova função para abrir o diálogo de busca de produto #####
  Future<void> _showProductSearchDialog(List<Product> allProducts) async {
    final Product? result = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductSearchDialog(allProducts: allProducts),
    );

    if (result != null) {
      setState(() {
        _selectedProduct = result;
        _productController.text = '${result.sku} - ${result.name}';
      });
    }
  }

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
              // ##### ALTERAÇÃO: Substituído Dropdown por TextFormField com busca #####
              StreamBuilder<List<Product>>(
                stream: _firestoreService.getProductsStream(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final products = snapshot.data!;
                  return TextFormField(
                    controller: _productController,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Produto',
                      hintText: 'Clique para selecionar um produto',
                      suffixIcon: Icon(Icons.search),
                    ),
                    onTap: () => _showProductSearchDialog(products),
                    validator: (value) => _selectedProduct == null ? 'Selecione um produto' : null,
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
                title: const Text('Nenhuma'),
                value: 'Nenhum',
                groupValue: _logoType,
                onChanged: (value) => setState(() => _logoType = value!),
              ),
              RadioListTile<String>(
                title: const Text('Logomarca da Empresa'),
                value: 'Própria',
                groupValue: _logoType,
                onChanged: (value) => setState(() => _logoType = value!),
              ),
              RadioListTile<String>(
                title: const Text('Logomarca do Cliente'),
                value: 'Cliente',
                groupValue: _logoType,
                onChanged: (value) => setState(() => _logoType = value!),
              ),
              
              const Divider(height: 20),
              CheckboxListTile(
                title: const Text('Usar para atender pedidos pendentes'),
                subtitle: const Text('Se marcado, o estoque quitará as pendências mais antigas.'),
                value: _fulfillPendingOrders,
                onChanged: (value) {
                  setState(() {
                    _fulfillPendingOrders = value ?? true;
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
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
                fulfillPendingOrders: _fulfillPendingOrders,
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

// ##### ALTERAÇÃO: Novo widget de diálogo para a busca de produtos #####
class _ProductSearchDialog extends StatefulWidget {
  final List<Product> allProducts;
  const _ProductSearchDialog({required this.allProducts});

  @override
  State<_ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends State<_ProductSearchDialog> {
  late List<Product> _filteredProducts;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredProducts = List.from(widget.allProducts);
    _searchController.addListener(_filterList);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterList);
    _searchController.dispose();
    super.dispose();
  }

  void _filterList() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredProducts = widget.allProducts.where((product) {
        return product.name.toLowerCase().contains(query) || 
               product.sku.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Selecionar Produto'),
      content: SizedBox(
        width: 400,
        height: 500,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar por nome ou SKU...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredProducts.length,
                itemBuilder: (context, index) {
                  final product = _filteredProducts[index];
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text('SKU: ${product.sku}'),
                    onTap: () => Navigator.of(context).pop(product),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar'))
      ],
    );
  }
}