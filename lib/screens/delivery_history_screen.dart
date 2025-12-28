// lib/screens/delivery_history_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart'; 
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/delivery_model.dart';
import '../models/order_model.dart';
import '../services/delivery_pdf_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';

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
  final AuthService _authService = AuthService();
  bool _isGeneratingPdf = false;
  bool _isProcessing = false;

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

  // =================================================================
  // 1. CONFIRMAÇÃO DE ENTREGA (No ato da entrega pelo motorista)
  // =================================================================
  void _confirmDeliveryReceived(Delivery delivery) async {
    final Map<int, int> returnsMap = {};
    final Map<int, TextEditingController> reasonsControllers = {};

    for (int i = 0; i < delivery.items.length; i++) {
      returnsMap[i] = 0; 
      reasonsControllers[i] = TextEditingController();
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Confirmar Entrega'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Verifique os itens abaixo. Se algo voltou (recusa imediata), ajuste a quantidade "Devolvido".',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      ...List.generate(delivery.items.length, (index) {
                        final item = delivery.items[index];
                        final returnedQty = returnsMap[index] ?? 0;
                        final deliveredQty = item.quantity - returnedQty;

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      // ADICIONADO SKU AQUI
                                      Text('SKU: ${item.sku}', style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                                      Text('Enviado: ${item.quantity}', style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    children: [
                                      const Text('Devolvido', style: TextStyle(fontSize: 10)),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: returnedQty > 0 
                                              ? () => setStateDialog(() => returnsMap[index] = returnedQty - 1)
                                              : null,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Text('$returnedQty', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.red),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: returnedQty < item.quantity
                                              ? () => setStateDialog(() => returnsMap[index] = returnedQty + 1)
                                              : null,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (returnedQty > 0) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                                child: TextField(
                                  controller: reasonsControllers[index],
                                  decoration: const InputDecoration(
                                    labelText: 'Motivo da Devolução (Obrigatório)',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                              Text(
                                'Serão entregues: $deliveredQty | Retornam: $returnedQty',
                                style: TextStyle(fontSize: 12, color: Colors.orange.shade800, fontStyle: FontStyle.italic),
                              ),
                            ],
                            const Divider(),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
                ElevatedButton(
                  onPressed: () {
                    bool valid = true;
                    for (int i = 0; i < delivery.items.length; i++) {
                      if ((returnsMap[i] ?? 0) > 0 && reasonsControllers[i]!.text.isEmpty) {
                        valid = false;
                        break;
                      }
                    }
                    if (!valid) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Por favor, informe o motivo para os itens devolvidos.'), backgroundColor: Colors.red));
                    } else {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: const Text('Confirmar Finalização'),
                ),
              ],
            );
          }
        );
      },
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      try {
        List<DeliveryItem> finalItemsState = [];
        for (int i = 0; i < delivery.items.length; i++) {
          final originalItem = delivery.items[i];
          final qtyReturned = returnsMap[i] ?? 0;
          final reason = reasonsControllers[i]?.text;
          
          finalItemsState.add(DeliveryItem(
            productId: originalItem.productId,
            sku: originalItem.sku,
            productName: originalItem.productName,
            quantity: originalItem.quantity, 
            logoType: originalItem.logoType,
            returnQuantity: qtyReturned, 
            returnReason: reason, 
          ));
        }

        await _firestoreService.confirmDeliveryWithReturns(
          orderId: widget.order.id!,
          deliveryId: delivery.id!,
          itemsWithStatus: finalItemsState
        );

        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrega confirmada e estoque atualizado!'), backgroundColor: Colors.green));
        }
      } catch (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao confirmar entrega: $e'), backgroundColor: Colors.red));
      } finally {
        if(mounted) setState(() => _isProcessing = false);
      }
    }
  }

  // =================================================================
  // 2. DEVOLUÇÃO PÓS-ENTREGA (Cliente volta dias depois)
  // =================================================================
  void _registerPostDeliveryReturn(Delivery originalDelivery) async {
    final Map<int, int> returnsMap = {};
    final Map<int, TextEditingController> reasonsControllers = {};

    for (int i = 0; i < originalDelivery.items.length; i++) {
      returnsMap[i] = 0;
      reasonsControllers[i] = TextEditingController();
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Nova Devolução (Pós-Entrega)'),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.only(bottom: 16),
                        color: Colors.orange.shade50,
                        child: const Text(
                          'Isso gerará um NOVO comprovante de devolução com a data de hoje.',
                          style: TextStyle(fontSize: 12, color: Colors.deepOrange),
                        ),
                      ),
                      ...List.generate(originalDelivery.items.length, (index) {
                        final item = originalDelivery.items[index];
                        final acceptedQty = item.quantity - item.returnQuantity;
                        final returningNow = returnsMap[index] ?? 0;

                        if (acceptedQty <= 0) return const SizedBox.shrink();

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      // ADICIONADO SKU AQUI TAMBÉM
                                      Text('SKU: ${item.sku}', style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500)),
                                      Text('Qtd nesta nota: $acceptedQty', style: const TextStyle(fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    children: [
                                      const Text('Devolver', style: TextStyle(fontSize: 10)),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.remove_circle_outline, size: 20),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: returningNow > 0 
                                              ? () => setStateDialog(() => returnsMap[index] = returningNow - 1)
                                              : null,
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8.0),
                                            child: Text('$returningNow', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.blue),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: returningNow < acceptedQty
                                              ? () => setStateDialog(() => returnsMap[index] = returningNow + 1)
                                              : null,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (returningNow > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                                child: TextField(
                                  controller: reasonsControllers[index],
                                  decoration: const InputDecoration(
                                    labelText: 'Motivo da Devolução',
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            const Divider(),
                          ],
                        );
                      }),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                  onPressed: () {
                    bool hasItems = false;
                    for (int i = 0; i < originalDelivery.items.length; i++) {
                      if ((returnsMap[i] ?? 0) > 0) hasItems = true;
                    }
                    if (!hasItems) {
                       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecione itens para devolver.'), backgroundColor: Colors.red));
                       return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Gerar Devolução'),
                ),
              ],
            );
          }
        );
      },
    );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      try {
        final currentUser = _authService.currentUser;
        final userName = currentUser?.displayName ?? currentUser?.email ?? 'Usuário';

        List<DeliveryItem> itemsReturningNow = [];
        for (int i = 0; i < originalDelivery.items.length; i++) {
          final qty = returnsMap[i] ?? 0;
          if (qty > 0) {
            final originalItem = originalDelivery.items[i];
            itemsReturningNow.add(DeliveryItem(
              productId: originalItem.productId,
              sku: originalItem.sku,
              productName: originalItem.productName,
              quantity: qty, 
              logoType: originalItem.logoType,
              returnReason: reasonsControllers[i]?.text,
            ));
          }
        }

        await _firestoreService.registerReturnTransaction(
          orderId: widget.order.id!,
          originalDeliveryId: originalDelivery.id!,
          itemsReturning: itemsReturningNow,
          clientName: widget.client.name,
          userName: userName,
        );

        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Devolução registrada em novo recibo!'), backgroundColor: Colors.green));
        }
      } catch (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
      } finally {
        if(mounted) setState(() => _isProcessing = false);
      }
    }
  }

  void _cancelDelivery(Delivery delivery) async {
     final bool? confirm = await showDialog<bool>(
       context: context,
       builder: (context) => AlertDialog(
         title: const Text('Cancelar Entrega'),
         content: const Text('Tem certeza que deseja cancelar esta saída? Os itens retornarão ao status "Em Estoque".'),
         actions: [
           TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')),
           ElevatedButton(
             onPressed: () => Navigator.of(context).pop(true),
             style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
             child: const Text('Sim, Cancelar'),
           ),
         ],
       ),
     );

    if (confirm == true) {
      setState(() => _isProcessing = true);
      try {
        await _firestoreService.cancelDelivery(delivery.id!);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrega cancelada e itens retornaram ao estoque.'), backgroundColor: Colors.orange));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao cancelar entrega: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico #${widget.order.id?.substring(0, 6).toUpperCase()}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_isGeneratingPdf || _isProcessing)
            const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)))
        ],
      ),
      body: StreamBuilder<List<Delivery>>(
        stream: _firestoreService.getDeliveriesForOrderStream(widget.order.id!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.isEmpty) return const Center(child: Text('Nenhuma movimentação registrada.'));

          final deliveries = snapshot.data!;
          
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: deliveries.length,
            itemBuilder: (context, index) {
              final delivery = deliveries[index];
              final isReturn = delivery.type == DeliveryType.devolucao;
              final isDelivered = delivery.status == DeliveryStatus.entregue;
              
              final totalQtd = delivery.items.map((e) => e.quantity).reduce((a, b) => a + b);
              
              int totalImmediateReturn = 0;
              int totalAccepted = 0;
              if (!isReturn) {
                 totalImmediateReturn = delivery.items.map((e) => e.returnQuantity).reduce((a, b) => a + b);
                 totalAccepted = totalQtd - totalImmediateReturn; 
              }

              return Card(
                color: isReturn ? Colors.orange.shade50 : (isDelivered ? Colors.green.shade50 : null),
                elevation: 2,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isReturn ? Colors.orange : (isDelivered ? Colors.green : Colors.blue),
                    child: Icon(
                      isReturn ? Icons.arrow_downward : Icons.arrow_upward,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    isReturn ? 'DEVOLUÇÃO' : 'SAÍDA / ENTREGA',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isReturn ? Colors.deepOrange : Colors.black87
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(DateFormat('dd/MM/yyyy HH:mm').format(delivery.deliveryDate.toDate())),
                      const SizedBox(height: 4),
                      if (isReturn)
                        Text('$totalQtd itens devolvidos pelo cliente.')
                      else if (isDelivered && totalImmediateReturn > 0)
                        Text('Enviados: $totalQtd | Entregues: $totalAccepted | Devolvidos: $totalImmediateReturn', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))
                      else if (isDelivered)
                        Text('Motorista: ${delivery.driverName} | Total Entregue: $totalQtd itens')
                      else
                        Text('Motorista: ${delivery.driverName} | Total Enviado: $totalQtd itens'),
                      
                      if (!isReturn) Text('Status: ${isDelivered ? 'Entregue' : 'Em Trânsito'}'),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print_outlined),
                        tooltip: 'Imprimir Comprovante',
                        onPressed: () => _generateDeliveryNotePdf(delivery),
                      ),
                      
                      if (!isReturn && isDelivered)
                        IconButton(
                          icon: const Icon(Icons.replay, color: Colors.orange),
                          tooltip: 'Gerar Devolução Posterior',
                          onPressed: () => _registerPostDeliveryReturn(delivery),
                        ),

                      if (!isReturn && !isDelivered) ...[
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                          tooltip: 'Cancelar Saída',
                          onPressed: () => _cancelDelivery(delivery),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.check_circle_outline,
                            color: isDelivered ? Colors.grey : Colors.green,
                          ),
                          tooltip: 'Confirmar Recebimento',
                          onPressed: () => _confirmDeliveryReceived(delivery),
                        ),
                      ]
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