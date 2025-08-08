// lib/widgets/mold_dialog.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/mold_model.dart';

class MoldDialog extends StatefulWidget {
  final Mold? mold;
  const MoldDialog({super.key, this.mold});

  @override
  _MoldDialogState createState() => _MoldDialogState();
}

class _MoldDialogState extends State<MoldDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.mold?.name ?? '');
    _quantityController = TextEditingController(text: widget.mold?.quantityAvailable.toString() ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      
      final mold = Mold(
        id: widget.mold?.id,
        name: _nameController.text,
        quantityAvailable: int.tryParse(_quantityController.text) ?? 0,
      );
      Navigator.of(context).pop(mold);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.mold == null ? 'Nova Forma' : 'Editar Forma'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome da Forma (Ex: T-50, P-40)'),
              validator: (value) => value!.isEmpty ? 'O nome é obrigatório' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _quantityController,
              decoration: const InputDecoration(labelText: 'Quantidade Disponível'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                if (value == null || value.isEmpty) return 'Quantidade é obrigatória';
                if (int.tryParse(value) == null) return 'Valor inválido';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        ElevatedButton(onPressed: _submit, child: const Text('Salvar')),
      ],
    );
  }
}