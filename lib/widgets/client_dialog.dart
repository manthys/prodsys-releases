// lib/widgets/client_dialog.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../models/client_model.dart';
import '../models/address_model.dart';

class ClientDialog extends StatefulWidget {
  final Client? client;
  const ClientDialog({super.key, this.client});
  @override
  _ClientDialogState createState() => _ClientDialogState();
}

class _ClientDialogState extends State<ClientDialog> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;

  late TextEditingController _nameController, _cnpjController, _ieController, _phoneController, _emailController;
  late TextEditingController _billingCepController, _billingStreetController, _billingNeighborhoodController, _billingCityController, _billingStateController;
  late TextEditingController _deliveryCepController, _deliveryStreetController, _deliveryNeighborhoodController, _deliveryCityController, _deliveryStateController;

  bool _deliverySameAsBilling = true;
  bool _isLoadingCep = false;
  
  final _phoneMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final _cepMask = MaskTextInputFormatter(mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeControllers();
  }
  
  void _initializeControllers() {
    final billing = widget.client?.billingAddress ?? Address();
    final delivery = widget.client?.deliveryAddress ?? Address();
    _nameController = TextEditingController(text: widget.client?.name ?? '');
    _cnpjController = TextEditingController(text: widget.client?.cnpj ?? '');
    _ieController = TextEditingController(text: widget.client?.ie ?? '');
    _phoneController = TextEditingController(text: widget.client?.phone ?? '');
    _emailController = TextEditingController(text: widget.client?.email ?? '');
    _billingCepController = TextEditingController(text: billing.cep);
    _billingStreetController = TextEditingController(text: billing.street);
    _billingNeighborhoodController = TextEditingController(text: billing.neighborhood);
    _billingCityController = TextEditingController(text: billing.city);
    _billingStateController = TextEditingController(text: billing.state);
    _deliveryCepController = TextEditingController(text: delivery.cep);
    _deliveryStreetController = TextEditingController(text: delivery.street);
    _deliveryNeighborhoodController = TextEditingController(text: delivery.neighborhood);
    _deliveryCityController = TextEditingController(text: delivery.city);
    _deliveryStateController = TextEditingController(text: delivery.state);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _cnpjController.dispose();
    _ieController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _billingCepController.dispose();
    _billingStreetController.dispose();
    _billingNeighborhoodController.dispose();
    _billingCityController.dispose();
    _billingStateController.dispose();
    _deliveryCepController.dispose();
    _deliveryStreetController.dispose();
    _deliveryNeighborhoodController.dispose();
    _deliveryCityController.dispose();
    _deliveryStateController.dispose();
    super.dispose();
  }

  Future<void> _fetchCep(TextEditingController cepCtrl, TextEditingController streetCtrl, TextEditingController neighborhoodCtrl, TextEditingController cityCtrl, TextEditingController stateCtrl) async {
    final cep = cepCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) return;
    setState(() => _isLoadingCep = true);
    try {
      final response = await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (mounted && response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['erro'] != true) {
          streetCtrl.text = data['logradouro'];
          neighborhoodCtrl.text = data['bairro'];
          cityCtrl.text = data['localidade'];
          stateCtrl.text = data['uf'];
        } else {
          _showErrorSnackBar('CEP não encontrado.');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Erro ao buscar CEP.');
    } finally {
      if (mounted) setState(() => _isLoadingCep = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }
  
  void _submit() {
    if (_formKey.currentState!.validate()) {
      final billingAddr = Address(
        cep: _billingCepController.text, street: _billingStreetController.text, neighborhood: _billingNeighborhoodController.text,
        city: _billingCityController.text, state: _billingStateController.text,
      );
      final deliveryAddr = _deliverySameAsBilling ? billingAddr : Address(
        cep: _deliveryCepController.text, street: _deliveryStreetController.text, neighborhood: _deliveryNeighborhoodController.text,
        city: _deliveryCityController.text, state: _deliveryStateController.text,
      );
      final updatedClient = Client(
        id: widget.client?.id, name: _nameController.text, cnpj: _cnpjController.text, ie: _ieController.text,
        phone: _phoneController.text, email: _emailController.text, billingAddress: billingAddr, deliveryAddress: deliveryAddr,
      );
      Navigator.of(context).pop(updatedClient);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.client == null ? 'Novo Cliente' : 'Editar Cliente'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.6,
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              TabBar(
                controller: _tabController,
                tabs: const [ Tab(icon: Icon(Icons.person), text: 'Dados Principais'), Tab(icon: Icon(Icons.location_on), text: 'Endereços')],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [ _buildMainDataTab(), _buildAddressTab()],
                ),
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

  Widget _buildMainDataTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nome / Razão Social', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: TextFormField(
                controller: _cnpjController,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly, // Garante que só números sejam digitados
                  _CpfCnpjFormatter(), // Nosso formatador inteligente
                ],
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'CPF / CNPJ', border: OutlineInputBorder()),
              )),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(controller: _ieController, decoration: const InputDecoration(labelText: 'IE / RG', border: OutlineInputBorder()))),
            ],
          ),
          const SizedBox(height: 16),
            Row(
            children: [
              Expanded(child: TextFormField(controller: _phoneController, inputFormatters: [_phoneMask], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone', border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? 'Obrigatório' : null)),
              const SizedBox(width: 16),
              Expanded(child: TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAddressTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Endereço de Cobrança/Faturamento', style: Theme.of(context).textTheme.titleMedium),
          _buildAddressForm(_billingCepController, _billingStreetController, _billingNeighborhoodController, _billingCityController, _billingStateController),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Endereço de entrega é o mesmo da cobrança'),
            value: _deliverySameAsBilling,
            onChanged: (value) => setState(() => _deliverySameAsBilling = value ?? true),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          if (!_deliverySameAsBilling) ...[
            const SizedBox(height: 16),
            Text('Endereço de Entrega', style: Theme.of(context).textTheme.titleMedium),
            _buildAddressForm(_deliveryCepController, _deliveryStreetController, _deliveryNeighborhoodController, _deliveryCityController, _deliveryStateController),
          ]
        ],
      ),
    );
  }
  
  Widget _buildAddressForm(TextEditingController cepCtrl, TextEditingController streetCtrl, TextEditingController neighborhoodCtrl, TextEditingController cityCtrl, TextEditingController stateCtrl) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2, 
              child: TextFormField(
                controller: cepCtrl, 
                inputFormatters: [_cepMask], 
                keyboardType: TextInputType.number, 
                decoration: InputDecoration(
                  labelText: 'CEP', 
                  border: const OutlineInputBorder(), 
                  suffixIcon: _isLoadingCep 
                    ? const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2,)) 
                    : IconButton(icon: const Icon(Icons.search), onPressed: () => _fetchCep(cepCtrl, streetCtrl, neighborhoodCtrl, cityCtrl, stateCtrl))
                )
              )
            ),
            const SizedBox(width: 16),
            Expanded(flex: 4, child: TextFormField(controller: streetCtrl, decoration: const InputDecoration(labelText: 'Rua / Logradouro', border: OutlineInputBorder()))),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(flex: 3, child: TextFormField(controller: neighborhoodCtrl, decoration: const InputDecoration(labelText: 'Bairro', border: OutlineInputBorder()))),
            const SizedBox(width: 16),
            Expanded(flex: 3, child: TextFormField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'Cidade', border: OutlineInputBorder()))),
            const SizedBox(width: 16),
            SizedBox(width: 80, child: TextFormField(controller: stateCtrl, decoration: const InputDecoration(labelText: 'UF', border: OutlineInputBorder()))),
          ],
        ),
      ],
    );
  }
}

// ===== NOVO FORMATADOR INTELIGENTE E CORRETO =====
class _CpfCnpjFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    
    // Já removemos os não-dígitos com o FilteringTextInputFormatter, aqui só formatamos
    if (text.isEmpty) {
      return newValue;
    }

    final digitsOnly = text.replaceAll(RegExp(r'[^\d]'), '');

    // ===== ADICIONADO LIMITE DE 14 DÍGITOS =====
    if (digitsOnly.length > 14) {
      return oldValue; // Impede que mais números sejam digitados
    }

    String newText;

    if (digitsOnly.length <= 11) {
      // Formato CPF
      newText = digitsOnly.replaceAllMapped(
        RegExp(r'(\d{3})(\d{3})(\d{3})(\d{2})'),
        (Match m) => '${m[1]}.${m[2]}.${m[3]}-${m[4]}',
      );
    } else {
      // Formato CNPJ
      newText = digitsOnly.replaceAllMapped(
        RegExp(r'(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})'),
        (Match m) => '${m[1]}.${m[2]}.${m[3]}/${m[4]}-${m[5]}',
      );
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}