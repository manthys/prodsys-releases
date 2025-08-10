// lib/screens/delivery_history_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/delivery_model.dart';
import '../models/order_model.dart';
import '../services/delivery_pdf_service.dart';
import '../services/firestore_service.dart';

class DeliveryHistoryScreen extends StatefulWidget {
  final Order order;
  final Client client;
  final CompanySettings companySettings;

  const DeliveryHistoryScreen({
    super.key,
    required this.order,
    required this.client,
    required this.companySettings,
  });

  @override
  State<DeliveryHistoryScreen> createState() => _DeliveryHistoryScreenState();
}

class _DeliveryHistoryScreenState extends State<DeliveryHistoryScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final DeliveryPdfService _deliveryPdfService = DeliveryPdfService();
  bool _isGeneratingPdf = false;

  void _generateDeliveryNotePdf(Delivery delivery) async {
    setState(() => _isGeneratingPdf = true);
    try {
      await _deliveryPdfService.generateAndShowPdf(delivery, widget.order, widget.client, widget.companySettings);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao gerar PDF: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  void _confirmDeliveryReceived(Delivery delivery) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Recebimento'),
        content: const Text('Isso marcará todos os itens desta entrega como "Entregue". Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmar')),
        ],
      ),
    );

    if (confirm == true) {
      await _firestoreService.confirmDeliveryAsCompleted(widget.order.id!, delivery.id!);
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrega confirmada com sucesso!'), backgroundColor: Colors.green));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Entregas do Pedido #${widget.order.id?.substring(0, 6).toUpperCase()}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isGeneratingPdf)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))
        ],
      ),
      body: StreamBuilder<List<Delivery>>(
        stream: _firestoreService.getDeliveriesForOrderStream(widget.order.id!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Nenhuma entrega registrada para este pedido.'));
          }

          final deliveries = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: deliveries.length,
            itemBuilder: (context, index) {
              final delivery = deliveries[index];
              final totalItems = delivery.items.map((e) => e.quantity).reduce((a, b) => a + b);
              final isDelivered = delivery.status == DeliveryStatus.entregue;

              return Card(
                color: isDelivered ? Colors.green.shade50 : null,
                child: ListTile(
                  leading: Icon(
                    isDelivered ? Icons.check_circle : Icons.local_shipping,
                    color: isDelivered ? Colors.green : Colors.blue,
                  ),
                  title: Text('Entrega de ${DateFormat('dd/MM/yyyy').format(delivery.deliveryDate.toDate())}'),
                  subtitle: Text('Motorista: ${delivery.driverName} | Itens: $totalItems\nStatus: ${isDelivered ? 'Entregue' : 'Em Trânsito'}'),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print_outlined),
                        tooltip: 'Imprimir Nota de Entrega',
                        onPressed: () => _generateDeliveryNotePdf(delivery),
                      ),
                      // Desabilita o botão se a entrega já foi confirmada
                      IconButton(
                        icon: Icon(
                          Icons.check_circle_outline,
                          color: isDelivered ? Colors.grey : Colors.green,
                        ),
                        tooltip: isDelivered ? 'Entrega já confirmada' : 'Confirmar Recebimento',
                        onPressed: isDelivered ? null : () => _confirmDeliveryReceived(delivery),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}