// lib/screens/products_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
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

    return StreamBuilder<List<Product>>(
      stream: firestoreService.getProductsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Erro: ${snapshot.error}'));
        if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Nenhum produto cadastrado.'));

        final products = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            DataTable(
              columns: const [
                DataColumn(label: Text('Nome/Descrição', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('SKU', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Tipo de Forma', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Preço Base', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Adic. Logo', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Ações', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: products.map((product) {
                return DataRow(cells: [
                  DataCell(Text(product.name)),
                  DataCell(Text(product.sku)),
                  DataCell(Text(product.moldType)),
                  DataCell(Text(currencyFormatter.format(product.basePrice))),
                  DataCell(Text(currencyFormatter.format(product.clientLogoPrice))),
                  DataCell(Row(
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Editar', onPressed: () => showProductDialog(product: product)),
                    ],
                  )),
                ]);
              }).toList(),
            ),
          ],
        );
      },
    );
  }
}