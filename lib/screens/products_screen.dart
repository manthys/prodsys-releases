// lib/screens/products_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/price_variation_model.dart';
import '../services/firestore_service.dart';
import '../widgets/product_dialog.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    void showProductDialog({Product? product}) async {
      final result = await showDialog<Product>(context: context, builder: (context) => ProductDialog(product: product));
      if (result != null) {
        if (product == null) {
          await firestoreService.addProduct(result);
        } else {
          await firestoreService.updateProduct(result);
        }
      }
    }

    // ##### NOVA FUNÇÃO PARA CONFIRMAR E EXECUTAR A EXCLUSÃO #####
    void _confirmDelete(BuildContext context, Product product) async {
      final bool? confirm = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza que deseja excluir o produto "${product.name}"?\n\nEsta ação não pode ser desfeita.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Sim, Excluir'),
            ),
          ],
        ),
      );

      if (confirm == true && context.mounted) {
        try {
          await firestoreService.deleteProduct(product.id!);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Produto excluído com sucesso!'), backgroundColor: Colors.green),
          );
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao excluir: ${e.toString().replaceAll("Exception: ", "")}'), backgroundColor: Colors.red),
          );
        }
      }
    }

    PriceVariation findPrice(Product product, String description) {
      return product.priceVariations.firstWhere(
        (v) => v.description == description,
        orElse: () => PriceVariation(description: description, price: 0.0),
      );
    }

    return Scaffold(
      body: StreamBuilder<List<Product>>(
        stream: firestoreService.getProductsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Nenhum produto cadastrado.'));

          final products = snapshot.data!;
          
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Nome/Descrição', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Tipo de Forma', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Preço S/ Nota', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('Preço C/ Nota', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('Adic. Logo', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: products.map((product) {
                  final priceWithoutNota = findPrice(product, 'Sem Nota');
                  final priceWithNota = findPrice(product, 'Com Nota');

                  return DataRow(cells: [
                    DataCell(Text(product.name)),
                    DataCell(Text(product.sku)),
                    DataCell(Text(product.moldType)),
                    DataCell(Text(currencyFormatter.format(priceWithoutNota.price))),
                    DataCell(Text(currencyFormatter.format(priceWithNota.price))),
                    DataCell(Text(currencyFormatter.format(product.clientLogoPrice))),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Editar', onPressed: () => showProductDialog(product: product)),
                        // ##### NOVO BOTÃO DE EXCLUIR #####
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          tooltip: 'Excluir',
                          onPressed: () => _confirmDelete(context, product),
                        ),
                      ],
                    )),
                  ]);
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}