// lib/services/delivery_pdf_service.dart

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order_model.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/delivery_model.dart';

class DeliveryPdfService {
  Future<void> generateAndShowPdf(Delivery delivery, Order order, Client client, CompanySettings company) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      logoImage = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    } catch (e) {
      logoImage = null;
    }

    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
    
    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildHeader(company, logoImage),
              pw.SizedBox(height: 10),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 10),
              _buildDeliveryTitle(delivery),
              pw.SizedBox(height: 20),
              _buildPartyInfoSection(client, order, delivery),
              pw.SizedBox(height: 15),
              _buildItemsTable(delivery),
              pw.Spacer(),
              _buildSignatureSection(),
              _buildPageFooter(context),
            ],
          );
        },
      ),
    );
    
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // ===== CABEÇALHO CORRIGIDO E COMPLETO =====
  pw.Widget _buildHeader(CompanySettings company, pw.MemoryImage? logo) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
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
        pw.Text('Página 1/1', style: const pw.TextStyle(fontSize: 9)),
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
            width: 80,
            child: pw.Text('$key:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildDeliveryTitle(Delivery delivery) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('NOTA DE ENTREGA', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
        pw.Text('Data: ${DateFormat('dd/MM/yyyy').format(delivery.deliveryDate.toDate())}', style: const pw.TextStyle(fontSize: 9)),
      ]
    );
  }

  pw.Widget _buildPartyInfoSection(Client client, Order order, Delivery delivery) {
    return _buildSection(
      title: 'DADOS DA ENTREGA',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildKeyValueRow('Cliente', client.name),
                    _buildKeyValueRow('CNPJ/CPF', client.cnpj ?? 'N/A'),
                    _buildKeyValueRow('Telefone', client.phone),
                    _buildKeyValueRow('Pedido N°', order.id?.substring(0, 6).toUpperCase() ?? 'N/A'),
                  ]
                )
              ),
              pw.SizedBox(width: 20),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Endereço de Entrega:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text('${order.deliveryAddress.street}, ${order.deliveryAddress.neighborhood}'),
                    pw.Text('${order.deliveryAddress.city} - ${order.deliveryAddress.state}, CEP: ${order.deliveryAddress.cep}'),
                  ]
                )
              )
            ]
          ),
          pw.Divider(height: 15, color: PdfColors.grey300),
          _buildKeyValueRow('Motorista', delivery.driverName),
          _buildKeyValueRow('Veículo', delivery.vehiclePlate.isNotEmpty ? delivery.vehiclePlate : 'N/A'),
          if (order.notes != null && order.notes!.isNotEmpty)
            _buildKeyValueRow('Observações', order.notes!),
        ]
      )
    );
  }
  
  pw.Widget _buildItemsTable(Delivery delivery) {
    final headers = ['N.', 'SKU', 'Item', 'Qtd.'];
    final data = delivery.items.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final item = entry.value;
      return [
        index.toString(),
        item.sku,
        item.productName,
        '${item.quantity} Unidades',
      ];
    }).toList();
    
    return pw.TableHelper.fromTextArray(
      cellPadding: const pw.EdgeInsets.all(4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerCellDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.centerLeft, 3: pw.Alignment.center,
      },
      headers: headers,
      data: data,
    );
  }

  pw.Widget _buildSignatureSection() {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 50),
      child: pw.Column(
        children: [
          pw.Divider(color: PdfColors.black, height: 10),
          pw.SizedBox(height: 5),
          pw.Text('Assinatura do Recebedor', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 10),
          pw.Text('Nome Legível: _________________________________________', style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 10),
          pw.Text('RG/CPF: _____________________________________________', style: const pw.TextStyle(fontSize: 9)),
        ]
      )
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