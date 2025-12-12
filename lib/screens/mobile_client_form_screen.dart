// lib/screens/mobile_client_form_screen.dart (VERSÃO COMPLETA E CORRIGIDA)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../models/client_model.dart';
import '../models/address_model.dart';
import '../services/firestore_service.dart';

class MobileClientFormScreen extends StatefulWidget {
  final Client? client;

  const MobileClientFormScreen({super.key, this.client});

  @override
  _MobileClientFormScreenState createState() => _MobileClientFormScreenState();
}

class _MobileClientFormScreenState extends State<MobileClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  bool _isLoading = false;
  bool _isLoadingCep = false;

  late TextEditingController _nameController, _cnpjController, _ieController, _phoneController, _emailController;
  late TextEditingController _billingCepController, _billingStreetController, _billingNeighborhoodController, _billingCityController, _billingStateController;
  late TextEditingController _deliveryCepController, _deliveryStreetController, _deliveryNeighborhoodController, _deliveryCityController, _deliveryStateController;

  bool _deliverySameAsBilling = true;
  
  final _phoneMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final _cepMask = MaskTextInputFormatter(mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    
    if (widget.client != null) {
      _deliverySameAsBilling = widget.client!.billingAddress.cep == widget.client!.deliveryAddress.cep &&
                               widget.client!.billingAddress.street == widget.client!.deliveryAddress.street;
    }
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
          setState(() {
            streetCtrl.text = data['logradouro'];
            neighborhoodCtrl.text = data['bairro'];
            cityCtrl.text = data['localidade'];
            stateCtrl.text = data['uf'];
          });
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
  
  // =================================================================
  // FUNÇÃO _submit CORRIGIDA
  // =================================================================
  void _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final billingAddr = Address(
        cep: _billingCepController.text, street: _billingStreetController.text, neighborhood: _billingNeighborhoodController.text,
        city: _billingCityController.text, state: _billingStateController.text,
      );
      final deliveryAddr = _deliverySameAsBilling ? billingAddr : Address(
        cep: _deliveryCepController.text, street: _deliveryStreetController.text, neighborhood: _deliveryNeighborhoodController.text,
        city: _deliveryCityController.text, state: _deliveryStateController.text,
      );
      
      Client clientToSave = Client(
        id: widget.client?.id, name: _nameController.text, cnpj: _cnpjController.text, ie: _ieController.text,
        phone: _phoneController.text, email: _emailController.text, billingAddress: billingAddr, deliveryAddress: deliveryAddr,
      );

      try {
        if (widget.client == null) {
          final docRef = await _firestoreService.addClient(clientToSave);
          clientToSave = clientToSave.copyWith(id: docRef.id); // <-- AGORA FUNCIONA
        } else {
          await _firestoreService.updateClient(clientToSave);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cliente salvo com sucesso!'), backgroundColor: Colors.green)
          );
          Navigator.of(context).pop(clientToSave); 
        }
      } catch (e) {
        _showErrorSnackBar('Erro ao salvar cliente: $e');
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.client == null ? 'Novo Cliente' : 'Editar Cliente'),
        actions: [
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))
          else
            IconButton(icon: const Icon(Icons.save), onPressed: _submit, tooltip: 'Salvar')
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildSectionTitle('Dados Principais'),
            TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nome / Razão Social'), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _cnpjController, inputFormatters: [FilteringTextInputFormatter.digitsOnly, _CpfCnpjFormatter()], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'CPF / CNPJ')),
            const SizedBox(height: 12),
            TextFormField(controller: _ieController, decoration: const InputDecoration(labelText: 'IE / RG')),
            const SizedBox(height: 12),
            TextFormField(controller: _phoneController, inputFormatters: [_phoneMask], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone'), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
            const SizedBox(height: 12),
            TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            
            _buildSectionTitle('Endereço de Cobrança/Faturamento'),
            _buildAddressForm(_billingCepController, _billingStreetController, _billingNeighborhoodController, _billingCityController, _billingStateController),
            
            CheckboxListTile(
              title: const Text('Endereço de entrega é o mesmo da cobrança'),
              value: _deliverySameAsBilling,
              onChanged: (value) => setState(() => _deliverySameAsBilling = value ?? true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),

            if (!_deliverySameAsBilling) ...[
              _buildSectionTitle('Endereço de Entrega'),
              _buildAddressForm(_deliveryCepController, _deliveryStreetController, _deliveryNeighborhoodController, _deliveryCityController, _deliveryStateController),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24.0, bottom: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }
  
  Widget _buildAddressForm(TextEditingController cepCtrl, TextEditingController streetCtrl, TextEditingController neighborhoodCtrl, TextEditingController cityCtrl, TextEditingController stateCtrl) {
    return Column(
      children: [
        const SizedBox(height: 16),
        TextFormField(
          controller: cepCtrl, 
          inputFormatters: [_cepMask], 
          keyboardType: TextInputType.number, 
          decoration: InputDecoration(
            labelText: 'CEP', 
            suffixIcon: _isLoadingCep 
              ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3))) 
              : IconButton(icon: const Icon(Icons.search), onPressed: () => _fetchCep(cepCtrl, streetCtrl, neighborhoodCtrl, cityCtrl, stateCtrl))
          )
        ),
        const SizedBox(height: 12),
        TextFormField(controller: streetCtrl, decoration: const InputDecoration(labelText: 'Rua / Logradouro')),
        const SizedBox(height: 12),
        TextFormField(controller: neighborhoodCtrl, decoration: const InputDecoration(labelText: 'Bairro')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: TextFormField(controller: cityCtrl, decoration: const InputDecoration(labelText: 'Cidade'))),
            const SizedBox(width: 12),
            SizedBox(width: 80, child: TextFormField(controller: stateCtrl, decoration: const InputDecoration(labelText: 'UF'))),
          ],
        ),
      ],
    );
  }
}

// Formatador de CPF/CNPJ
class _CpfCnpjFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final digitsOnly = text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length > 14) return oldValue;
    String newText;
    if (digitsOnly.length <= 11) {
      newText = digitsOnly.replaceAllMapped(RegExp(r'(\d{3})(\d{3})(\d{3})(\d{2})'), (Match m) => '${m[1]}.${m[2]}.${m[3]}-${m[4]}');
    } else {
      newText = digitsOnly.replaceAllMapped(RegExp(r'(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})'), (Match m) => '${m[1]}.${m[2]}.${m[3]}/${m[4]}-${m[5]}');
    }
    return TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length));
  }
}