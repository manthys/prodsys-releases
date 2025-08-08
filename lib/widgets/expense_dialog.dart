// lib/widgets/expense_dialog.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense_model.dart';

class ExpenseDialog extends StatefulWidget {
  final Expense? expense;
  const ExpenseDialog({super.key, this.expense});

  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _descriptionController, _amountController;
  DateTime _selectedDate = DateTime.now();
  String _selectedCategory = 'Matéria-Prima';
  PlatformFile? _pickedFile;
  bool _isUploading = false;

  final List<String> _categories = ['Matéria-Prima', 'Mão de Obra', 'Aluguel', 'Alimentação', 'Energia', 'Água', 'Internet', 'Outros'];

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(text: widget.expense?.description ?? '');
    _amountController = TextEditingController(text: widget.expense?.amount.toString() ?? '');
    _selectedDate = widget.expense?.expenseDate.toDate() ?? DateTime.now();
    _selectedCategory = widget.expense?.category ?? 'Matéria-Prima';
  }

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }
  
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _pickedFile = result.files.first;
      });
    }
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      setState(() => _isUploading = true);

      String? attachmentUrl;
      if (_pickedFile != null) {
        try {
          final ref = FirebaseStorage.instance.ref('expense_receipts/${DateTime.now().toIso8601String()}_${_pickedFile!.name}');
          final uploadTask = await ref.putFile(File(_pickedFile!.path!));
          attachmentUrl = await uploadTask.ref.getDownloadURL();
        } catch (e) {
          setState(() => _isUploading = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro no upload: $e'), backgroundColor: Colors.red));
          return;
        }
      }

      final expense = Expense(
        id: widget.expense?.id,
        description: _descriptionController.text,
        amount: double.parse(_amountController.text.replaceAll(',', '.')),
        category: _selectedCategory,
        expenseDate: Timestamp.fromDate(_selectedDate),
        attachmentUrl: attachmentUrl ?? widget.expense?.attachmentUrl,
      );

      Navigator.of(context).pop(expense);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.expense == null ? 'Nova Despesa' : 'Editar Despesa'),
      content: _isUploading 
        ? const Center(child: CircularProgressIndicator()) 
        : Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(controller: _descriptionController, decoration: const InputDecoration(labelText: 'Descrição'), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
              TextFormField(controller: _amountController, decoration: const InputDecoration(labelText: 'Valor', prefixText: 'R\$ '), keyboardType: const TextInputType.numberWithOptions(decimal: true), inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+[,.]?\d{0,2}'))], validator: (v) => double.tryParse(v!.replaceAll(',', '.')) == null ? 'Inválido' : null),
              DropdownButtonFormField<String>(value: _selectedCategory, items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(), onChanged: (v) => setState(() => _selectedCategory = v!), decoration: const InputDecoration(labelText: 'Categoria')),
              ListTile(title: Text('Data: ${DateFormat('dd/MM/yyyy').format(_selectedDate)}'), trailing: const Icon(Icons.calendar_today), onTap: _pickDate),
              const SizedBox(height: 10),
              ElevatedButton.icon(icon: const Icon(Icons.attach_file), label: const Text('Anexar Comprovante'), onPressed: _pickFile),
              if (_pickedFile != null) Text('Arquivo: ${_pickedFile!.name}', style: const TextStyle(color: Colors.green))
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
}