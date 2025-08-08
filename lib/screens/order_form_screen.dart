// lib/screens/order_form_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:intl/intl.dart';
import '../models/address_model.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/product_model.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

class OrderFormScreen extends StatefulWidget {
  final Order? existingOrder;
  const OrderFormScreen({super.key, this.existingOrder});
  @override
  _OrderFormScreenState createState() => _OrderFormScreenState();
}

class _OrderFormScreenState extends State<OrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  final _currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  final _shippingCostController = TextEditingController();
  final _notesController = TextEditingController();
  final _deliveryCepController = TextEditingController();
  final _deliveryStreetController = TextEditingController();
  final _deliveryNeighborhoodController = TextEditingController();
  final _deliveryCityController = TextEditingController();
  final _deliveryStateController = TextEditingController();
  final _discountController = TextEditingController();

  Client? _selectedClient;
  List<Client> _allClients = [];
  CompanySettings? _companySettings;
  List<Product> _allProducts = [];
  final List<OrderItem> _orderItems = [];
  String _paymentMethod = 'PIX';
  double _totalItemsAmount = 0.0;
  double _shippingCost = 0.0;
  double _discount = 0.0;
  double _finalAmount = 0.0;
  bool _isLoading = true;
  bool get _isEditing => widget.existingOrder != null;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _shippingCostController.addListener(_calculateTotal);
    _discountController.addListener(_onDiscountChanged);
  }

  @override
  void dispose() {
    _shippingCostController.removeListener(_calculateTotal);
    _discountController.removeListener(_onDiscountChanged);
    _shippingCostController.dispose();
    _notesController.dispose();
    _deliveryCepController.dispose();
    _deliveryStreetController.dispose();
    _deliveryNeighborhoodController.dispose();
    _deliveryCityController.dispose();
    _deliveryStateController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final results = await Future.wait([
      _firestoreService.getProductsStream().first,
      _firestoreService.getCompanySettings(),
      _firestoreService.getClientsStream().first,
    ]);
    _allProducts = results[0] as List<Product>;
    _companySettings = results[1] as CompanySettings;
    _allClients = results[2] as List<Client>;
    if (_isEditing) {
      _populateFormForEditing();
    } else {
      _shippingCostController.text = '0.0';
      _discountController.text = '0.0';
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _populateFormForEditing() {
    final order = widget.existingOrder!;
    _selectedClient = _allClients.firstWhere((c) => c.id == order.clientId);
    _shippingCostController.text = order.shippingCost.toString();
    _discountController.text = order.discount.toString();
    _notesController.text = order.notes ?? '';
    _paymentMethod = order.paymentMethod;
    _orderItems.clear();
    _orderItems.addAll(order.items);
    _updateDeliveryAddressFields(order.deliveryAddress);
    _calculateTotal();
  }

  void _updateDeliveryAddressFields(Address address) {
    _deliveryCepController.text = address.cep;
    _deliveryStreetController.text = address.street;
    _deliveryNeighborhoodController.text = address.neighborhood;
    _deliveryCityController.text = address.city;
    _deliveryStateController.text = address.state;
  }

  void _addProductToOrder(Product product) {
    final qtyController = TextEditingController(text: '1');
    String logoType = 'Nenhum'; 
    showDialog(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) {
      double calculateFinalPrice() {
        double finalPrice = product.basePrice;
        if (logoType == 'Cliente') finalPrice += product.clientLogoPrice;
        return finalPrice;
      }
      return AlertDialog(title: Text('Adicionar ${product.name}'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [TextField(controller: qtyController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Quantidade'), autofocus: true), const SizedBox(height: 16), Text('Logomarca:', style: Theme.of(context).textTheme.bodyMedium), RadioListTile<String>(title: const Text('Nenhuma'), value: 'Nenhum', groupValue: logoType, onChanged: (value) => setDialogState(() => logoType = value!), contentPadding: EdgeInsets.zero), RadioListTile<String>(title: const Text('Logomarca da Empresa'), value: 'Própria', groupValue: logoType, onChanged: (value) => setDialogState(() => logoType = value!), contentPadding: EdgeInsets.zero), RadioListTile<String>(title: Text('Logomarca do Cliente (+ ${_currencyFormatter.format(product.clientLogoPrice)})'), value: 'Cliente', groupValue: logoType, onChanged: (value) => setDialogState(() => logoType = value!), contentPadding: EdgeInsets.zero), const Divider(), const SizedBox(height: 8), Text('Preço Unitário Final: ${_currencyFormatter.format(calculateFinalPrice())}', style: const TextStyle(fontWeight: FontWeight.bold))])), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')), ElevatedButton(onPressed: () {
        final qty = int.tryParse(qtyController.text) ?? 0;
        if (qty > 0) {
          setState(() {
            _orderItems.add(OrderItem(productId: product.id!, sku: product.sku, productName: product.name, quantity: qty, finalUnitPrice: calculateFinalPrice(), logoType: logoType, includesLid: false));
            _calculateTotal();
          });
          Navigator.of(context).pop();
        }
      }, child: const Text('Adicionar'))]);
    }));
  }
  
  void _onDiscountChanged() {
    setState(() {
      _discount = double.tryParse(_discountController.text.replaceAll(',', '.')) ?? 0.0;
      _calculateTotal();
    });
  }

  void _applyDiscountPercentage(double percentage) {
    final subtotal = _totalItemsAmount + _shippingCost;
    final discountValue = subtotal * percentage;
    setState(() {
      _discountController.text = discountValue.toStringAsFixed(2);
    });
  }

  void _calculateTotal() {
    setState(() {
      _totalItemsAmount = _orderItems.fold(0.0, (sum, item) => sum + item.totalPrice);
      _shippingCost = double.tryParse(_shippingCostController.text.replaceAll(',', '.')) ?? 0.0;
      _discount = double.tryParse(_discountController.text.replaceAll(',', '.')) ?? 0.0;
      _finalAmount = _totalItemsAmount + _shippingCost - _discount;
    });
  }

  void _saveOrder() async {
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro: Usuário não autenticado.'), backgroundColor: Colors.red));
      return;
    }
    if (_formKey.currentState!.validate() && _selectedClient != null && _orderItems.isNotEmpty) {
      final deliveryAddress = Address(cep: _deliveryCepController.text, street: _deliveryStreetController.text, neighborhood: _deliveryNeighborhoodController.text, city: _deliveryCityController.text, state: _deliveryStateController.text);
      if (_isEditing) {
        final updatedOrder = widget.existingOrder!.copyWith(
          clientId: _selectedClient!.id!, clientName: _selectedClient!.name, items: _orderItems,
          totalItemsAmount: _totalItemsAmount, shippingCost: _shippingCost, discount: _discount, finalAmount: _finalAmount,
          notes: _notesController.text, paymentMethod: _paymentMethod, deliveryAddress: deliveryAddress,
        );
        await _firestoreService.updateOrder(updatedOrder);
        if (mounted) Navigator.of(context).pop(updatedOrder);
      } else {
        final newOrder = Order(
          clientId: _selectedClient!.id!, clientName: _selectedClient!.name, items: _orderItems,
          creationDate: Timestamp.now(), totalItemsAmount: _totalItemsAmount,
          shippingCost: _shippingCost, discount: _discount, finalAmount: _finalAmount,
          notes: _notesController.text,
          paymentTerms: _companySettings?.defaultPaymentTerms ?? '50% de entrada e 50% na entrega.',
          paymentMethod: _paymentMethod,
          createdByUserId: currentUser.uid,
          createdByUserName: currentUser.displayName ?? currentUser.email ?? 'Usuário Desconhecido',
          deliveryAddress: deliveryAddress,
        );
        await _firestoreService.addOrder(newOrder);
        if (mounted) Navigator.of(context).pop();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, selecione um cliente e adicione pelo menos um item.'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Pedido' : 'Nova Cotação'),
        actions: [IconButton(icon: const Icon(Icons.save), onPressed: _saveOrder, tooltip: 'Salvar')]
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dados Principais', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<Client>(
                      value: _selectedClient,
                      hint: const Text('Selecione um Cliente'),
                      decoration: const InputDecoration(labelText: 'Cliente', border: OutlineInputBorder()),
                      items: _allClients.map((client) => DropdownMenuItem<Client>(value: client, child: Text(client.name))).toList(),
                      onChanged: (client) {
                        setState(() {
                          _selectedClient = client;
                          if (client != null) _updateDeliveryAddressFields(client.deliveryAddress);
                        });
                      },
                      validator: (value) => value == null ? 'Selecione um cliente' : null,
                    ),
                    const SizedBox(height: 16),
                    Text('Forma de Pagamento', style: Theme.of(context).textTheme.titleSmall),
                    Row(
                      children: [
                        Expanded(child: RadioListTile<String>(title: const Text('PIX'), value: 'PIX', groupValue: _paymentMethod, onChanged: (value) => setState(() => _paymentMethod = value!))),
                        Expanded(child: RadioListTile<String>(title: const Text('Cartão'), value: 'Cartão', groupValue: _paymentMethod, onChanged: (value) => setState(() => _paymentMethod = value!))),
                        Expanded(child: RadioListTile<String>(title: const Text('Outro'), value: 'Outro', groupValue: _paymentMethod, onChanged: (value) => setState(() => _paymentMethod = value!))),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Endereço de Entrega', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextFormField(controller: _deliveryCepController, decoration: const InputDecoration(labelText: 'CEP', border: OutlineInputBorder()))),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: TextFormField(controller: _deliveryStreetController, decoration: const InputDecoration(labelText: 'Rua', border: OutlineInputBorder()))),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: TextFormField(controller: _deliveryNeighborhoodController, decoration: const InputDecoration(labelText: 'Bairro', border: OutlineInputBorder()))),
                      const SizedBox(width: 16),
                      Expanded(child: TextFormField(controller: _deliveryCityController, decoration: const InputDecoration(labelText: 'Cidade', border: OutlineInputBorder()))),
                      const SizedBox(width: 16),
                      SizedBox(width: 100, child: TextFormField(controller: _deliveryStateController, decoration: const InputDecoration(labelText: 'UF', border: OutlineInputBorder()))),
                    ]),
                    const SizedBox(height: 24),
                    Text('Itens do Pedido', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _orderItems.length,
                      itemBuilder: (context, index) {
                        final item = _orderItems[index];
                        return ListTile(
                          title: Text(item.productName),
                          subtitle: Text('${item.quantity} x ${_currencyFormatter.format(item.finalUnitPrice)}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_currencyFormatter.format(item.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() {
                                _orderItems.removeAt(index);
                                _calculateTotal();
                              }))
                            ],
                          ),
                        );
                      },
                    ),
                    if (_orderItems.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16.0), child: Center(child: Text('Nenhum item adicionado.'))),
                    const SizedBox(height: 16),
                    SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Adicionar Produto'), onPressed: () {
                      showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Selecione um Produto'), content: SizedBox(width: 300, child: ListView.builder(shrinkWrap: true, itemCount: _allProducts.length, itemBuilder: (context, index) {
                        final product = _allProducts[index];
                        return ListTile(title: Text(product.name), onTap: () {
                          Navigator.of(context).pop();
                          _addProductToOrder(product);
                        });
                      }))));
                    })),
                    const Divider(height: 32),
                    Text('Custos e Descontos', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _notesController,
                            decoration: const InputDecoration(labelText: 'Observações', border: OutlineInputBorder()),
                            maxLines: 3,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: Column(
                            children: [
                              TextFormField(controller: _shippingCostController, decoration: const InputDecoration(labelText: 'Custo do Frete', prefixText: 'R\$ ', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                              const SizedBox(height: 16),
                              TextFormField(controller: _discountController, decoration: const InputDecoration(labelText: 'Desconto (Valor Fixo)', prefixText: 'R\$ ', border: OutlineInputBorder()), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  ElevatedButton(onPressed: () => _applyDiscountPercentage(0.05), child: const Text('5%')),
                                  ElevatedButton(onPressed: () => _applyDiscountPercentage(0.10), child: const Text('10%')),
                                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.tertiary), onPressed: () => _discountController.text = '0.0', child: const Text('Zerar')),
                                ],
                              )
                            ],
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            _buildTotalRow('Subtotal Itens', _totalItemsAmount),
                            _buildTotalRow('Frete', _shippingCost),
                            _buildTotalRow('Desconto', -_discount, isDiscount: true),
                            const Divider(),
                            _buildTotalRow('TOTAL', _finalAmount, isTotal: true),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTotalRow(String label, double value, {bool isDiscount = false, bool isTotal = false}) {
    final style = TextStyle(
      fontSize: isTotal ? 18 : 16,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: isDiscount ? Colors.red : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(_currencyFormatter.format(value), style: style),
        ],
      ),
    );
  }
}