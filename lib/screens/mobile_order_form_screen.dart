// lib/screens/mobile_order_form_screen.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import '../models/address_model.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/price_variation_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import 'mobile_client_form_screen.dart';
import 'mobile_product_picker_screen.dart';
// =================================================================
// IMPORTAÇÃO QUE FALTAVA
// =================================================================
import '../widgets/currency_input_formatter.dart'; 
// =================================================================
// IMPORTAÇÃO ADICIONADA PARA A LÓGICA DE SELEÇÃO
// =================================================================
import 'mobile_clients_screen.dart';

class MobileOrderFormScreen extends StatefulWidget {
  const MobileOrderFormScreen({super.key});

  @override
  State<MobileOrderFormScreen> createState() => _MobileOrderFormScreenState();
}

class _MobileOrderFormScreenState extends State<MobileOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _authService = AuthService();
  final _currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  
  // Controladores
  final _clientController = TextEditingController();
  final _buyerNameController = TextEditingController();
  final _buyerPhoneController = TextEditingController();
  final _buyerEmailController = TextEditingController();
  final _shippingCostController = TextEditingController(text: '0,00');
  final _discountController = TextEditingController(text: '0,00');

  // Estado do Formulário
  int _currentStep = 0;
  Client? _selectedClient;
  final List<OrderItem> _orderItems = [];
  double _totalItemsAmount = 0.0;
  double _shippingCost = 0.0;
  double _discount = 0.0;
  double _finalAmount = 0.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _shippingCostController.addListener(_calculateTotal);
    _discountController.addListener(_calculateTotal);
  }

  @override
  void dispose() {
    _clientController.dispose();
    _buyerNameController.dispose();
    _buyerPhoneController.dispose();
    _buyerEmailController.dispose();
    _shippingCostController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  void _calculateTotal() {
    setState(() {
      _totalItemsAmount = _orderItems.fold(0.0, (sum, item) => sum + item.totalPrice);
      _shippingCost = double.tryParse(_shippingCostController.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
      _discount = double.tryParse(_discountController.text.replaceAll('.', '').replaceAll(',', '.')) ?? 0.0;
      _finalAmount = _totalItemsAmount + _shippingCost - _discount;
    });
  }

  void _onStepContinue() {
    if (_currentStep == 0 && _selectedClient == null) {
      _showErrorSnackBar('Por favor, selecione um cliente.');
      return;
    }
    if (_currentStep == 1 && _orderItems.isEmpty) {
      _showErrorSnackBar('Adicione pelo menos um item ao pedido.');
      return;
    }
    
    if (_currentStep < 2) {
      setState(() => _currentStep += 1);
    } else {
      _saveOrder();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  void _selectClient() async {
    FocusScope.of(context).unfocus();
    
    final result = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Selecionar Cliente'),
        content: const Text('Deseja selecionar um cliente existente ou cadastrar um novo?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop('new'), child: const Text('+ Novo Cliente')),
          TextButton(onPressed: () => Navigator.of(ctx).pop('pick'), child: const Text('Selecionar Existente')),
        ],
      )
    );

    if (result == 'new') {
      _createNewClient();
    } else if (result == 'pick') {
      _pickClient();
    }
  }

  void _pickClient() async {
    final client = await Navigator.of(context).push<Client>(
      MaterialPageRoute(builder: (ctx) => const MobileClientsScreen(isPickerMode: true)) // <-- 'const' CORRIGIDO
    );
    if (client != null) {
      _setClient(client);
    }
  }

  void _createNewClient() async {
    final newClient = await Navigator.of(context).push<Client>(
      MaterialPageRoute(builder: (ctx) => const MobileClientFormScreen())
    );
    if (newClient != null) {
      _setClient(newClient);
    }
  }

  void _setClient(Client client) {
    setState(() {
      _selectedClient = client;
      _clientController.text = client.name;
    });
  }
  
  void _addProduct() async {
    final product = await Navigator.of(context).push<Product>(
      MaterialPageRoute(builder: (ctx) => const MobileProductPickerScreen())
    );
    if (product == null) return;
    
    PriceVariation selectedVariation = product.priceVariations.firstWhere((v) => v.description == 'Sem Nota', orElse: () => product.priceVariations.first);
    
    final qtyController = TextEditingController(text: '1');
    String logoType = 'Nenhum'; 

    final OrderItem? newItem = await showDialog<OrderItem>(
      context: context, 
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double calculateFinalPrice() {
            double finalPrice = selectedVariation.price;
            if (logoType == 'Cliente') finalPrice += product.clientLogoPrice;
            return finalPrice;
          }
          return AlertDialog(
            title: Text('Adicionar ${product.name}'), 
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                crossAxisAlignment: CrossAxisAlignment.start, 
                children: [
                  Text('Tabela de Preço:', style: Theme.of(context).textTheme.bodyMedium),
                  ...product.priceVariations.map((v) => RadioListTile<PriceVariation>(
                    title: Text('${v.description} (${_currencyFormatter.format(v.price)})'),
                    value: v,
                    groupValue: selectedVariation,
                    onChanged: (val) => setDialogState(() => selectedVariation = val!),
                  )),
                  const Divider(),
                  TextField(controller: qtyController, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly], decoration: const InputDecoration(labelText: 'Quantidade'), autofocus: true),
                  const SizedBox(height: 16),
                  Text('Logomarca:', style: Theme.of(context).textTheme.bodyMedium), 
                  RadioListTile<String>(title: const Text('Nenhuma'), value: 'Nenhum', groupValue: logoType, onChanged: (value) => setDialogState(() => logoType = value!), contentPadding: EdgeInsets.zero), 
                  RadioListTile<String>(title: const Text('Logomarca da Empresa'), value: 'Própria', groupValue: logoType, onChanged: (value) => setDialogState(() => logoType = value!), contentPadding: EdgeInsets.zero), 
                  RadioListTile<String>(title: Text('Logomarca do Cliente (+ ${_currencyFormatter.format(product.clientLogoPrice)})'), value: 'Cliente', groupValue: logoType, onChanged: (value) => setDialogState(() => logoType = value!), contentPadding: EdgeInsets.zero),
                  const Divider(),
                  Text('Preço Unitário Final: ${_currencyFormatter.format(calculateFinalPrice())}', style: const TextStyle(fontWeight: FontWeight.bold))
                ]
              )
            ), 
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')), 
              ElevatedButton(onPressed: () {
                final qty = int.tryParse(qtyController.text) ?? 0;
                if (qty > 0) {
                  Navigator.of(context).pop(OrderItem(
                    productId: product.id!, sku: product.sku, productName: product.name, 
                    quantity: qty, finalUnitPrice: calculateFinalPrice(), 
                    logoType: logoType, includesLid: false
                  ));
                }
              }, child: const Text('Adicionar'))
            ]
          );
        }
      )
    );

    if (newItem != null) {
      setState(() {
        _orderItems.add(newItem);
        _calculateTotal();
      });
    }
  }

  void _removeOrderItem(int index) {
    setState(() {
      _orderItems.removeAt(index);
      _calculateTotal();
    });
  }

  void _saveOrder() async {
    if (_formKey.currentState!.validate() && _selectedClient != null && _orderItems.isNotEmpty) {
      setState(() => _isLoading = true);
      
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        _showErrorSnackBar('Erro: Usuário não autenticado.');
        setState(() => _isLoading = false);
        return;
      }
      
      final companySettings = await _firestoreService.getCompanySettings();

      final newOrder = Order(
        clientId: _selectedClient!.id!,
        clientName: _selectedClient!.name,
        buyerName: _buyerNameController.text,
        buyerPhone: _buyerPhoneController.text,
        buyerEmail: _buyerEmailController.text,
        items: _orderItems,
        creationDate: Timestamp.now(),
        totalItemsAmount: _totalItemsAmount,
        shippingCost: _shippingCost,
        discount: _discount,
        finalAmount: _finalAmount,
        notes: null, 
        paymentTerms: companySettings.defaultPaymentTerms,
        paymentMethod: 'PIX',
        createdByUserId: currentUser.uid,
        createdByUserName: currentUser.displayName ?? currentUser.email ?? 'Usuário Desconhecido',
        deliveryAddress: _selectedClient!.deliveryAddress,
      );
      
      try {
        await _firestoreService.addOrder(newOrder);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cotação criada com sucesso!'), backgroundColor: Colors.green)
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        _showErrorSnackBar('Erro ao salvar cotação: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else if (_selectedClient == null) {
      _showErrorSnackBar('Selecione um cliente.');
    } else if (_orderItems.isEmpty) {
       _showErrorSnackBar('Adicione pelo menos um item.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nova Cotação'),
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: _onStepContinue,
          onStepCancel: _onStepCancel,
          onStepTapped: (step) => setState(() => _currentStep = step),
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 16.0),
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: [
                      ElevatedButton(
                        onPressed: details.onStepContinue,
                        child: Text(_currentStep == 2 ? 'SALVAR COTAÇÃO' : 'PRÓXIMO'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: details.onStepCancel,
                        child: Text(_currentStep == 0 ? 'CANCELAR' : 'VOLTAR'),
                      ),
                    ],
                  ),
            );
          },
          steps: [
            Step(
              title: const Text('Cliente'),
              isActive: _currentStep >= 0,
              state: _currentStep > 0 ? StepState.complete : StepState.indexed,
              content: _buildStepCliente(),
            ),
            Step(
              title: const Text('Itens'),
              isActive: _currentStep >= 1,
              state: _currentStep > 1 ? StepState.complete : StepState.indexed,
              content: _buildStepItens(),
            ),
            Step(
              title: const Text('Resumo'),
              isActive: _currentStep >= 2,
              content: _buildStepResumo(),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStepCliente() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _clientController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Cliente Selecionado',
            hintText: 'Toque para selecionar',
            border: OutlineInputBorder(),
          ),
          onTap: _selectClient,
          validator: (v) => _selectedClient == null ? 'Selecione um cliente' : null,
        ),
        const SizedBox(height: 16),
        Text('Contato do Pedido (Opcional)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextFormField(controller: _buyerNameController, decoration: const InputDecoration(labelText: 'Nome do Comprador')),
        const SizedBox(height: 12),
        TextFormField(controller: _buyerPhoneController, decoration: const InputDecoration(labelText: 'Telefone do Comprador'), keyboardType: TextInputType.phone),
        const SizedBox(height: 12),
        TextFormField(controller: _buyerEmailController, decoration: const InputDecoration(labelText: 'E-mail do Comprador'), keyboardType: TextInputType.emailAddress),
      ],
    );
  }

  Widget _buildStepItens() {
    return Column(
      children: [
        if (_orderItems.isEmpty)
          const Center(child: Text('Nenhum item adicionado.', style: TextStyle(color: Colors.grey))),
        
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _orderItems.length,
          itemBuilder: (context, index) {
            final item = _orderItems[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(item.productName),
                subtitle: Text('${item.quantity} x ${_currencyFormatter.format(item.finalUnitPrice)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_currencyFormatter.format(item.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _removeOrderItem(index),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Adicionar Produto'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 40)),
          onPressed: _addProduct,
        )
      ],
    );
  }
  
  Widget _buildStepResumo() {
    return Column(
      children: [
        TextFormField(
          controller: _shippingCostController, 
          decoration: const InputDecoration(labelText: 'Custo do Frete', prefixText: 'R\$ '), 
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [CurrencyInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _discountController, 
          decoration: const InputDecoration(labelText: 'Desconto (Valor Fixo)', prefixText: 'R\$ '), 
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [CurrencyInputFormatter()],
        ),
        const Divider(height: 32),
        _buildTotalRow('Subtotal Itens', _currencyFormatter.format(_totalItemsAmount)),
        _buildTotalRow('Frete', _currencyFormatter.format(_shippingCost)),
        _buildTotalRow('Desconto', '- ${_currencyFormatter.format(_discount)}', color: Colors.red),
        const SizedBox(height: 8),
        _buildTotalRow('TOTAL', _currencyFormatter.format(_finalAmount), isTotal: true),
      ],
    );
  }

  Widget _buildTotalRow(String label, String value, {Color? color, bool isTotal = false}) {
    final style = TextStyle(
      fontSize: isTotal ? 18 : 15,
      fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}