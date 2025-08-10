// lib/screens/order_details_screen.dart

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/delivery_model.dart';
import '../models/order_model.dart';
import '../models/stock_item_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/pdf_service.dart';
import '../services/delivery_pdf_service.dart';
import '../widgets/delivery_dialog.dart';
import 'order_form_screen.dart';
import 'delivery_history_screen.dart'; // <-- NOVO IMPORT

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
  late Order _currentOrder;
  bool _isGeneratingPdf = false;
  bool _isUploading = false;

  // ... (initState, reloadOrder, showSnackBar, generateOrderPdf, e outras funções permanecem iguais)
  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
  }
  Future<void> _reloadOrder() async {
    final updatedOrder = await _firestoreService.getOrderById(_currentOrder.id!);
    if (updatedOrder != null && mounted) setState(() => _currentOrder = updatedOrder);
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
  void _confirmarExclusao() async {
    final bool? confirmar = await showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Confirmar Exclusão'), content: const Text('Deseja realmente excluir esta cotação? Esta ação não pode ser desfeita.'), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')), ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Sim, Excluir'))]));
    if (confirmar == true) {
      await _firestoreService.deleteOrder(_currentOrder.id!);
      if (mounted) Navigator.of(context).pop();
    }
  }
  void _converterParaPedido() async {
    await _firestoreService.updateOrderStatus(_currentOrder.id!, OrderStatus.pedido);
    _showSnackBar('Cotação convertida em Pedido! Aguardando pagamento do sinal.');
    _reloadOrder();
  }
  void _cancelarPedido() async {
    final bool? confirmar = await showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Confirmar Cancelamento'), content: const Text('Tem certeza que deseja cancelar este pedido? Os itens de produção associados serão excluídos.'), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')), ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Sim, Cancelar'))]));
    if (confirmar == true) {
      try {
        await _firestoreService.updateOrderStatus(_currentOrder.id!, OrderStatus.cancelado);
        await _firestoreService.deleteStockItemsForOrder(_currentOrder.id!);
        _showSnackBar('Pedido cancelado e itens de produção removidos.');
        _reloadOrder();
      } catch (e) {
        _showSnackBar('Erro ao cancelar o pedido: $e', isError: true);
      }
    }
  }
  Future<void> _confirmInitialPayment() async {
    PlatformFile? pickedFile;
    int paymentOption = 0;
    final bool? confirmed = await showDialog<bool>(context: context, builder: (context) {
      return StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(title: const Text('Confirmar Pagamento e Iniciar Produção'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Selecione o valor pago:'), RadioListTile<int>(title: const Text('Sinal (50%)'), value: 0, groupValue: paymentOption, onChanged: (value) => setDialogState(() => paymentOption = value!)), RadioListTile<int>(title: const Text('Valor Integral (100%)'), value: 1, groupValue: paymentOption, onChanged: (value) => setDialogState(() => paymentOption = value!)), const Divider(), const SizedBox(height: 16), const Text('Deseja anexar um comprovante? (Opcional)'), const SizedBox(height: 8), Center(child: ElevatedButton.icon(icon: const Icon(Icons.attach_file), label: const Text('Anexar'), onPressed: () async {
          final result = await FilePicker.platform.pickFiles();
          if (result != null) setDialogState(() => pickedFile = result.files.first);
        })), if (pickedFile != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Center(child: Text('Arquivo: ${pickedFile!.name}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold))))])), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmar'))]);
      });
    });
    if (confirmed != true) return;
    final isFullPayment = paymentOption == 1;
    final double amountToConfirm = isFullPayment ? _currentOrder.finalAmount : (_currentOrder.finalAmount / 2);
    final PaymentStatus newPaymentStatus = isFullPayment ? PaymentStatus.pagoIntegralmente : PaymentStatus.sinalPago;
    final String successMessage = isFullPayment ? 'Pagamento integral confirmado!' : 'Sinal confirmado!';
    setState(() => _isUploading = true);
    try {
      final Map<String, dynamic> dataToUpdate = {'amountPaid': amountToConfirm, 'paymentStatus': newPaymentStatus.name, 'status': OrderStatus.emFabricacao.name, 'confirmationDate': Timestamp.now()};
      await _firestoreService.updateOrderPayment(_currentOrder.id!, dataToUpdate);
      if (pickedFile != null && pickedFile!.path != null) {
        final file = File(pickedFile!.path!);
        final ref = FirebaseStorage.instance.ref('payment_proofs/${_currentOrder.id}/${DateTime.now().millisecondsSinceEpoch}_${pickedFile!.name}');
        final uploadTask = await ref.putFile(file);
        final downloadUrl = await uploadTask.ref.getDownloadURL();
        await _firestoreService.addAttachmentUrlToOrder(_currentOrder.id!, downloadUrl);
      }
      final updatedOrder = await _firestoreService.getOrderById(_currentOrder.id!);
      if (updatedOrder != null) await _firestoreService.createStockItemsForOrder(updatedOrder);
      _showSnackBar('$successMessage Itens enviados para produção.');
      _reloadOrder();
    } catch (e) {
      _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
  Future<void> _confirmFinalPayment() async {
    PlatformFile? pickedFile;
    final bool? confirmed = await showDialog<bool>(context: context, builder: (context) {
      return StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(title: const Text("Confirmar Pagamento Final"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text('Deseja anexar um comprovante? (Opcional)'), const SizedBox(height: 20), ElevatedButton.icon(icon: const Icon(Icons.attach_file), label: const Text('Anexar Comprovante'), onPressed: () async {
          final result = await FilePicker.platform.pickFiles();
          if (result != null) setDialogState(() => pickedFile = result.files.first);
        }), if (pickedFile != null) Padding(padding: const EdgeInsets.only(top: 8.0), child: Text('Arquivo: ${pickedFile!.name}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)))]), actions: [TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')), ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Confirmar'))]);
      });
    });
    if (confirmed != true) return;
    setState(() => _isUploading = true);
    try {
      final Map<String, dynamic> dataToUpdate = {'amountPaid': _currentOrder.finalAmount, 'paymentStatus': PaymentStatus.pagoIntegralmente.name};
      await _firestoreService.updateOrderPayment(_currentOrder.id!, dataToUpdate);
      if (pickedFile != null && pickedFile!.path != null) {
        final file = File(pickedFile!.path!);
        final ref = FirebaseStorage.instance.ref('payment_proofs/${_currentOrder.id}/${DateTime.now().millisecondsSinceEpoch}_${pickedFile!.name}');
        final uploadTask = await ref.putFile(file);
        final downloadUrl = await uploadTask.ref.getDownloadURL();
        await _firestoreService.addAttachmentUrlToOrder(_currentOrder.id!, downloadUrl);
      }
      _showSnackBar("Pagamento final confirmado!");
      _reloadOrder();
    } catch (e) {
       _showSnackBar('Erro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
  void _showDeliveryDialog() async {
    final allStockItems = await _firestoreService.getStockItemsStream().first;
    final itemsReadyForDelivery = allStockItems.where((item) => item.orderId == _currentOrder.id && item.status == StockItemStatus.emEstoque).toList();
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
        final selectedItems = result['selectedItems'] as List<DeliverySelectionItem>;
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

  @override
  Widget build(BuildContext context) {
    final bool canBeEdited = _currentOrder.status == OrderStatus.cotacao || _currentOrder.status == OrderStatus.pedido;
    return Scaffold(
      appBar: AppBar(
        title: Text('Detalhes #${_currentOrder.id?.substring(0, 6).toUpperCase() ?? ''}'),
        actions: [
          IconButton(icon: const Icon(Icons.copy_all_outlined), tooltip: 'Duplicar Pedido', onPressed: _duplicateOrder),
          if (canBeEdited) IconButton(icon: const Icon(Icons.edit), tooltip: 'Editar Pedido', onPressed: _navigateToEditScreen),
          if (_isGeneratingPdf) const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white)))
          else IconButton(icon: const Icon(Icons.picture_as_pdf), tooltip: 'Gerar PDF do Pedido', onPressed: _generateOrderPdf),
          if (_currentOrder.status == OrderStatus.cotacao) IconButton(icon: const Icon(Icons.delete), tooltip: 'Excluir Cotação', onPressed: _confirmarExclusao),
          if (_currentOrder.status != OrderStatus.finalizado && _currentOrder.status != OrderStatus.cancelado) IconButton(icon: const Icon(Icons.cancel), tooltip: 'Cancelar Pedido', onPressed: _cancelarPedido),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildClientInfoSection(), const SizedBox(height: 24), _buildItemsSection(), const Divider(), _buildTotalsSection(), const SizedBox(height: 24), _buildNotesSection(), _buildAttachmentsSection(), const SizedBox(height: 32),
        if (_isUploading) const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()))
        else _buildActionButtons(),
      ])),
    );
  }
  
  // ... (buildClientInfoSection, buildItemsSection, buildTotalsSection, buildNotesSection, buildAttachmentsSection)
  Widget _buildClientInfoSection() {
    final dateFormatter = DateFormat('dd/MM/yyyy HH:mm');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Cliente: ${_currentOrder.clientName}', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8), Text('Data: ${dateFormatter.format(_currentOrder.creationDate.toDate())}'), Text('Criado por: ${_currentOrder.createdByUserName}'), const SizedBox(height: 8), Row(children: [Text('Status: ', style: Theme.of(context).textTheme.bodyLarge), Chip(label: Text(_getStatusName(_currentOrder.status), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: _getStatusColor(_currentOrder.status), padding: const EdgeInsets.symmetric(horizontal: 8))])]);
  }
  Widget _buildItemsSection() {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Itens do Pedido:', style: Theme.of(context).textTheme.titleMedium), const Divider(), ..._currentOrder.items.map((item) => ListTile(contentPadding: EdgeInsets.zero, title: Text(item.productName), subtitle: Text('${item.quantity} x ${currencyFormatter.format(item.finalUnitPrice)}\nSKU: ${item.sku}'), trailing: Text(currencyFormatter.format(item.totalPrice), style: const TextStyle(fontWeight: FontWeight.bold)), isThreeLine: true)).toList()]);
  }
  Widget _buildTotalsSection() {
    final currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return Align(alignment: Alignment.centerRight, child: SizedBox(width: 280, child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Subtotal dos Itens:'), Text(currencyFormatter.format(_currentOrder.totalItemsAmount))]), const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Frete:'), Text(currencyFormatter.format(_currentOrder.shippingCost))]), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Desconto:'), Text('- ${currencyFormatter.format(_currentOrder.discount)}', style: const TextStyle(color: Colors.red))]), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('TOTAL:', style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)), Text(currencyFormatter.format(_currentOrder.finalAmount), style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold))]), const SizedBox(height: 4), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Valor Pago:', style: TextStyle(color: Colors.green.shade800)), Text(currencyFormatter.format(_currentOrder.amountPaid), style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold))])])));
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
        if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
        else _showSnackBar('Não foi possível abrir o anexo.', isError: true);
      });
    }).toList())), const SizedBox(height: 24)]);
  }
  
  // WIDGET DE BOTÕES DE AÇÃO ATUALIZADO
  Widget _buildActionButtons() {
    if (_currentOrder.status == OrderStatus.cotacao) return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.check_circle), label: const Text('Converter em Pedido'), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _converterParaPedido));
    if (_currentOrder.status == OrderStatus.pedido && _currentOrder.paymentStatus == PaymentStatus.aguardandoSinal) return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _confirmInitialPayment));
    if (_currentOrder.status == OrderStatus.aguardandoEntrega) {
      return Column(
        children: [
          SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.local_shipping), label: const Text('Registrar Saída para Entrega'), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _showDeliveryDialog)),
          const SizedBox(height: 10),
          // Botão para ver o histórico
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            icon: const Icon(Icons.history),
            label: const Text('Ver Histórico de Entregas'),
            onPressed: () async {
              // Precisamos dos dados do cliente e da empresa para passar para a tela de histórico
              final client = await _firestoreService.getClientById(_currentOrder.clientId);
              final companySettings = await _firestoreService.getCompanySettings();
              if (client != null && mounted) {
                Navigator.of(context).push(MaterialPageRoute(builder: (context) => DeliveryHistoryScreen(order: _currentOrder, client: client, companySettings: companySettings)));
              }
            },
          )),
        ],
      );
    }
    if (_currentOrder.status == OrderStatus.emFabricacao && _currentOrder.paymentStatus == PaymentStatus.sinalPago) return SizedBox(width: double.infinity, child: ElevatedButton.icon(icon: const Icon(Icons.price_check), label: const Text('Confirmar Pagamento Final'), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: _confirmFinalPayment));
    return const SizedBox.shrink();
  }

  // ... (getStatusColor e getStatusName)
  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.cotacao: return Colors.blueGrey;
      case OrderStatus.pedido: return Colors.orange;
      case OrderStatus.emFabricacao: return Colors.blue;
      case OrderStatus.aguardandoEntrega: return Colors.purple;
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
      case OrderStatus.finalizado: return 'Finalizado';
      case OrderStatus.cancelado: return 'Cancelado';
    }
  }
}