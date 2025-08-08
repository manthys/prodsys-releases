// lib/services/pdf_service.dart

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order_model.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';

class PdfService {
  Future<void> generateAndShowPdf(Order order, Client client, CompanySettings company) async {
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
              // SEÇÃO 1: CABEÇALHO (Logo e dados da empresa)
              _buildHeader(company, logoImage),
              pw.SizedBox(height: 10),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 10),
              
              // SEÇÃO 2: TÍTULO DO PEDIDO
              _buildOrderTitle(order),
              pw.SizedBox(height: 15),

              // SEÇÃO 3: DADOS DA ORDEM DE COMPRA
              _buildOrderDetailsSection(order),
              pw.SizedBox(height: 10),
              
              // SEÇÃO 4, 5, 6 e 7 (AGRUPADAS)
              _buildPartyInfoSection(company, client, order),
              pw.SizedBox(height: 15),
              
              // SEÇÃO 8: ITENS
              _buildItemsTable(order),
              _buildTotals(order),
              
              // O Spacer garante que o rodapé fique no final
              pw.Spacer(), 
              
              _buildPageFooter(context),
            ],
          );
        },
      ),
    );
    
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // ===== WIDGETS DE CONSTRUÇÃO DO PDF REVISADOS E CORRIGIDOS =====

  // 1. CABEÇALHO
  pw.Widget _buildHeader(CompanySettings company, pw.MemoryImage? logo) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) pw.Image(logo, height: 50, width: 50),
            if (logo != null) pw.SizedBox(width: 15),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(company.companyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                pw.Text('${company.address.street}, ${company.address.cep}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.Text(company.email ?? '', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                pw.Text('CNPJ: ${company.cnpj} | Telefone: ${company.phone}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
              ],
            ),
          ]
        ),
        pw.Text('Página 1/1', style: const pw.TextStyle(fontSize: 9)),
      ],
    );
  }

  // 2. TÍTULO
  pw.Widget _buildOrderTitle(Order order) {
    return pw.Text('ORDEM DE COMPRA ${order.id?.substring(0,6).toUpperCase() ?? ''}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14));
  }
  
  // FUNÇÃO AUXILIAR PARA CRIAR SEÇÕES
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

  // FUNÇÃO AUXILIAR PARA LINHAS CHAVE-VALOR
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

  // 3. DADOS DA ORDEM DE COMPRA
  pw.Widget _buildOrderDetailsSection(Order order) {
    final deliveryDateFormatted = order.deliveryDate != null ? DateFormat('dd/MM/yyyy').format(order.deliveryDate!.toDate()) : 'A definir';
    return _buildSection(
      title: 'DADOS DA ORDEM DE COMPRA',
      child: pw.Column(
        children: [
           pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: pw.Column(children: [
                _buildKeyValueRow('Data', DateFormat('dd/MM/yyyy').format(order.creationDate.toDate())),
                _buildKeyValueRow('Cond. pgto.', order.paymentTerms ?? 'A combinar'),
              ])),
              pw.Expanded(child: pw.Column(children: [
                _buildKeyValueRow('Previsão da entrega', deliveryDateFormatted),
                _buildKeyValueRow('Forma pgto.', order.paymentMethod),
              ])),
            ]
          ),
          _buildKeyValueRow('Observação', order.notes ?? 'Sem observações.'),
        ]
      )
    );
  }

  // 4, 5, 6, 7. AGRUPAMENTO DE INFORMAÇÕES
  pw.Widget _buildPartyInfoSection(CompanySettings company, Client client, Order order) {
    return pw.Column(
      children: [
        _buildSection(
          title: 'RESPONSÁVEL PELA COMPRA',
          child: pw.Column(children: [
              _buildKeyValueRow('Nome', client.name),
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
        pw.SizedBox(height: 10),
        _buildSection(
          title: 'ENDEREÇO DE ENTREGA',
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('${order.deliveryAddress.street}, ${order.deliveryAddress.neighborhood}', style: const pw.TextStyle(fontSize: 9)),
              pw.Text('${order.deliveryAddress.city} - ${order.deliveryAddress.state}, CEP: ${order.deliveryAddress.cep}', style: const pw.TextStyle(fontSize: 9)),
            ]
          )
        ),
      ]
    );
  }

  // 8. ITENS
  pw.Widget _buildItemsTable(Order order) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return pw.TableHelper.fromTextArray(
      cellPadding: const pw.EdgeInsets.all(4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerCellDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 9),
      cellAlignments: {
        0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.center, 3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight
      },
      headers: ['N.', 'Item', 'Qtd.', 'Unit. (R\$)', 'Total (R\$)'],
      data: order.items.asMap().entries.map((entry) {
        final index = entry.key + 1;
        final item = entry.value;
        return [
          index.toString(), item.productName, '${item.quantity} Unidades',
          currencyFormatter.format(item.finalUnitPrice), currencyFormatter.format(item.totalPrice)
        ];
      }).toList(),
    );
  }

  // 9. TOTAIS
  pw.Widget _buildTotals(Order order) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$ ');
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 10),
      child: pw.SizedBox(
        width: 250,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Subtotal'), pw.Text(currencyFormatter.format(order.totalItemsAmount))]),
            pw.Divider(color: PdfColors.grey400),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Frete'), pw.Text(currencyFormatter.format(order.shippingCost))]),
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
 
  // 10. RODAPÉ
  pw.Widget _buildPageFooter(pw.Context context) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Desenvolvido por Manthysr', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
        pw.Text('Página ${context.pageNumber} de ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
      ]
    );
  }
}