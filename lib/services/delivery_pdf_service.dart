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
// Import necessário para buscar os pesos no banco
import '../services/firestore_service.dart';

class DeliveryPdfService {
  final FirestoreService _firestoreService = FirestoreService();

  Future<void> generateAndShowPdf(Delivery delivery, Order order, Client client, CompanySettings company) async {
    final pdf = pw.Document();

    pw.MemoryImage? logoImage;
    try {
      logoImage = pw.MemoryImage((await rootBundle.load('assets/logo.png')).buffer.asUint8List());
    } catch (e) {
      logoImage = null;
    }

    // --- CÁLCULO DE PESOS (NOVO) ---
    // Busca formas e produtos para cruzar os dados de peso
    final molds = await _firestoreService.getMoldsStream().first;
    final products = await _firestoreService.getProductsStream().first;
    
    // Cria mapa: Nome da Forma -> Peso
    final moldWeights = {for (var m in molds) m.name: m.weight};
    
    // Cria mapa: ID do Produto -> Peso Unitário
    final productWeights = <String, double>{};
    for (var p in products) {
       productWeights[p.id!] = moldWeights[p.moldType] ?? 0.0;
    }
    
    // Calcula o peso total desta entrega específica
    double deliveryTotalWeight = 0.0;
    for(var item in delivery.items) {
       double weight = productWeights[item.productId] ?? 0.0;
       deliveryTotalWeight += (item.quantity * weight);
    }
    // -------------------------------

    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);
    
    pdf.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        // Passamos o peso total para o cabeçalho
        header: (pw.Context context) => _buildHeader(company, delivery, logoImage, deliveryTotalWeight),
        footer: (pw.Context context) => _buildPageFooter(context),
        build: (pw.Context context) {
          return [
            _buildPartyInfoSection(client, order, delivery),
            pw.SizedBox(height: 15),
            // Passamos o mapa de pesos para a tabela
            _buildItemsTable(delivery, productWeights),
            pw.Spacer(),
            _buildSignatureSection(delivery.type),
          ];
        },
      ),
    );
    
    // Define o nome do arquivo para facilitar ao salvar
    final fileName = 'Entrega_${client.name.replaceAll(' ', '_')}_${DateFormat('ddMMyy').format(DateTime.now())}.pdf';

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: fileName,
    );
  }

  // Header atualizado com Peso Total
  pw.Widget _buildHeader(CompanySettings company, Delivery delivery, pw.MemoryImage? logo, double totalWeight) {
    final String title = delivery.type == DeliveryType.devolucao 
        ? 'COMPROVANTE DE DEVOLUÇÃO' 
        : 'NOTA DE ENTREGA';
        
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) pw.Image(logo, height: 50, width: 50),
            if (logo != null) pw.SizedBox(width: 20),
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
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14, color: delivery.type == DeliveryType.devolucao ? PdfColors.red : PdfColors.black)),
            pw.Text('Data: ${DateFormat('dd/MM/yyyy HH:mm').format(delivery.deliveryDate.toDate())}', style: const pw.TextStyle(fontSize: 9)), 
            
            // AQUI ESTÁ A INFORMAÇÃO DO PESO TOTAL NO CABEÇALHO
            if (totalWeight > 0)
               pw.Text('Carga Total: ${totalWeight.toStringAsFixed(1)} kg', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          ]
        )
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

  // Tabela atualizada com a coluna de Peso Unitário e Total por linha
  pw.Widget _buildItemsTable(Delivery delivery, Map<String, double> productWeights) {
    final isReturn = delivery.type == DeliveryType.devolucao;
    
    // Adicionada coluna "Peso (kg)"
    final List<String> headers = isReturn 
        ? ['N.', 'SKU', 'Qtd Devolvida', 'Peso (kg)', 'Item', 'Motivo da Devolução']
        : ['N.', 'SKU', 'Qtd.', 'Peso (kg)', 'Item', 'Env.', 'Dev.', 'Ent.', 'Motivo/Obs'];

    bool hasImmediateRefusal = !isReturn && delivery.items.any((i) => i.returnQuantity > 0);
    
    final List<String> finalHeaders = (isReturn || hasImmediateRefusal) 
        ? headers 
        : ['N.', 'SKU', 'Qtd.', 'Peso (kg)', 'Item']; 

    final data = delivery.items.asMap().entries.map((entry) {
      final index = entry.key + 1;
      final item = entry.value;
      
      // Busca o peso unitário
      final weight = productWeights[item.productId] ?? 0.0;
      // Calcula o peso da linha (Peso Unit * Quantidade)
      final totalRowWeight = weight * item.quantity;
      final weightStr = weight > 0 ? '${totalRowWeight.toStringAsFixed(1)}' : '-';

      if (isReturn) {
        // Documento de DEVOLUÇÃO
        return [
          index.toString(),
          item.sku,
          item.quantity.toString(), // Na devolução, quantity é o que voltou
          weightStr,
          item.productName,
          item.returnReason?.replaceAll(' | ', '\n') ?? '-'
        ];
      } else if (hasImmediateRefusal) {
        // Documento de SAÍDA com Recusa Imediata
        final accepted = item.quantity - item.returnQuantity;
        return [
          index.toString(),
          item.sku,
          '-', // Coluna Qtd Geral fica vazia
          weightStr,
          item.productName,
          item.quantity.toString(),
          item.returnQuantity > 0 ? item.returnQuantity.toString() : '-',
          accepted.toString(),
          item.returnReason?.replaceAll(' | ', '\n') ?? '-'
        ];
      } else {
        // Documento de SAÍDA Limpa (Padrão)
        return [
          index.toString(),
          item.sku,
          '${item.quantity} Un.',
          weightStr,
          item.productName,
        ];
      }
    }).toList();
    
    // Definição das larguras das colunas (Ajustado para caber o Peso)
    Map<int, pw.TableColumnWidth> columnWidths;
    Map<int, pw.Alignment> cellAlignments;

    if (isReturn) {
        columnWidths = {
            0: const pw.FixedColumnWidth(20), 
            1: const pw.FixedColumnWidth(50), 
            2: const pw.FixedColumnWidth(60),
            3: const pw.FixedColumnWidth(40), // Peso
            4: const pw.FlexColumnWidth(2), 
            5: const pw.FlexColumnWidth(1.5)
        };
        cellAlignments = {
            0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.center,
            3: pw.Alignment.center, 4: pw.Alignment.centerLeft, 5: pw.Alignment.centerLeft
        };
    } else if (hasImmediateRefusal) {
        columnWidths = {
            0: const pw.FixedColumnWidth(20), 1: const pw.FixedColumnWidth(50), 2: const pw.FixedColumnWidth(25), 
            3: const pw.FixedColumnWidth(35), // Peso
            4: const pw.FlexColumnWidth(2), 
            5: const pw.FixedColumnWidth(25), 
            6: const pw.FixedColumnWidth(25), 
            7: const pw.FixedColumnWidth(25), 
            8: const pw.FlexColumnWidth(1.5)
        };
        cellAlignments = {
            0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.center,
            3: pw.Alignment.center, 4: pw.Alignment.centerLeft, 5: pw.Alignment.center, 
            6: pw.Alignment.center, 7: pw.Alignment.center, 8: pw.Alignment.centerLeft
        };
    } else {
        // Padrão
        columnWidths = {
            0: const pw.FixedColumnWidth(25), 
            1: const pw.FlexColumnWidth(1.5), 
            2: const pw.FixedColumnWidth(40), // Qtd
            3: const pw.FixedColumnWidth(50), // Peso
            4: const pw.FlexColumnWidth(3.0)  
        };
        cellAlignments = {
            0: pw.Alignment.center, 1: pw.Alignment.centerLeft, 2: pw.Alignment.center, 3: pw.Alignment.center, 4: pw.Alignment.centerLeft
        };
    }

    return pw.TableHelper.fromTextArray(
      cellPadding: const pw.EdgeInsets.all(4),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
      headerCellDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
      cellStyle: const pw.TextStyle(fontSize: 8),
      cellAlignments: cellAlignments,
      columnWidths: columnWidths,
      headers: finalHeaders,
      data: data,
    );
  }

  pw.Widget _buildSignatureSection(DeliveryType type) {
    final label = type == DeliveryType.devolucao 
        ? 'Assinatura do Responsável (Recebimento da Devolução)'
        : 'Assinatura do Recebedor (Cliente)';
        
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 50),
      child: pw.Column(
        children: [
          pw.Divider(color: PdfColors.black, height: 10),
          pw.SizedBox(height: 5),
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
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