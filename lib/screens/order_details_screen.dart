// lib/screens/order_details_screen.dart

import 'dart:io';
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
import '../widgets/pickup_dialog.dart' hide DeliverySelectionItem;

// Imports das telas
import 'order_form_screen.dart';
import 'delivery_history_screen.dart';


class OrderDetailsScreen extends StatefulWidget {
  final Order order;
  const OrderDetailsScreen({super.key, required this.order});
  @override
  _OrderDetailsScreenState createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  final PdfService _orderPdfService = PdfService();
  final ReceiptPdfService _receiptPdfService = ReceiptPdfService();
  late final ProductionSimulator _simulator;
  late Order _currentOrder;
  bool _isGeneratingPdf = false;
  bool _isUploading = false;
  
  List<StockItem>? _stockItemsForOrder;
  bool _isLoadingStockItems = true;

  DateTime? _recalculatedDeliveryDate;
  bool _isRecalculatingDate = false;

  String? _currentUserRole;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _simulator = ProductionSimulator(_firestoreService);
    _recalculateDateIfNeeded();
    _loadAssociatedStockItems();
    _loadCurrentUserRole();
  }
  
  Future<void> _loadCurrentUserRole() async {
    final user = _authService.currentUser;
    if (user != null) {
      final role = await _authService.getUserRole(user.uid);
      if (mounted) setState(() => _currentUserRole = role);
    }
  }

  Future<void> _loadAssociatedStockItems() async {
    if (!mounted) return;
    setState(() => _isLoadingStockItems = true);
    final items = await _firestoreService.getStockItemsForOrder(_currentOrder.id!);
    if (mounted) {
      setState(() {
        _stockItemsForOrder = items;
        _isLoadingStockItems = false;
      });
    }
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
  
  Future<void> _reloadOrder() async {
    final updatedOrder = await _firestoreService.getOrderById(_currentOrder.id!);
    if (updatedOrder != null && mounted) {
      setState(() => _currentOrder = updatedOrder);
      _recalculateDateIfNeeded();
      _loadAssociatedStockItems();
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: isError ? Colors.red : Colors.green));
  }
  void _generateOrderPdf() async {
    setState(() => _isGeneratingPdf = true);
    try {
      final companySettings = await _firestoreService.getCompanySettings();
      final client = await _firestoreService.getClientById(_currentOrder.clientId);
      if (client != null) await _orderPdfService.generateAndShowPdf(_currentOrder, client, companySettings);
      else _showSnackBar('Erro: Cliente não encontrado.', isError: true);
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

    final nameController = TextEditingController(text: client.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerar Recibo'),
        content: TextField(
          controller: nameController,
          decoration: const InputDecoration(labelText: 'Nome para o Recibo'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Gerar')),
        ],
      ),
    );

    if (confirmed != true || nameController.text.isEmpty) return;

    setState(() => _isGeneratingPdf = true);
    try {
      final companySettings = await _firestoreService.getCompanySettings();
      await _receiptPdfService.generateAndShowPdf(
        _currentOrder,
        client,
        companySettings,
        recipientName: nameController.text,
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
      await _firestoreService.deleteOrder(_currentOrder.id!);
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

    final bool? confirmar = await showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Confirmar Cancelamento'), content: const Text('Tem certeza que deseja cancelar este pedido? Os itens de produção associados serão excluídos.'), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')), ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Sim, Cancelar'))]));
    if (confirmar == true) {
      try {
        await _firestoreService.updateOrderStatus(_currentOrder.id!, OrderStatus.cancelado);
        await _firestoreService.handleOrderCancellation(_currentOrder.id!);
        _showSnackBar('Pedido cancelado e itens de produção removidos.');
        _reloadOrder();
      } catch (e) {
        _showSnackBar('Erro ao cancelar o pedido: $e', isError: true);
      }
    }
  }

  Future<void> _confirmInitialPayment() async {
    final dateToConfirm = _recalculatedDeliveryDate ?? _currentOrder.deliveryDate?.toDate() ?? DateTime.now();
    if (!mounted) return;

    final groupedStock = await _firestoreService.findAvailableStockForOrder(_currentOrder);
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
          neededItems: _currentOrder.items,
        ),
      );
      if (result == null) {
        _showSnackBar('Alocação cancelada pelo usuário.', isError: true);
        return;
      }
      chosenItems = result;
    }

    if(mounted) {
      _showUnifiedPaymentDialog(chosenItems, dateToConfirm);
    }
  }
  
  Future<void> _showUnifiedPaymentDialog(List<StockItem> chosenItems, DateTime newEstimatedDate) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PaymentConfirmationDialog(totalAmount: _currentOrder.finalAmount),
    );

    if (result == null) return;

    final double amountToConfirm = result['amount'];
    final List<PaymentDistribution> distributions = result['distributions'];
    final PlatformFile? proof = result['proof'];

    setState(() => _isUploading = true);

    try {
      PaymentStatus newPaymentStatus;
      if ((_currentOrder.amountPaid + amountToConfirm) >= _currentOrder.finalAmount) {
        newPaymentStatus = PaymentStatus.pagoIntegralmente;
      } else if (amountToConfirm > 0) {
        newPaymentStatus = PaymentStatus.sinalPago;
      } else {
        newPaymentStatus = _currentOrder.paymentStatus;
      }
      
      final updatedDistributions = [..._currentOrder.paymentDistributions, ...distributions];

      final Map<String, dynamic> dataToUpdate = {
        'paymentDistributions': updatedDistributions.map((d) => d.toJson()).toList(),
        'paymentStatus': newPaymentStatus.name,
        'status': OrderStatus.emFabricacao.name,
        'confirmationDate': Timestamp.now(),
        'deliveryDate': Timestamp.fromDate(newEstimatedDate),
      };
      
      await _firestoreService.updateOrderPayment(_currentOrder.id!, dataToUpdate);
      if (proof != null) {
        await _uploadProof(proof);
      }
      
      final updatedOrder = await _firestoreService.getOrderById(_currentOrder.id!);
      if (updatedOrder == null) throw Exception("Pedido não encontrado após atualização.");

      await _firestoreService.processSmartAllocationForOrder(updatedOrder, chosenItems);

      _showSnackBar('Pagamento confirmado! Itens enviados para produção.');
      _reloadOrder();
    } catch (e) {
      _showSnackBar('Erro no processo: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
    final result = await Navigator.of(context).push<Order>(MaterialPageRoute(builder: (context) => OrderFormScreen(existingOrder: _currentOrder)));
    if (result != null && mounted) setState(() => _currentOrder = result);
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
    final itemsReadyForPickup = (_stockItemsForOrder ?? [])
        .where((item) => item.status == StockItemStatus.emEstoque)
        .toList();

    if (itemsReadyForPickup.isEmpty) {
      _showSnackBar('Não há itens em estoque prontos para retirada deste pedido.', isError: true);
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => PickupDialog(order: _currentOrder, itemsReadyForPickup: itemsReadyForPickup),
    );

    if (result != null) {
      setState(() => _isUploading = true);
      try {
        final List<DeliverySelectionItem> selectedItems = result['selectedItems'] as List<DeliverySelectionItem>;
        final currentUser = _authService.currentUser;
        
        final deliveryItems = selectedItems
            .map((sel) => DeliveryItem(
                  productId: sel.productId,
                  sku: sel.sku,
                  productName: sel.productName,
                  quantity: sel.quantityToDeliver,
                ))
            .toList();

        final newDelivery = Delivery(
          orderId: _currentOrder.id!,
          clientName: _currentOrder.clientName,
          deliveryDate: Timestamp.now(),
          items: deliveryItems,
          driverName: 'Retirada na Empresa',
          vehiclePlate: 'N/A',
          createdByUserName: currentUser?.displayName ?? currentUser?.email ?? 'N/A',
        );

        List<StockItem> stockItemsToUpdate = [];
        List<StockItem> availableItems = List.from(itemsReadyForPickup);
        for (var selItem in selectedItems) {
          var itemsToFind = selItem.quantityToDeliver;
          var foundItems = availableItems
              .where((stockItem) => stockItem.productId == selItem.productId)
              .take(itemsToFind)
              .toList();
          stockItemsToUpdate.addAll(foundItems);
          for (var found in foundItems) {
            availableItems.remove(found);
          }
        }
        
        await _firestoreService.createPickupAndUpdateStock(newDelivery, stockItemsToUpdate);
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
    final itemsReadyForDelivery = (_stockItemsForOrder ?? [])
        .where((item) => item.status == StockItemStatus.emEstoque)
        .toList();

    if (itemsReadyForDelivery.isEmpty) {
      _showSnackBar('Não há itens em estoque prontos para entrega deste pedido.', isError: true);
      return;
    }

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => DeliveryDialog(order: _currentOrder, itemsReadyForDelivery: itemsReadyForDelivery),
    );

    if (result != null) {
      setState(() => _isUploading = true);
      try {
        final driverName = result['driverName'] as String;
        final vehiclePlate = result['vehiclePlate'] as String;
        final List<DeliverySelectionItem> selectedItems = result['selectedItems'] as List<DeliverySelectionItem>;
        final currentUser = _authService.currentUser;

        final deliveryItems = selectedItems.map((sel) => DeliveryItem(productId: sel.productId, sku: sel.sku, productName: sel.productName, quantity: sel.quantityToDeliver)).toList();
        
        final newDelivery = Delivery(
          orderId: _currentOrder.id!, clientName: _currentOrder.clientName, deliveryDate: Timestamp.now(),
          items: deliveryItems, driverName: driverName, vehiclePlate: vehiclePlate,
          createdByUserName: currentUser?.displayName ?? currentUser?.email ?? 'N/A',
        );

        List<StockItem> stockItemsToUpdate = [];
        List<StockItem> availableItems = List.from(itemsReadyForDelivery);

        for (var selItem in selectedItems) {
          var itemsToFind = selItem.quantityToDeliver;
          var foundItems = availableItems.where((stockItem) => stockItem.productId == selItem.productId).take(itemsToFind).toList();
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
      if (_currentOrder.status == OrderStatus.emFabricacao) {
        await _firestoreService.checkAndUpdateOrderStatusAfterProduction(_currentOrder.id!);
      } 
      else if (_currentOrder.status == OrderStatus.aguardandoEntrega || _currentOrder.status == OrderStatus.aguardandoPagamentoFinal) {
        await _firestoreService.checkIfOrderIsFullyCompleted(_currentOrder.id!);
      }
      _showSnackBar('Verificação de status concluída.');
    } catch(e) {
      _showSnackBar('Erro ao verificar status: $e', isError: true);
    } finally {
      _reloadOrder();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // =================================================================
    // LÓGICA DE VISIBILIDADE DO BOTÃO DE EDITAR CORRIGIDA AQUI
    // =================================================================
    final bool canBeEdited = _currentOrder.status == OrderStatus.cotacao || 
                             _currentOrder.status == OrderStatus.pedido ||
                             _currentOrder.status == OrderStatus.emFabricacao ||
                             _currentOrder.status == OrderStatus.aguardandoEntrega;
    
    final bool canCancel = _currentUserRole == 'admin' && 
                           _currentOrder.status != OrderStatus.finalizado && 
                           _currentOrder.status != OrderStatus.cancelado;
                           
    final bool canEditPayment = _currentUserRole == 'admin' && 
                                (_currentOrder.status == OrderStatus.emFabricacao ||
                                 _currentOrder.status == OrderStatus.aguardandoEntrega ||
                                 _currentOrder.status == OrderStatus.aguardandoPagamentoFinal ||
                                 _currentOrder.status == OrderStatus.finalizado);
    
    final bool needsRefund = _currentOrder.notes?.contains('Valor a devolver ao cliente:') == true;
    String? refundAmountString;
    if (needsRefund) {
      final regex = RegExp(r'Valor a devolver ao cliente: R\$(\d+[\.,]\d{2})');
      final match = regex.firstMatch(_currentOrder.notes!);
      if (match != null) {
        refundAmountString = "R\$ ${match.group(1)}";
      }
    }
        
    return Scaffold(
      appBar: AppBar(
        title: Text('Detalhes #${_currentOrder.id?.substring(0, 6).toUpperCase() ?? ''}'),
        actions: [
          if (canEditPayment)
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: 'Adicionar/Editar Distribuição de Pagamento',
              onPressed: _editPaymentDistribution,
            ),
          // BOTÃO DE EDITAR AGORA USA A LÓGICA CORRETA
          if (canBeEdited) 
            IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar Itens do Pedido', onPressed: _navigateToEditScreen),

          IconButton(icon: const Icon(Icons.picture_as_pdf), tooltip: 'Gerar PDF do Pedido', onPressed: _generateOrderPdf),
          if (_currentOrder.status != OrderStatus.cotacao && _currentOrder.status != OrderStatus.cancelado)
            IconButton(
              icon: const Icon(Icons.local_shipping_outlined), 
              tooltip: 'Histórico de Entregas', 
              onPressed: () async {
                final client = await _firestoreService.getClientById(_currentOrder.clientId);
                final companySettings = await _firestoreService.getCompanySettings();
                if (client != null && mounted) {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (context) => DeliveryHistoryScreen(order: _currentOrder, client: client, companySettings: companySettings)));
                  _reloadOrder();
                }
              }
            ),
          if (_currentOrder.status == OrderStatus.cotacao) IconButton(icon: const Icon(Icons.delete), tooltip: 'Excluir Cotação', onPressed: _confirmarExclusao),
          if (canCancel) IconButton(icon: const Icon(Icons.cancel), tooltip: 'Cancelar Pedido', onPressed: _cancelarPedido),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildClientInfoSection(needsRefund: needsRefund),
        if (needsRefund)
          Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200)
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Atenção: Este pedido requer o processamento de um reembolso de ${refundAmountString ?? "valor não especificado"}.',
                      style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24), 
        _isLoadingStockItems
          ? const Center(child: CircularProgressIndicator())
          : _buildItemsSection(_stockItemsForOrder ?? []),
        const Divider(), 
        _buildTotalsSection(), 
        _buildPaymentDistributionSection(), 
        const SizedBox(height: 24), 
        _buildNotesSection(), 
        _buildAttachmentsSection(), 
        const SizedBox(height: 32),
        if (_isUploading) const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
        else _buildActionButtons(),
      ])),
    );
  }
  
  Widget _buildClientInfoSection({required bool needsRefund}) {
    final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
    final dateToShow = _recalculatedDeliveryDate ?? _currentOrder.deliveryDate?.toDate();
    final deliveryDateFormatted = dateToShow != null 
        ? DateFormat('dd/MM/yyyy').format(dateToShow)
        : 'A definir';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Cliente: ${_currentOrder.clientName}', style: Theme.of(context).textTheme.titleLarge), 
      const SizedBox(height: 8), 
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
      const SizedBox(height: 8), 
      Row(children: [
        Text('Status: ', style: Theme.of(context).textTheme.bodyLarge), 
        Chip(
          label: Text(_getStatusName(_currentOrder.status), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
          backgroundColor: _getStatusColor(_currentOrder.status), 
          padding: const EdgeInsets.symmetric(horizontal: 8)
        ),
        if(needsRefund) ...[
          const SizedBox(width: 8),
          Chip(
            label: const Text('Reembolso Pendente', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.orange.shade100,
            side: BorderSide(color: Colors.orange.shade300),
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
        ]
      ])
    ]);
  }
  
  Widget _buildItemsSection(List<StockItem> stockItems) {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Itens do Pedido:', style: Theme.of(context).textTheme.titleMedium),
        const Divider(),
        ..._currentOrder.items.map((item) {
          final deliveredCount = stockItems.where((stockItem) =>
            stockItem.productId == item.productId &&
            stockItem.logoType == item.logoType &&
            (stockItem.status == StockItemStatus.entregue || stockItem.status == StockItemStatus.emTransito)
          ).length;

          final subtitleText = 'SKU: ${item.sku}\n'
                               '${item.quantity} x ${currencyFormatter.format(item.finalUnitPrice)}\n'
                               'Entregues/Retirados: $deliveredCount de ${item.quantity}';

          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(item.productName),
            subtitle: Text(subtitleText),
            trailing: Text(
              currencyFormatter.format(item.totalPrice),
              style: const TextStyle(fontWeight: FontWeight.bold)
            ),
            isThreeLine: true,
          );
        })
      ]
    );
  }
  
  Widget _buildTotalsSection() {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 280,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Subtotal dos Itens:'),
              Text(currencyFormatter.format(_currentOrder.totalItemsAmount), style: TextStyle(color: theme.textTheme.bodySmall?.color))
            ]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Frete:'),
              Text(currencyFormatter.format(_currentOrder.shippingCost), style: TextStyle(color: theme.textTheme.bodySmall?.color))
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Desconto:'),
              Text('- ${currencyFormatter.format(_currentOrder.discount)}', style: const TextStyle(color: Colors.red))
            ]),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('TOTAL:', style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
              Text(
                currencyFormatter.format(_currentOrder.finalAmount),
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                )
              )
            ]),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Valor Pago:', style: TextStyle(color: Colors.green.shade800)),
              Text(
                currencyFormatter.format(_currentOrder.amountPaid),
                style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)
              )
            ])
          ]
        )
      )
    );
  }

  Widget _buildPaymentDistributionSection() {
    if (_currentOrder.paymentDistributions.isEmpty) {
      return const SizedBox.shrink();
    }
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Padding(
      padding: const EdgeInsets.only(top: 8.0, right: 8.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 280,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Recebido por:", style: Theme.of(context).textTheme.bodySmall),
              ..._currentOrder.paymentDistributions.map((dist) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16.0, top: 2.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(dist.recipient, style: Theme.of(context).textTheme.bodySmall),
                      Text(currencyFormatter.format(dist.amount), style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    if (_currentOrder.notes == null || _currentOrder.notes!.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Observações:', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 4), Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(4)), child: Text(_currentOrder.notes!)), const SizedBox(height: 24)]);
  }

  Widget _buildAttachmentsSection() {
    if (_currentOrder.attachmentUrls.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Anexos (Comprovantes):', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8), Card(elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade300)), child: Column(children: _currentOrder.attachmentUrls.asMap().entries.map((entry) {
      int index = entry.key;
      String url = entry.value;
      return ListTile(leading: const Icon(Icons.file_present, color: Colors.blue), title: Text('Comprovante ${index + 1}'), subtitle: const Text('Clique para visualizar', style: TextStyle(color: Colors.blue)), onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('Não foi possível abrir o anexo.', isError: true);
        }
      });
    }).toList())), const SizedBox(height: 24)]);
  }
  
  Widget _buildActionButtons() {
    final bool needsRefundConfirmation = _currentOrder.notes?.contains('Valor a devolver ao cliente:') == true &&
                                          _currentOrder.status != OrderStatus.finalizado &&
                                          _currentOrder.status != OrderStatus.cancelado;

    if (needsRefundConfirmation) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: const Icon(Icons.undo_rounded),
          label: const Text('Confirmar Devolução e Finalizar'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)),
          onPressed: _confirmRefund,
        ),
      );
    }
    
    if (_currentOrder.status == OrderStatus.cotacao) return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.check_circle), label: const Text('Converter em Pedido'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _converterParaPedido));
    if (_currentOrder.status == OrderStatus.pedido && _currentOrder.paymentStatus == PaymentStatus.aguardandoSinal) return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _confirmInitialPayment));
    
    if (_currentOrder.status == OrderStatus.emFabricacao || _currentOrder.status == OrderStatus.aguardandoEntrega) {
      List<Widget> buttons = [];
      
      if (_currentOrder.status == OrderStatus.aguardandoEntrega) {
        buttons.add(SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.storefront), label: const Text('Registrar Retirada na Empresa'), style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _registerPickup)));
        buttons.add(const SizedBox(height: 10));
      }

      buttons.add(SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.local_shipping_outlined), label: const Text('Registrar Saída para Entrega'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _showDeliveryDialog)));
      
      if (_currentOrder.paymentStatus == PaymentStatus.sinalPago) {
        buttons.add(const SizedBox(height: 10));
        buttons.add(SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento Final'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _confirmFinalPayment)));
      }
      return Column(children: buttons);
    }
    
    if (_currentOrder.status == OrderStatus.aguardandoPagamentoFinal) {
        return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento Final'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _confirmFinalPayment));
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
    _neededQty = {
      for (var item in widget.neededItems) '${item.productId}-${item.logoType}': item.quantity
    };
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