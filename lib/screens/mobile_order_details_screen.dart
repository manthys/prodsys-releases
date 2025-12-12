// lib/screens/mobile_order_details_screen.dart (NOVO ARQUIVO - COMPLETO)

import 'dart:io';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

// Imports dos modelos
import '../models/payment_distribution_model.dart';
import '../models/delivery_model.dart';
import '../models/order_model.dart';
import '../models/order_item_model.dart';
import '../models/stock_item_model.dart';
import '../models/client_model.dart';
import '../models/company_settings_model.dart';
import '../models/delivery_selection_item_model.dart'; 

// Imports dos serviços
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_service.dart';
import '../services/receipt_pdf_service.dart';
import '../services/delivery_pdf_service.dart';
import '../services/production_simulator.dart';

// Imports dos widgets
import '../widgets/delivery_dialog.dart';
import '../widgets/payment_confirmation_dialog.dart';
import '../widgets/payment_distribution_dialog.dart';
import '../widgets/pickup_dialog.dart';
import '../widgets/currency_input_formatter.dart';

// Imports das telas
import 'order_form_screen.dart'; // ATENÇÃO: Usando a tela do desktop por enquanto
import 'delivery_history_screen.dart';


class MobileOrderDetailsScreen extends StatefulWidget {
  final Order order;
  const MobileOrderDetailsScreen({super.key, required this.order});

  @override
  State<MobileOrderDetailsScreen> createState() => _MobileOrderDetailsScreenState();
}

class _MobileOrderDetailsScreenState extends State<MobileOrderDetailsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  final PdfService _orderPdfService = PdfService();
  final ReceiptPdfService _receiptPdfService = ReceiptPdfService();
  final DeliveryPdfService _deliveryPdfService = DeliveryPdfService();
  late final ProductionSimulator _simulator;
  late Order _currentOrder;
  bool _isGeneratingPdf = false;
  bool _isUploading = false;
  List<StockItem>? _stockItemsForOrder;
  List<Delivery>? _deliveriesForOrder;

  bool _isLoading = true;
  DateTime? _recalculatedDeliveryDate;
  bool _isRecalculatingDate = false;
  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _simulator = ProductionSimulator(_firestoreService);
    _loadInitialData();
  }
  
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    
    final results = await Future.wait([
      _firestoreService.getStockItemsForOrder(_currentOrder.id!),
      _firestoreService.getDeliveriesForOrderStream(_currentOrder.id!).first,
      _authService.getUserRole(_authService.currentUser!.uid),
    ]);

    if(mounted) {
      setState(() {
        _stockItemsForOrder = results[0] as List<StockItem>;
        _deliveriesForOrder = results[1] as List<Delivery>;
        _currentUserRole = results[2] as String;
        _isLoading = false;
      });
      _recalculateDateIfNeeded();
    }
  }

  Future<void> _reloadOrder() async {
    final updatedOrder = await _firestoreService.getOrderById(_currentOrder.id!);
    if (updatedOrder != null && mounted) {
      setState(() {
        _currentOrder = updatedOrder;
      });
      await _loadInitialData();
    }
  }
  
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green));
  }

  Future<void> _recalculateDateIfNeeded() async {
    if (_currentOrder.status == OrderStatus.cotacao || _currentOrder.status == OrderStatus.pedido) {
      setState(() => _isRecalculatingDate = true);
      final estimatedDate = await _simulator.estimateCompletionDate(_currentOrder.items);
      if (mounted) {
        setState(() {
          _recalculatedDeliveryDate = estimatedDate;
          _isRecalculatingDate = false;
        });
      }
    }
  }
  
  List<DeliverySelectionItem> _prepareSelectionItems() {
     if (_stockItemsForOrder == null || _deliveriesForOrder == null) return [];

     final availableInStock = groupBy(
         _stockItemsForOrder!.where((item) => item.status == StockItemStatus.emEstoque),
         (StockItem item) => '${item.productId}-${item.logoType}'
     );

     final alreadyDeliveredCount = <String, int>{};
     for (final delivery in _deliveriesForOrder!) {
         for (final deliveredItem in delivery.items) {
             final key = '${deliveredItem.productId}-${deliveredItem.logoType}';
             alreadyDeliveredCount.update(key, (value) => value + deliveredItem.quantity, ifAbsent: () => deliveredItem.quantity);
         }
     }

     final selectionItems = <DeliverySelectionItem>[];
     for (final orderItem in _currentOrder.items) {
         final key = '${orderItem.productId}-${orderItem.logoType}';
         final inStockCount = availableInStock[key]?.length ?? 0;
         
         if (inStockCount > 0) {
             final deliveredCount = alreadyDeliveredCount[key] ?? 0;
             final neededCount = orderItem.quantity - deliveredCount;

             if (neededCount > 0) {
                 selectionItems.add(
                     DeliverySelectionItem(
                         productId: orderItem.productId,
                         sku: orderItem.sku,
                         productName: orderItem.productName,
                         logoType: orderItem.logoType,
                         maxQuantity: inStockCount < neededCount ? inStockCount : neededCount,
                         quantityToDeliver: inStockCount < neededCount ? inStockCount : neededCount,
                     )
                 );
             }
         }
     }
     return selectionItems;
  }

  bool get _areAllItemsDelivered {
    if (_currentOrder.items.isEmpty) return true;
    if (_deliveriesForOrder == null) return false;

    for (final orderItem in _currentOrder.items) {
      int deliveredCount = 0;
      for (final delivery in _deliveriesForOrder!) {
        for (final deliveryItem in delivery.items) {
          if (deliveryItem.productId == orderItem.productId && deliveryItem.logoType == orderItem.logoType) {
            deliveredCount += deliveryItem.quantity;
          }
        }
      }
      if (deliveredCount < orderItem.quantity) {
        return false;
      }
    }
    return true;
  }
  
  void _generateOrderPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final companySettings = await _firestoreService.getCompanySettings();
      final client = await _firestoreService.getClientById(_currentOrder.clientId);
      if (client != null) {
        await _orderPdfService.generateAndShowPdf(_currentOrder, client, companySettings);
      } else {
        _showSnackBar('Erro: Cliente não encontrado.', isError: true);
      }
    } catch (e) {
      _showSnackBar('Erro ao gerar PDF do Pedido: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  void _generateReceiptPdf() async {
    final client = await _firestoreService.getClientById(_currentOrder.clientId);
    if (client == null) {
      _showSnackBar('Erro: Cliente não encontrado.', isError: true);
      return;
    }

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: client.name);
    final amountController = TextEditingController();
    final referenceController = TextEditingController();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerar Recibo de Pagamento'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nome para o Recibo'),
                  validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: amountController,
                  decoration: const InputDecoration(labelText: 'Valor Recebido', prefixText: 'R\$ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [CurrencyInputFormatter()],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Obrigatório';
                    final value = double.tryParse(v.replaceAll('.', '').replaceAll(',', '.'));
                    if (value == null || value <= 0) return 'Valor inválido';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: referenceController,
                  decoration: const InputDecoration(labelText: 'Referente a', hintText: 'Ex: Sinal de 50%, 1ª parcela, etc.'),
                    validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.of(context).pop({
                  'name': nameController.text,
                  'amount': double.parse(amountController.text.replaceAll('.', '').replaceAll(',', '.')),
                  'reference': referenceController.text,
                });
              }
            },
            child: const Text('Gerar'),
          ),
        ],
      ),
    );

    if (result == null) return;

    setState(() => _isGeneratingPdf = true);
    try {
      final companySettings = await _firestoreService.getCompanySettings();
      await _receiptPdfService.generateAndShowPdf(
        _currentOrder,
        client,
        companySettings,
        recipientName: result['name'],
        receivedAmount: result['amount'],
        paymentReference: result['reference'],
      );
    } catch (e) {
      _showSnackBar('Erro ao gerar Recibo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isGeneratingPdf = false);
    }
  }

  void _confirmarExclusao() async {
    final bool? confirmar = await showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Confirmar Exclusão'), content: const Text('Deseja realmente excluir esta cotação? Esta ação não pode ser desfeita.'), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')), ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Sim, Excluir'))]));
    if (confirmar == true) {
      await _firestoreService.handleOrderCancellation(_currentOrder.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }
  
  void _converterParaPedido() async {
    final dateToConfirm = _recalculatedDeliveryDate ?? _currentOrder.deliveryDate?.toDate() ?? DateTime.now();
    
    final bool? confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Converter em Pedido'),
        content: Text('A previsão de entrega para este pedido é ${DateFormat('dd/MM/yyyy').format(dateToConfirm)}. Deseja continuar?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sim, Converter')),
        ],
      ),
    );

    if (confirmar == true) {
      await _firestoreService.updateOrder(
        _currentOrder.copyWith(
          status: OrderStatus.pedido,
          deliveryDate: Timestamp.fromDate(dateToConfirm),
        )
      );
      _showSnackBar('Cotação convertida em Pedido! Aguardando pagamento do sinal.');
      _reloadOrder();
    }
  }

  void _cancelarPedido() async {
    if (_currentUserRole != 'admin') {
      _showSnackBar('Você não tem permissão para cancelar pedidos.', isError: true);
      return;
    }

    final bool isFinalized = _currentOrder.status == OrderStatus.finalizado;
    final String warningMessage = isFinalized
      ? 'Tem certeza que deseja cancelar este pedido FINALIZADO? Todos os itens entregues retornarão ao estoque geral e o status será "Cancelado". Esta ação é recomendada para casos de devolução total.'
      : 'Tem certeza que deseja cancelar este pedido? Os itens de produção associados serão excluídos.';
    
    final bool? confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Cancelamento'),
        content: Text(warningMessage),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Sim, Cancelar')
          )
        ]
      )
    );

    if (confirmar == true) {
      try {
        await _firestoreService.handleOrderCancellation(_currentOrder.id!);
        _showSnackBar('Pedido cancelado. Itens retornaram ao estoque, se aplicável.');
        _reloadOrder();
      } catch (e) {
        _showSnackBar('Erro ao cancelar o pedido: $e', isError: true);
      }
    }
  }

  Future<void> _triggerSmartAllocation(Order order) async {
    final dateToConfirm = _recalculatedDeliveryDate ?? order.deliveryDate?.toDate() ?? DateTime.now();
    if (!mounted) return;
    final groupedStock = await _firestoreService.findAvailableStockForOrder(order);
    if (!mounted) return;
    final allOrders = await _firestoreService.getOrdersStream().first;
    if (!mounted) return;
    List<StockItem> chosenItems = [];
    if (groupedStock.stockByOrderId.isNotEmpty) {
      final List<StockItem>? result = await showDialog<List<StockItem>>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => _AllocationDialog(
          groupedStock: groupedStock.stockByOrderId,
          allOrders: allOrders,
          neededItems: order.items,
        ),
      );
      if (result == null) {
        _showSnackBar('Alocação cancelada pelo usuário. Os itens serão produzidos do zero.', isError: true);
      } else {
        chosenItems = result;
      }
    }
    await _processOrderProduction(order, chosenItems, dateToConfirm);
  }

  Future<void> _processOrderProduction(Order order, List<StockItem> chosenItems, DateTime newEstimatedDate) async {
    setState(() => _isUploading = true);
    try {
      if (order.status == OrderStatus.pedido) {
        final dataToUpdate = {
          'status': OrderStatus.emFabricacao.name,
          'confirmationDate': Timestamp.now(),
          'deliveryDate': Timestamp.fromDate(newEstimatedDate),
        };
        await _firestoreService.updateOrderPayment(order.id!, dataToUpdate);
      }
      final updatedOrder = await _firestoreService.getOrderById(order.id!);
      if (updatedOrder == null) throw Exception("Pedido não encontrado após atualização.");
      await _firestoreService.processSmartAllocationForOrder(updatedOrder, chosenItems);
      _showSnackBar('Itens enviados para produção/alocados com sucesso!');
      _reloadOrder();
    } catch (e) {
      _showSnackBar('Erro no processo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _confirmInitialPayment() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PaymentConfirmationDialog(totalAmount: _currentOrder.finalAmount),
    );
    if (result == null) return;
    setState(() => _isUploading = true);
    try {
      final double amountToConfirm = result['amount'];
      final List<PaymentDistribution> distributions = result['distributions'];
      final PlatformFile? proof = result['proof'];
      PaymentStatus newPaymentStatus;
      if ((_currentOrder.amountPaid + amountToConfirm) >= _currentOrder.finalAmount) {
        newPaymentStatus = PaymentStatus.pagoIntegralmente;
      } else if (amountToConfirm > 0) {
        newPaymentStatus = PaymentStatus.sinalPago;
      } else {
        newPaymentStatus = _currentOrder.paymentStatus;
      }
      final updatedDistributions = [..._currentOrder.paymentDistributions, ...distributions];
      final Map<String, dynamic> paymentData = {
        'paymentDistributions': updatedDistributions.map((d) => d.toJson()).toList(),
        'paymentStatus': newPaymentStatus.name,
      };
      await _firestoreService.updateOrderPayment(_currentOrder.id!, paymentData);
      if (proof != null) {
        await _uploadProof(proof);
      }
      final updatedOrder = await _firestoreService.getOrderById(_currentOrder.id!);
      if (updatedOrder != null) {
        await _triggerSmartAllocation(updatedOrder);
      }
    } catch (e) {
       _showSnackBar('Erro ao confirmar pagamento: $e', isError: true);
    } finally {
      if(mounted) setState(() => _isUploading = false);
    }
  }
  
  Future<void> _attachProof() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.first.path == null) return;
    
    final pickedFile = result.files.first;
    
    final bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Anexo'),
        content: Text('Deseja anexar o arquivo ${pickedFile.name} a este pedido?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sim, Anexar')),
        ],
      )
    );

    if (confirm != true) return;

    setState(() => _isUploading = true);
    try {
      await _uploadProof(pickedFile);
      _showSnackBar('Comprovante anexado com sucesso!');
    } catch (e) {
      _showSnackBar('Erro ao anexar: $e', isError: true);
    } finally {
      if(mounted) setState(() => _isUploading = false);
      _reloadOrder();
    }
  }
  
  Future<void> _uploadProof(PlatformFile? pickedFile) async {
    if (pickedFile == null || pickedFile.path == null) return;
    
    final file = File(pickedFile.path!);
    final ref = FirebaseStorage.instance.ref('payment_proofs/${_currentOrder.id}/${DateTime.now().millisecondsSinceEpoch}_${pickedFile.name}');
    final uploadTask = await ref.putFile(file);
    final downloadUrl = await uploadTask.ref.getDownloadURL();
    await _firestoreService.addAttachmentUrlToOrder(_currentOrder.id!, downloadUrl);
  }

  Future<void> _confirmFinalPayment() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PaymentConfirmationDialog(
        totalAmount: _currentOrder.finalAmount,
        alreadyPaidAmount: _currentOrder.amountPaid,
      ),
    );

    if (result == null) return;

    final double amountToConfirm = result['amount'];
    final List<PaymentDistribution> distributions = result['distributions'];
    final PlatformFile? proof = result['proof'];

    if (amountToConfirm <= 0) {
        _showSnackBar("Nenhum valor foi adicionado.", isError: true);
        return;
    }

    setState(() => _isUploading = true);
    try {
      if (proof != null) {
        await _uploadProof(proof);
      }

      final updatedDistributions = [..._currentOrder.paymentDistributions, ...distributions];
      await _firestoreService.confirmFinalPaymentAndUpdateStatus(_currentOrder.id!, updatedDistributions);
      _showSnackBar("Pagamento final confirmado!");
      _reloadOrder();
    } catch (e) {
      _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
  
  Future<void> _confirmRefund() async {
    final bool? confirmar = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Devolução'),
        content: const Text('Tem certeza que deseja marcar o reembolso deste pedido como concluído? Esta ação irá registrar a devolução e tentar finalizar o pedido se todas as outras condições estiverem cumpridas.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sim, Confirmar'),
          )
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _firestoreService.confirmRefundAndFinalizeOrder(_currentOrder.id!);
      _showSnackBar('Reembolso confirmado e status do pedido atualizado!');
    } catch (e) {
      _showSnackBar('Erro ao confirmar reembolso: $e', isError: true);
    } finally {
      _reloadOrder();
    }
  }

  Future<void> _editPaymentDistribution() async {
    final List<PaymentDistribution>? updatedDistributions = await showDialog<List<PaymentDistribution>>(
      context: context,
      builder: (context) => PaymentDistributionDialog(
        totalAmount: _currentOrder.amountPaid,
        initialDistributions: _currentOrder.paymentDistributions,
      ),
    );

    if (updatedDistributions != null) {
      try {
        await _firestoreService.updateOrderPaymentDistribution(_currentOrder.id!, updatedDistributions);
        _showSnackBar("Distribuição de pagamento atualizada!");
        _reloadOrder();
      } catch (e) {
        _showSnackBar("Erro ao atualizar: $e", isError: true);
      }
    }
  }

  void _navigateToEditScreen() async {
    final originalStatus = _currentOrder.status;

    final result = await Navigator.of(context).push<Order>(
      MaterialPageRoute(builder: (context) => OrderFormScreen(existingOrder: _currentOrder))
    );

    if (result != null) {
      if (originalStatus == OrderStatus.finalizado && (result.status == OrderStatus.emFabricacao || result.status == OrderStatus.aguardandoEntrega)) {
        setState(() { _currentOrder = result; });
        _showSnackBar('Pedido reaberto. Verificando estoque para alocação...');
        await _triggerSmartAllocation(result);
      } else {
         setState(() { _currentOrder = result; });
        _reloadOrder();
      }
    }
  }

  void _duplicateOrder() {
    final currentUser = _authService.currentUser;
    if (currentUser == null) {
      _showSnackBar('Você precisa estar logado para duplicar um pedido.', isError: true);
      return;
    }
    final newQuote = _currentOrder.duplicateAsQuote(currentUser: currentUser);
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => OrderFormScreen(existingOrder: newQuote)));
  }

  void _registerPickup() async {
      final selectionItems = _prepareSelectionItems();

      if (selectionItems.isEmpty) {
          _showSnackBar('Não há itens em estoque prontos para retirada deste pedido.', isError: true);
          return;
      }

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => PickupDialog(order: _currentOrder, itemsReadyForPickup: selectionItems),
      );

      if (result != null) {
          setState(() => _isUploading = true);
          try {
            final List<DeliverySelectionItem> selectedItems = result['selectedItems'];
            final String pickupPersonName = result['pickupPersonName'];
            final String vehiclePlate = result['vehiclePlate'];
            final currentUser = _authService.currentUser;
            
            final deliveryItems = selectedItems
                .map((sel) => DeliveryItem(
                    productId: sel.productId,
                    sku: sel.sku,
                    productName: sel.productName,
                    quantity: sel.quantityToDeliver,
                    logoType: sel.logoType ?? 'Nenhum',
                  ))
                .toList();
    
            final newDelivery = Delivery(
              orderId: _currentOrder.id!,
              clientName: _currentOrder.clientName,
              deliveryDate: Timestamp.now(),
              items: deliveryItems,
              driverName: pickupPersonName, 
              vehiclePlate: vehiclePlate,
              createdByUserName: currentUser?.displayName ?? currentUser?.email ?? 'N/A',
            );
    
            List<StockItem> stockItemsToUpdate = [];
            List<StockItem> availableItems = List.from(_stockItemsForOrder!.where((i) => i.status == StockItemStatus.emEstoque));
            for (var selItem in selectedItems) {
              var itemsToFind = selItem.quantityToDeliver;
              var foundItems = availableItems
                  .where((stockItem) => stockItem.productId == selItem.productId && stockItem.logoType == selItem.logoType)
                  .take(itemsToFind)
                  .toList();
              stockItemsToUpdate.addAll(foundItems);
              for (var found in foundItems) {
                availableItems.remove(found);
              }
            }
            
            final deliveryId = await _firestoreService.createPickupAndUpdateStock(newDelivery, stockItemsToUpdate);
    
            final client = await _firestoreService.getClientById(_currentOrder.clientId);
            final companySettings = await _firestoreService.getCompanySettings();
            if (client != null && mounted) {
              final createdDelivery = newDelivery.copyWith(id: deliveryId);
              await _deliveryPdfService.generateAndShowPdf(createdDelivery, _currentOrder, client, companySettings);
            }
    
            _showSnackBar('Retirada registrada com sucesso!');
          } catch (e) {
            _showSnackBar('Erro ao registrar retirada: $e', isError: true);
          } finally {
            if (mounted) setState(() => _isUploading = false);
            _reloadOrder();
          }
      }
  }

  void _showDeliveryDialog() async {
      final selectionItems = _prepareSelectionItems();

      if (selectionItems.isEmpty) {
          _showSnackBar('Não há itens em estoque prontos para entrega deste pedido.', isError: true);
          return;
      }

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => DeliveryDialog(order: _currentOrder, itemsReadyForDelivery: selectionItems),
      );

      if (result != null) {
          setState(() => _isUploading = true);
          try {
            final driverName = result['driverName'] as String;
            final vehiclePlate = result['vehiclePlate'] as String;
            final List<DeliverySelectionItem> selectedItems = result['selectedItems'];
            final currentUser = _authService.currentUser;
    
            final deliveryItems = selectedItems.map((sel) => DeliveryItem(
              productId: sel.productId, 
              sku: sel.sku, 
              productName: sel.productName, 
              quantity: sel.quantityToDeliver,
              logoType: sel.logoType ?? 'Nenhum',
            )).toList();
            
            final newDelivery = Delivery(
              orderId: _currentOrder.id!, clientName: _currentOrder.clientName, deliveryDate: Timestamp.now(),
              items: deliveryItems, driverName: driverName, vehiclePlate: vehiclePlate,
              createdByUserName: currentUser?.displayName ?? currentUser?.email ?? 'N/A',
            );
    
            List<StockItem> stockItemsToUpdate = [];
            List<StockItem> availableItems = List.from(_stockItemsForOrder!.where((i) => i.status == StockItemStatus.emEstoque));
    
            for (var selItem in selectedItems) {
              var itemsToFind = selItem.quantityToDeliver;
              var foundItems = availableItems.where((stockItem) => stockItem.productId == selItem.productId && stockItem.logoType == selItem.logoType).take(itemsToFind).toList();
              stockItemsToUpdate.addAll(foundItems);
              for (var found in foundItems) {
                availableItems.remove(found);
              }
            }
    
            await _firestoreService.createDeliveryAndUpdateStock(newDelivery, stockItemsToUpdate);
            _showSnackBar('Entrega registrada com sucesso!');
          } catch(e) {
            _showSnackBar('Erro ao registrar entrega: $e', isError: true);
          } finally {
            if(mounted) setState(() => _isUploading = false);
            _reloadOrder();
          }
      }
  }

  void _forceRecheckStatus() async {
    if (_currentOrder.id == null) return;
    _showSnackBar('Verificando status...', isError: false);

    try {
      await _firestoreService.checkIfOrderIsFullyCompleted(_currentOrder.id!);
      _showSnackBar('Verificação de status concluída.');
    } catch(e) {
      _showSnackBar('Erro ao verificar status: $e', isError: true);
    } finally {
      _reloadOrder();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final bool isAdm = _currentUserRole == 'admin';
    final bool canBeEdited = (_currentOrder.status != OrderStatus.finalizado && _currentOrder.status != OrderStatus.cancelado) || (isAdm && _currentOrder.status == OrderStatus.finalizado);
    final bool canCancel = isAdm && _currentOrder.status != OrderStatus.cancelado;
    final bool canAttachProof = _currentOrder.status != OrderStatus.cotacao && _currentOrder.status != OrderStatus.finalizado && _currentOrder.status != OrderStatus.cancelado;
    final bool canEditPayment = isAdm && _currentOrder.status != OrderStatus.cotacao && _currentOrder.status != OrderStatus.pedido && _currentOrder.status != OrderStatus.cancelado;
    final bool needsRefund = _currentOrder.notes?.contains('[SISTEMA] Valor a devolver ao cliente:') ?? false;
        
    return Scaffold(
      appBar: AppBar(
        title: Text('Detalhes #${_currentOrder.id?.substring(0, 6).toUpperCase() ?? ''}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'duplicate': _duplicateOrder(); break;
                case 'attach': _attachProof(); break;
                case 'editPayment': _editPaymentDistribution(); break;
                case 'editOrder': _navigateToEditScreen(); break;
                case 'pdfOrder': _generateOrderPdf(); break;
                case 'pdfReceipt': _generateReceiptPdf(); break;
                case 'deliveryHistory': _showDeliveryHistory(); break;
                case 'deleteQuote': _confirmarExclusao(); break;
                case 'cancelOrder': _cancelarPedido(); break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(value: 'duplicate', child: ListTile(leading: Icon(Icons.copy), title: Text('Duplicar Cotação'))),
              if (canAttachProof) const PopupMenuItem<String>(value: 'attach', child: ListTile(leading: Icon(Icons.attach_file), title: Text('Anexar Comprovante'))),
              if (canEditPayment) const PopupMenuItem<String>(value: 'editPayment', child: ListTile(leading: Icon(Icons.edit_note), title: Text('Editar Pagamento'))),
              if (canBeEdited) const PopupMenuItem<String>(value: 'editOrder', child: ListTile(leading: Icon(Icons.edit), title: Text('Editar Itens'))),
              const PopupMenuItem<String>(value: 'pdfOrder', child: ListTile(leading: Icon(Icons.picture_as_pdf), title: Text('Gerar PDF Pedido'))),
              if (_currentOrder.status != OrderStatus.cotacao && _currentOrder.status != OrderStatus.cancelado)
                const PopupMenuItem<String>(value: 'pdfReceipt', child: ListTile(leading: Icon(Icons.receipt), title: Text('Gerar Recibo'))),
              if (_currentOrder.status != OrderStatus.cotacao && _currentOrder.status != OrderStatus.cancelado)
                const PopupMenuItem<String>(value: 'deliveryHistory', child: ListTile(leading: Icon(Icons.local_shipping_outlined), title: Text('Histórico Entregas'))),
              if (_currentOrder.status == OrderStatus.cotacao)
                const PopupMenuItem<String>(value: 'deleteQuote', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Excluir Cotação', style: TextStyle(color: Colors.red)))),
              if (canCancel)
                const PopupMenuItem<String>(value: 'cancelOrder', child: ListTile(leading: Icon(Icons.cancel, color: Colors.red), title: Text('Cancelar Pedido', style: TextStyle(color: Colors.red)))),
            ],
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(12.0), 
            children: [
              _buildClientInfoSection(needsRefund: needsRefund),
              const SizedBox(height: 16), 
              _buildItemsSection(),
              const SizedBox(height: 16),
              _buildTotalsSection(), 
              _buildPaymentDistributionSection(), 
              const SizedBox(height: 16), 
              _buildNotesSection(), 
              _buildAttachmentsSection(), 
              const SizedBox(height: 32),
              if (_isUploading)
                const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
              else
                _buildActionButtons(),
              const SizedBox(height: 20),
            ]
          ),
    );
  }
  
  void _showDeliveryHistory() async {
    final client = await _firestoreService.getClientById(_currentOrder.clientId);
    final companySettings = await _firestoreService.getCompanySettings();
    if (client != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (context) => DeliveryHistoryScreen(order: _currentOrder, client: client, companySettings: companySettings)));
      _reloadOrder();
    }
  }

  Widget _buildClientInfoSection({required bool needsRefund}) {
    final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
    final dateToShow = _recalculatedDeliveryDate ?? _currentOrder.deliveryDate?.toDate();
    final deliveryDateFormatted = dateToShow != null 
        ? DateFormat('dd/MM/yyyy').format(dateToShow)
        : 'A definir';
    String? refundAmountString;
    if (needsRefund) {
      final regex = RegExp(r'Valor a devolver ao cliente: R\$(\d+[\.,]\d{2})');
      final match = regex.firstMatch(_currentOrder.notes!);
      if (match != null) {
        refundAmountString = "R\$ ${match.group(1)}";
      }
    }
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, 
          children: [
            Text('Cliente: ${_currentOrder.clientName}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 20)), 
            if (_currentOrder.buyerName != null && _currentOrder.buyerName!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Comprador: ${_currentOrder.buyerName}', style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                    if (_currentOrder.buyerPhone != null && _currentOrder.buyerPhone!.isNotEmpty)
                      Text('Telefone: ${_currentOrder.buyerPhone}', style: const TextStyle(fontStyle: FontStyle.italic)),
                    if (_currentOrder.buyerEmail != null && _currentOrder.buyerEmail!.isNotEmpty)
                      Text('E-mail: ${_currentOrder.buyerEmail}', style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            const Divider(height: 20),
            Text('Data do Pedido: ${dateFormatter.format(_currentOrder.creationDate.toDate())}'),
            Row(
              children: [
                Text('Previsão de Entrega: $deliveryDateFormatted', style: const TextStyle(fontWeight: FontWeight.bold)),
                if (_isRecalculatingDate) ...[
                  const SizedBox(width: 8),
                  const SizedBox(height: 12, width: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                ]
              ],
            ),
            Text('Criado por: ${_currentOrder.createdByUserName}'), 
            const SizedBox(height: 12), 
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  label: Text(_getStatusName(_currentOrder.status), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
                  backgroundColor: _getStatusColor(_currentOrder.status), 
                  padding: const EdgeInsets.symmetric(horizontal: 8)
                ),
                if(needsRefund)
                  Chip(
                    label: Text('Reembolso Pendente (${refundAmountString ?? ""})'),
                    backgroundColor: Colors.orange.shade100,
                    side: BorderSide(color: Colors.orange.shade300),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
              ]
            ),
          ]
        ),
      ),
    );
  }

  Widget _buildItemsSection() {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Itens do Pedido:', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            ..._currentOrder.items.map((orderItem) {
              final producedCount = orderItem.quantityProduced;
              int deliveredCount = 0;
              if (_deliveriesForOrder != null) {
                for (final d in _deliveriesForOrder!) {
                  deliveredCount += d.items.where((i) => i.productId == orderItem.productId && i.logoType == orderItem.logoType).fold(0, (sum, i) => sum + i.quantity);
                }
              }
              final inStockCount = max(0, producedCount - deliveredCount);

              return Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(orderItem.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('SKU: ${orderItem.sku}'),
                    Text('${orderItem.quantity} x ${currencyFormatter.format(orderItem.finalUnitPrice)}', style: const TextStyle(color: Colors.grey)),
                    Text('Produzidos: $producedCount de ${orderItem.quantity}'),
                    Text('Entregues: $deliveredCount de ${orderItem.quantity}'),
                    if (inStockCount > 0)
                      Text('Em estoque: $inStockCount', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        currencyFormatter.format(orderItem.totalPrice),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTotalsSection() {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final theme = Theme.of(context);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildTotalRow('Subtotal dos Itens:', currencyFormatter.format(_currentOrder.totalItemsAmount), theme.textTheme.bodyMedium),
            _buildTotalRow('Frete:', currencyFormatter.format(_currentOrder.shippingCost), theme.textTheme.bodyMedium),
            _buildTotalRow('Desconto:', '- ${currencyFormatter.format(_currentOrder.discount)}', theme.textTheme.bodyMedium?.copyWith(color: Colors.red)),
            const Divider(height: 20),
            _buildTotalRow('TOTAL:', currencyFormatter.format(_currentOrder.finalAmount), theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            _buildTotalRow('Valor Pago:', currencyFormatter.format(_currentOrder.amountPaid), theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.green.shade800)),
          ]
        ),
      ),
    );
  }

  Widget _buildTotalRow(String label, String value, TextStyle? style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _buildPaymentDistributionSection() {
    if (_currentOrder.paymentDistributions.isEmpty) return const SizedBox.shrink();
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Recebido por:", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            ..._currentOrder.paymentDistributions.map((dist) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.person, size: 20),
                title: Text(dist.recipient),
                trailing: Text(currencyFormatter.format(dist.amount)),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    if (_currentOrder.notes == null || _currentOrder.notes!.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Observações:', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            SizedBox(width: double.infinity, child: Text(_currentOrder.notes!)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection() {
    if (_currentOrder.attachmentUrls.isEmpty) return const SizedBox.shrink();
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Anexos (Comprovantes):', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            ..._currentOrder.attachmentUrls.asMap().entries.map((entry) {
              int index = entry.key;
              String url = entry.value;
              return ListTile(
                leading: const Icon(Icons.file_present, color: Colors.blue),
                title: Text('Comprovante ${index + 1}'),
                subtitle: const Text('Clique para visualizar', style: TextStyle(color: Colors.blue)),
                onTap: () async {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  } else {
                    _showSnackBar('Não foi possível abrir o anexo.', isError: true);
                  }
                },
              );
            }).toList()
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButtons() {
    final bool hasItemsInStock = _stockItemsForOrder?.any((item) => item.status == StockItemStatus.emEstoque) ?? false;
    final bool needsRefund = _currentOrder.notes?.contains('[SISTEMA] Valor a devolver ao cliente:') ?? false;
    final style = ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12), textStyle: const TextStyle(fontSize: 16));
    
    if (needsRefund && _areAllItemsDelivered) {
      return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.undo_rounded), label: const Text('Confirmar Devolução'), style: style.copyWith(backgroundColor: MaterialStateProperty.all(Colors.teal)), onPressed: _confirmRefund));
    }
    
    if (_currentOrder.status == OrderStatus.cotacao) return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.check_circle), label: const Text('Converter em Pedido'), style: style.copyWith(backgroundColor: MaterialStateProperty.all(Colors.orange)), onPressed: _converterParaPedido));
    if (_currentOrder.status == OrderStatus.pedido && _currentOrder.paymentStatus == PaymentStatus.aguardandoSinal) return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento'), style: style.copyWith(backgroundColor: MaterialStateProperty.all(Colors.green)), onPressed: _confirmInitialPayment));
    
    if ((_currentOrder.status == OrderStatus.emFabricacao || _currentOrder.status == OrderStatus.aguardandoEntrega) && hasItemsInStock) {
      List<Widget> buttons = [
        SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.storefront), label: const Text('Registrar Retirada'), style: style.copyWith(backgroundColor: MaterialStateProperty.all(Colors.brown)), onPressed: _registerPickup)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.local_shipping_outlined), label: const Text('Registrar Entrega'), style: style.copyWith(backgroundColor: MaterialStateProperty.all(Colors.indigo)), onPressed: _showDeliveryDialog)),
      ];
      if (_currentOrder.paymentStatus == PaymentStatus.sinalPago) {
        buttons.add(const SizedBox(height: 10));
        buttons.add(SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento Final'), style: style.copyWith(backgroundColor: MaterialStateProperty.all(Colors.blue)), onPressed: _confirmFinalPayment)));
      }
      return Column(children: buttons);
    }
    
    if (_currentOrder.status == OrderStatus.aguardandoPagamentoFinal && !needsRefund) {
        return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento Final'), style: style.copyWith(backgroundColor: MaterialStateProperty.all(Colors.blue)), onPressed: _confirmFinalPayment));
    }

    return const SizedBox.shrink();
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.cotacao: return Colors.blueGrey;
      case OrderStatus.pedido: return Colors.orange;
      case OrderStatus.emFabricacao: return Colors.blue;
      case OrderStatus.aguardandoEntrega: return Colors.purple;
      case OrderStatus.aguardandoPagamentoFinal: return Colors.amber.shade700;
      case OrderStatus.finalizado: return Colors.green;
      case OrderStatus.cancelado: return Colors.red;
    }
  }

  String _getStatusName(OrderStatus status) {
    switch (status) {
      case OrderStatus.cotacao: return 'Cotação';
      case OrderStatus.pedido: return 'Pedido';
      case OrderStatus.emFabricacao: return 'Em Fabricação';
      case OrderStatus.aguardandoEntrega: return 'Aguardando Entrega';
      case OrderStatus.aguardandoPagamentoFinal: return 'Aguardando Pagamento Final';
      case OrderStatus.finalizado: return 'Finalizado';
      case OrderStatus.cancelado: return 'Cancelado';
    }
  }
}

// =================================================================
// DIÁLOGO DE ALOCAÇÃO (COPIADO DO SEU ARQUIVO)
// =================================================================
class _AllocationDialog extends StatefulWidget {
  final Map<String, List<StockItem>> groupedStock;
  final List<Order> allOrders;
  final List<OrderItem> neededItems;

  const _AllocationDialog({
    required this.groupedStock,
    required this.allOrders,
    required this.neededItems,
  });

  @override
  State<_AllocationDialog> createState() => _AllocationDialogState();
}

class _AllocationDialogState extends State<_AllocationDialog> {
  final Map<String, bool> _sourceSelection = {};
  late Map<String, int> _neededQty;

  @override
  void initState() {
    super.initState();
    for (var key in widget.groupedStock.keys) {
      _sourceSelection[key] = true;
    }
    _calculateNeeded();
  }

  void _calculateNeeded() {
    _neededQty = {};
    // Corrigido para somar quantidades, não apenas pegar a primeira
    for (var item in widget.neededItems) {
      final key = '${item.productId}-${item.logoType}';
      _neededQty.update(key, (value) => value + item.quantity, ifAbsent: () => item.quantity);
    }
  }

  List<StockItem> _getSelectedItems() {
    final selected = <StockItem>[];
    final tempNeeded = Map<String, int>.from(_neededQty);

    final List<String> sourceKeys = widget.groupedStock.keys.toList();
    sourceKeys.sort((a, b) {
      if (a == 'general') return -1;
      if (b == 'general') return 1;
      return a.compareTo(b);
    });

    for(final sourceKey in sourceKeys) {
      if (_sourceSelection[sourceKey] == true) {
        final sortedItems = List<StockItem>.from(widget.groupedStock[sourceKey]!);
        sortedItems.sort((a, b) => (a.deliveryDeadline ?? a.creationDate).compareTo(b.deliveryDeadline ?? b.creationDate));

        for (final item in sortedItems) {
          final itemKey = '${item.productId}-${item.logoType}';
          if ((tempNeeded[itemKey] ?? 0) > 0) {
            selected.add(item);
            tempNeeded[itemKey] = tempNeeded[itemKey]! - 1;
          }
        }
      }
    }
    return selected;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Alocação Inteligente de Estoque'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selecione as fontes de estoque que deseja usar:'),
              const SizedBox(height: 8),
              ...widget.groupedStock.keys.map((orderId) {
                final items = widget.groupedStock[orderId]!;
                final order = orderId == 'general' 
                  ? null 
                  : widget.allOrders.firstWhere((o) => o.id == orderId, orElse: () => widget.allOrders.first);
                
                final title = orderId == 'general'
                  ? 'Estoque Geral (${items.length} un.)'
                  : 'Pedido #${orderId.substring(0,6).toUpperCase()} (${order?.clientName}) - ${items.length} un.';

                final itemsByProduct = groupBy(items, (StockItem item) => '${item.productId}-${item.logoType}');

                return ExpansionTile(
                  key: PageStorageKey(orderId),
                  title: Text(title),
                  leading: Checkbox(
                    value: _sourceSelection[orderId],
                    onChanged: (value) {
                      setState(() {
                        _sourceSelection[orderId] = value ?? false;
                      });
                    },
                  ),
                  initiallyExpanded: true,
                  children: itemsByProduct.entries.map((entry) {
                    final firstItem = entry.value.first;
                    final count = entry.value.length;
                    return ListTile(
                      title: Text(firstItem.productName, style: const TextStyle(fontSize: 14)),
                      subtitle: Text('SKU: ${firstItem.sku} | Logo: ${firstItem.logoType}'),
                      trailing: Text('$count un.', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    );
                  }).toList(),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(_getSelectedItems());
          },
          child: const Text('Confirmar e Alocar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(<StockItem>[]),
          child: const Text('Produzir do Zero'),
        ),
      ],
    );
  }
  
}