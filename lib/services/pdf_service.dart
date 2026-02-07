// lib/services/pdf_service.dart

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order_model.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
// Import para buscar os pesos
import '../services/firestore_service.dart';

class PdfService {
  final FirestoreService _firestoreService = FirestoreService();

  Future<void> generateAndShowPdf(Order order, Client client, CompanySettings company) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      logoImage = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    } catch (e) {
      logoImage = null;
    }

    // --- CÁLCULO DE PESOS ---
    final molds = await _firestoreService.getMoldsStream().first;
    final products = await _firestoreService.getProductsStream().first;
    
    final moldWeights = {for (var m in molds) m.name: m.weight};
    final productWeights = <String, double>{};
    for (var p in products) {
       productWeights[p.id!] = moldWeights[p.moldType] ?? 0.0;
    }
    // ------------------------

    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
    
    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (pw.Context context) => _buildHeader(company, logoImage),
        footer: (pw.Context context) => _buildPageFooter(context),
        build: (pw.Context context) {
          return [
            _buildOrderTitle(order),
            pw.SizedBox(height: 15),
            _buildOrderDetailsSection(order),
            pw.SizedBox(height: 10),
            _buildPartyInfoSection(company, client),
            pw.SizedBox(height: 10),
            _buildDeliveryAddressSection(order),
            pw.SizedBox(height: 15),
            // Passamos o mapa de pesos
            _buildItemsTable(order, productWeights),
            _buildTotals(order, productWeights),
            pw.SizedBox(height: 30),
            _buildFooterInfo(order, company),
          ];
        },
      ),
    );
    
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  pw.Widget _buildHeader(CompanySettings company, pw.MemoryImage? logo) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null)
              pw.Image(logo, height: 50, width: 50),
            if (logo != null)
              pw.SizedBox(width: 20),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(company.companyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18)),
                pw.Text(company.address.street, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.Text('${company.address.city} - ${company.address.state}, CEP: ${company.address.cep}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.Text('CNPJ: ${company.cnpj} | Telefone: ${company.phone}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.Text('Email: ${company.email}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
          ]
        ),
      ]
    );
  }
  
  pw.Widget _buildSection({required String title, required pw.Widget child}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(4),
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          child: pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
        ),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300, width: 1)),
          child: child,
        )
      ]
    );
  }

  pw.Widget _buildKeyValueRow(String key, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 100,
            child: pw.Text('$key:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildOrderTitle(Order order) {
    return pw.Text('ORDEM DE COMPRA ${order.id?.substring(0,6).toUpperCase() ?? ''}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14));
  }

  pw.Widget _buildOrderDetailsSection(Order order) {
    final deliveryDateFormatted = order.deliveryDate != null ? DateFormat('dd/MM/yyyy').format(order.deliveryDate!.toDate()) : 'A definir';
    return _buildSection(
      title: 'DADOS DA ORDEM DE COMPRA',
      child: pw.Column(
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(children: [
                  _buildKeyValueRow('Data', DateFormat('dd/MM/yyyy').format(order.creationDate.toDate())),
                  _buildKeyValueRow('Cond. pgto.', order.paymentTerms ?? 'A combinar'),
                ])
              ),
              pw.Expanded(
                child: pw.Column(children: [
                  _buildKeyValueRow('Previsão da entrega', deliveryDateFormatted),
                  _buildKeyValueRow('Forma pgto.', order.paymentMethod),
                ])
              ),
            ]
          ),
          _buildKeyValueRow('Observação', order.notes ?? 'Sem observações.'),
        ]
      )
    );
  }

  pw.Widget _buildPartyInfoSection(CompanySettings company, Client client) {
    return pw.Column(
      children: [
        _buildSection(
          title: 'RESPONSÁVEL PELA COMPRA',
          child: pw.Column(children: [
              _buildKeyValueRow('Nome', client.name),
              _buildKeyValueRow('CPF/CNPJ', client.cnpj ?? 'N/A'),
              _buildKeyValueRow('Telefone', client.phone),
              _buildKeyValueRow('E-mail', client.email ?? 'N/A'),
          ])
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: _buildSection(
              title: 'DADOS DO FATURAMENTO',
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(client.name, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('${client.billingAddress.street}, ${client.billingAddress.neighborhood}', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('${client.billingAddress.city} - ${client.billingAddress.state}, CEP: ${client.billingAddress.cep}', style: const pw.TextStyle(fontSize: 9)),
                ]
              )
            )),
            pw.SizedBox(width: 10),
            pw.Expanded(child: _buildSection(
              title: 'DADOS DO FORNECEDOR',
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(company.companyName, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text('CNPJ: ${company.cnpj}', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('Tel: ${company.phone}', style: const pw.TextStyle(fontSize: 9)),
                  pw.Text('${company.address.street}, ${company.address.city}', style: const pw.TextStyle(fontSize: 9)),
                ]
              )
            )),
          ]
        ),
      ]
    );
  }
  
  pw.Widget _buildDeliveryAddressSection(Order order) {
    return _buildSection(
      title: 'ENDEREÇO DE ENTREGA',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('${order.deliveryAddress.street}, ${order.deliveryAddress.neighborhood}', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('${order.deliveryAddress.city} - ${order.deliveryAddress.state}, CEP: ${order.deliveryAddress.cep}', style: const pw.TextStyle(fontSize: 9)),
        ]
      )
    );
  }

  // Tabela atualizada com a coluna de Peso
  pw.Widget _buildItemsTable(Order order, Map<String, double> productWeights) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    // Adicionada coluna "Peso Un."
    final headers = ['N.', 'SKU', 'Item', 'Qtd.', 'Peso Un.', 'Unit. (R\$)', 'Total (R\$)'];
    
    final data = order.items.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final item = entry.value;
      
      final weight = productWeights[item.productId] ?? 0.0;
      final totalRowWeight = weight * item.quantity;
      final weightStr = weight > 0 ? '${totalRowWeight.toStringAsFixed(1)} kg' : '-';

      return [
        index.toString(), 
        item.sku, 
        item.productName, 
        '${item.quantity} Un.',
        weightStr, // Mostra o peso total da linha
        currencyFormatter.format(item.finalUnitPrice), 
        currencyFormatter.format(item.totalPrice)
      ];
    }).toList();
    
    return pw.TableHelper.fromTextArray(
      cellPadding: const pw.EdgeInsets.all(4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerCellDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft,
        3: pw.Alignment.center, 4: pw.Alignment.center, 5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight,
      },
      columnWidths: {
        0: const pw.FlexColumnWidth(0.5), 
        1: const pw.FlexColumnWidth(1), 
        2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(0.8), // Qtd
        4: const pw.FlexColumnWidth(1),   // Peso
        5: const pw.FlexColumnWidth(1.2), 
        6: const pw.FlexColumnWidth(1.2),
      },
      headers: headers,
      data: data,
    );
  }

  // Totais atualizados com Peso Total Estimado
  pw.Widget _buildTotals(Order order, Map<String, double> productWeights) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ');
    
    // Cálculo do peso total
    double totalWeight = 0.0;
    for(var item in order.items) {
      totalWeight += (item.quantity * (productWeights[item.productId] ?? 0.0));
    }

    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.SizedBox(
        width: 250,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Linha de Peso Total
            if (totalWeight > 0) ...[
               pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('Peso Total Estimado:'),
                pw.Text('${totalWeight.toStringAsFixed(1)} kg', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))
              ]),
              pw.Divider(color: PdfColors.grey400),
            ],
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Subtotal'),
              pw.Text(currencyFormatter.format(order.totalItemsAmount))
            ]),
            pw.Divider(color: PdfColors.grey400),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Frete'),
              pw.Text(currencyFormatter.format(order.shippingCost))
            ]),
            pw.Divider(color: PdfColors.grey400),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('Total', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.Text(currencyFormatter.format(order.finalAmount), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ]),
          ],
        ),
      ),
    );
  }

  pw.Widget _buildFooterInfo(Order order, CompanySettings company) {
      return _buildSection(
        title: 'INFORMAÇÕES ADICIONAIS',
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            _buildKeyValueRow('Termos de Pagamento', order.paymentTerms ?? company.defaultPaymentTerms),
            _buildKeyValueRow('Dados para Pagamento', company.paymentInfo),
          ]
        ),
      );
  }
 
  pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 20),
      padding: const pw.EdgeInsets.only(top: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 1)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Desenvolvido por Manthysr | Contato: cmanthysr@gmail.com', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
          pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey))
        ]
      )
    );
  }
}