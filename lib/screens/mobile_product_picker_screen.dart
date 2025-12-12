// lib/screens/mobile_product_picker_screen.dart (NOVO ARQUIVO)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../services/firestore_service.dart';

class MobileProductPickerScreen extends StatefulWidget {
  const MobileProductPickerScreen({super.key});

  @override
  State<MobileProductPickerScreen> createState() => _MobileProductPickerScreenState();
}

class _MobileProductPickerScreenState extends State<MobileProductPickerScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  String _searchTerm = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchTerm = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecionar Produto'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou SKU...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                contentPadding: EdgeInsets.zero,
                suffixIcon: _searchTerm.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<List<Product>>(
        stream: _firestoreService.getProductsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Nenhum produto cadastrado.'));

          final filteredProducts = snapshot.data!.where((product) {
            final query = _searchTerm.toLowerCase();
            return product.name.toLowerCase().contains(query) || product.sku.toLowerCase().contains(query);
          }).toList();

          if (filteredProducts.isEmpty) {
            return const Center(child: Text('Nenhum produto encontrado.'));
          }

          return ListView.builder(
            itemCount: filteredProducts.length,
            itemBuilder: (context, index) {
              final product = filteredProducts[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ListTile(
                  title: Text(product.name),
                  subtitle: Text('SKU: ${product.sku} | Preço: ${currencyFormatter.format(product.basePrice)}'),
                  onTap: () {
                    // Retorna o produto selecionado para a tela anterior
                    Navigator.of(context).pop(product);
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}