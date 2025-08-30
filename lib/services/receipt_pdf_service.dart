// lib/services/receipt_pdf_service.dart

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order_model.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';

class ReceiptPdfService {
  Future<void> generateAndShowPdf(Order order, Client client, CompanySettings company, {String? recipientName}) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final theme = pw.ThemeData.withFont(base: font, bold: boldFont);

    pw.MemoryImage? logoImage;
    try {
      final byteData = await rootBundle.load('assets/logo.png');
      logoImage = pw.MemoryImage(byteData.buffer.asUint8List());
    } catch (e) {
      print("Aviso: Arquivo 'assets/logo.png' não encontrado. O recibo será gerado sem o logo.");
      logoImage = null;
    }

    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    
    final valueInWords = NumeroPorExtenso.escrever(order.finalAmount);
    
    final nameOnReceipt = recipientName ?? client.name;

    pdf.addPage(
      pw.Page(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 50, vertical: 40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(children: [
                    if (logoImage != null) pw.Image(logoImage, height: 60),
                    if (logoImage != null) pw.SizedBox(width: 20),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(company.companyName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                        pw.Text(company.address.street, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('${company.address.city} - ${company.address.state}, CEP: ${company.address.cep}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('CNPJ: ${company.cnpj}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('Telefone: ${company.phone}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                        pw.Text('Email: ${company.email}', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                      ],
                    ),
                  ]),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('RECIBO', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 22)),
                      pw.SizedBox(height: 8),
                      pw.Text(currencyFormatter.format(order.finalAmount), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18, color: PdfColors.blue)),
                    ]
                  ),
                ],
              ),
              pw.Divider(height: 30, thickness: 2),
              pw.SizedBox(height: 30),
              
              pw.RichText(
                text: pw.TextSpan(
                  style: const pw.TextStyle(fontSize: 12, height: 1.5),
                  children: [
                    const pw.TextSpan(text: 'Recebemos de '),
                    pw.TextSpan(
                      text: client.cnpj != null && client.cnpj!.isNotEmpty 
                          ? '${nameOnReceipt.toUpperCase()} (CNPJ/CPF: ${client.cnpj})' 
                          : nameOnReceipt.toUpperCase(), 
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)
                    ),
                    const pw.TextSpan(text: ', a importância de '),
                    pw.TextSpan(text: '${currencyFormatter.format(order.finalAmount)} ($valueInWords)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    const pw.TextSpan(text: ', referente ao pagamento integral do pedido de número '),
                    pw.TextSpan(text: '#${order.id?.substring(0,6).toUpperCase() ?? ''}.', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ]
                )
              ),
              pw.SizedBox(height: 50),
              
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${company.address.city}, ${DateFormat("d 'de' MMMM 'de' yyyy", 'pt_BR').format(DateTime.now())}.',
                  style: const pw.TextStyle(fontSize: 12)
                )
              ),
              pw.SizedBox(height: 80),

              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                    pw.Container(
                      width: 250,
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black))),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(company.companyName, style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('CNPJ: ${company.cnpj}', style: const pw.TextStyle(fontSize: 10)),
                  ]
                )
              ),
              pw.Spacer(),

              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                      pw.Text('Este recibo comprova o pagamento integral do pedido especificado.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
                      pw.SizedBox(height: 10),
                      pw.Text('Desenvolvido por Manthysr | Contato: cmanthysr@gmail.com', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
                    ]
                )
              )
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}

class NumeroPorExtenso {
  static const _unidades = [
    '', 'um', 'dois', 'três', 'quatro', 'cinco', 'seis', 'sete', 'oito', 'nove',
    'dez', 'onze', 'doze', 'treze', 'catorze', 'quinze', 'dezesseis', 'dezessete', 'dezoito', 'dezenove'
  ];
  static const _dezenas = ['', '', 'vinte', 'trinta', 'quarenta', 'cinquenta', 'sessenta', 'setenta', 'oitenta', 'noventa'];
  static const _centenas = ['', 'cento', 'duzentos', 'trezentos', 'quatrocentos', 'quinhentos', 'seiscentos', 'setecentos', 'oitocentos', 'novecentos'];

  static String escrever(double valor) {
    if (valor == 0) return 'zero reais';

    int reais = valor.truncate();
    int centavos = ((valor - reais) * 100).round();

    String extensoReais = '';
    if (reais > 0) {
      extensoReais = _converterInteiro(reais);
      if (reais == 1) {
        extensoReais += ' real';
      } else {
        extensoReais += ' reais';
      }
    }

    String extensoCentavos = '';
    if (centavos > 0) {
      extensoCentavos = _converterInteiro(centavos);
      if (centavos == 1) {
        extensoCentavos += ' centavo';
      } else {
        extensoCentavos += ' centavos';
      }
    }

    if (reais > 0 && centavos > 0) {
      return '$extensoReais e $extensoCentavos';
    } else if (reais > 0) {
      return extensoReais;
    } else {
      return extensoCentavos;
    }
  }

  static String _converterInteiro(int n) {
    if (n < 0) return '';
    if (n < 20) return _unidades[n];
    if (n < 100) {
      return _dezenas[n ~/ 10] + ((n % 10 > 0) ? ' e ${_unidades[n % 10]}' : '');
    }
    if (n < 1000) {
      if (n == 100) return 'cem';
      return _centenas[n ~/ 100] + ((n % 100 > 0) ? ' e ${_converterInteiro(n % 100)}' : '');
    }
    if (n < 1000000) {
      String milhar = _converterInteiro(n ~/ 1000);
      if (n ~/ 1000 == 1) {
        milhar = 'mil';
      } else {
        milhar += ' mil';
      }
      
      if (n % 1000 == 0) return milhar;
      if (n % 1000 < 100 || n % 100 == 0) {
        return '$milhar e ${_converterInteiro(n % 1000)}';
      }
      return '$milhar, ${_converterInteiro(n % 1000)}';
    }
    return n.toString();
  }
}