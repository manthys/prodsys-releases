// lib/screens/products_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/price_variation_model.dart'; // Importe o modelo de variação
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

    // Função auxiliar para encontrar um preço específico
    PriceVariation _findPrice(Product product, String description) {
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
                  // ##### COLUNAS DE PREÇO ATUALIZADAS #####
                  DataColumn(label: Text('Preço S/ Nota', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('Preço C/ Nota', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('Adic. Logo', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                  DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: products.map((product) {
                  // Encontra os preços para exibição
                  final priceWithoutNota = _findPrice(product, 'Sem Nota');
                  final priceWithNota = _findPrice(product, 'Com Nota');

                  return DataRow(cells: [
                    DataCell(Text(product.name)),
                    DataCell(Text(product.sku)),
                    DataCell(Text(product.moldType)),
                    // ##### CÉLULAS DE PREÇO ATUALIZADAS #####
                    DataCell(Text(currencyFormatter.format(priceWithoutNota.price))),
                    DataCell(Text(currencyFormatter.format(priceWithNota.price))),
                    DataCell(Text(currencyFormatter.format(product.clientLogoPrice))),
                    DataCell(Row(
                      children: [
                        IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Editar', onPressed: () => showProductDialog(product: product)),
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