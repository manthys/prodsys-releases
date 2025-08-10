// lib/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../models/address_model.dart';
import '../models/company_settings_model.dart';
import '../services/firestore_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  bool _isLoading = true;
  bool _isLoadingCep = false;

  late TextEditingController _companyNameController, _cnpjController, _phoneController, _emailController;
  late TextEditingController _cepController, _streetController, _neighborhoodController, _cityController, _stateController;
  late TextEditingController _paymentInfoController;
  late TextEditingController _paymentTermsController;

  final _cnpjMask = MaskTextInputFormatter(mask: '##.###.###/####-##', filter: {"#": RegExp(r'[0-9]')});
  final _phoneMask = MaskTextInputFormatter(mask: '(##) #####-####', filter: {"#": RegExp(r'[0-9]')});
  final _cepMask = MaskTextInputFormatter(mask: '#####-###', filter: {"#": RegExp(r'[0-9]')});

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadSettings();
  }

  void _initializeControllers() {
    _companyNameController = TextEditingController();
    _cnpjController = TextEditingController();
    _phoneController = TextEditingController();
    _emailController = TextEditingController();
    _cepController = TextEditingController();
    _streetController = TextEditingController();
    _neighborhoodController = TextEditingController();
    _cityController = TextEditingController();
    _stateController = TextEditingController();
    _paymentInfoController = TextEditingController();
    _paymentTermsController = TextEditingController();
  }

  @override
  void dispose() {
    _companyNameController.dispose();
    _cnpjController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _cepController.dispose();
    _streetController.dispose();
    _neighborhoodController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _paymentInfoController.dispose();
    _paymentTermsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await _firestoreService.getCompanySettings();
    _companyNameController.text = settings.companyName;
    _cnpjController.text = settings.cnpj;
    _phoneController.text = settings.phone;
    _emailController.text = settings.email;
    _cepController.text = settings.address.cep;
    _streetController.text = settings.address.street;
    _neighborhoodController.text = settings.address.neighborhood;
    _cityController.text = settings.address.city;
    _stateController.text = settings.address.state;
    _paymentInfoController.text = settings.paymentInfo;
    _paymentTermsController.text = settings.defaultPaymentTerms;

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchCep() async {
    final cep = _cepController.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (cep.length != 8) return;

    setState(() => _isLoadingCep = true);
    try {
      final response = await http.get(Uri.parse('https://viacep.com.br/ws/$cep/json/'));
      if (mounted && response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['erro'] != true) {
          _streetController.text = data['logradouro'];
          _neighborhoodController.text = data['bairro'];
          _cityController.text = data['localidade'];
          _stateController.text = data['uf'];
        } else {
          _showErrorSnackBar('CEP não encontrado.');
        }
      }
    } catch (e) {
      _showErrorSnackBar('Erro ao buscar CEP.');
    } finally {
      if(mounted) setState(() => _isLoadingCep = false);
    }
  }

  void _showErrorSnackBar(String message) {
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: Colors.red));
  }

  void _saveSettings() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      final settings = CompanySettings(
        companyName: _companyNameController.text,
        cnpj: _cnpjController.text,
        phone: _phoneController.text,
        email: _emailController.text,
        address: Address(
          cep: _cepController.text,
          street: _streetController.text,
          neighborhood: _neighborhoodController.text,
          city: _cityController.text,
          state: _stateController.text,
        ),
        paymentInfo: _paymentInfoController.text,
        defaultPaymentTerms: _paymentTermsController.text,
      );

      await _firestoreService.saveCompanySettings(settings);

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configurações salvas com sucesso!'), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Dados da Minha Empresa', style: Theme.of(context).textTheme.headlineSmall),
                    const Divider(height: 24),
                    TextFormField(controller: _companyNameController, decoration: const InputDecoration(labelText: 'Nome da Empresa / Razão Social', border: OutlineInputBorder())),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: TextFormField(controller: _cnpjController, inputFormatters: [_cnpjMask], keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'CNPJ', border: OutlineInputBorder()))),
                      const SizedBox(width: 16),
                      Expanded(child: TextFormField(controller: _phoneController, inputFormatters: [_phoneMask], keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Telefone', border: OutlineInputBorder()))),
                    ]),
                    const SizedBox(height: 16),
                    TextFormField(controller: _emailController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail de Contato', border: OutlineInputBorder())),
                    
                    const SizedBox(height: 24),
                    Text('Endereço da Empresa', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(height: 24),
                    Row(children: [
                      Expanded(child: TextFormField(controller: _cepController, inputFormatters: [_cepMask], keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'CEP', border: const OutlineInputBorder(), suffixIcon: _isLoadingCep ? const Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator(strokeWidth: 2)) : IconButton(icon: const Icon(Icons.search), onPressed: _fetchCep)))),
                      const SizedBox(width: 16),
                      Expanded(flex: 2, child: TextFormField(controller: _streetController, decoration: const InputDecoration(labelText: 'Rua / Logradouro', border: OutlineInputBorder()))),
                    ]),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: TextFormField(controller: _neighborhoodController, decoration: const InputDecoration(labelText: 'Bairro', border: OutlineInputBorder()))),
                      const SizedBox(width: 16),
                      Expanded(child: TextFormField(controller: _cityController, decoration: const InputDecoration(labelText: 'Cidade', border: OutlineInputBorder()))),
                       const SizedBox(width: 16),
                      SizedBox(width: 100, child: TextFormField(controller: _stateController, decoration: const InputDecoration(labelText: 'UF', border: OutlineInputBorder()))),
                    ]),
                    
                    const SizedBox(height: 24),
                    Text('Informações Financeiras', style: Theme.of(context).textTheme.titleLarge),
                    const Divider(height: 24),
                    
                    TextFormField(
                      controller: _paymentTermsController,
                      decoration: const InputDecoration(labelText: 'Termos de Pagamento Padrão', border: OutlineInputBorder(), hintText: 'Ex: 50% de entrada e 50% na entrega.'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _paymentInfoController,
                      decoration: const InputDecoration(labelText: 'Dados para Pagamento (Chave PIX, Banco, etc.)', border: OutlineInputBorder(), hintText: 'Ex: PIX (CNPJ): 12.345.678/0001-99\nBanco do Brasil, Ag: 1234, C/C: 56789-0'),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: _saveSettings,
              icon: const Icon(Icons.save),
              label: const Text('Salvar Alterações'),
            ),
          );
  }
}