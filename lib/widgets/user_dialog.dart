// lib/widgets/user_dialog.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class UserDialog extends StatefulWidget {
  const UserDialog({super.key});

  @override
  _UserDialogState createState() => _UserDialogState();
}

class _UserDialogState extends State<UserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _nameController = TextEditingController(); // <-- NOVO CONTROLLER
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);
      
      final result = await _authService.createEmployeeUser(
        _emailController.text,
        _passwordController.text,
        _nameController.text, // <-- PASSANDO O NOME
      );

      if (mounted) {
        if (result == null) {
          Navigator.of(context).pop(true);
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo Funcionário'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CAMPO DE NOME ADICIONADO
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome do Funcionário'),
              validator: (v) => v!.isEmpty ? 'O nome é obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email do Funcionário'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v!.isEmpty ? 'O email é obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Senha Provisória'),
              obscureText: true,
              validator: (v) => v!.length < 6 ? 'A senha deve ter no mínimo 6 caracteres' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Salvar'),
        ),
      ],
    );
  }
}