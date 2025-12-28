import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product_model.dart';
import '../models/mold_model.dart';
import '../models/price_variation_model.dart'; 
import '../services/firestore_service.dart';
import '../widgets/currency_input_formatter.dart';

class BulkPriceUpdateScreen extends StatefulWidget {
  const BulkPriceUpdateScreen({super.key});

  @override
  State<BulkPriceUpdateScreen> createState() => _BulkPriceUpdateScreenState();
}

class _BulkPriceUpdateScreenState extends State<BulkPriceUpdateScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final NumberFormat _currencyFormatter = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<Mold> _allMolds = [];
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  
  Mold? _selectedMold;
  
  final Map<String, bool> _useGlobalPriceMap = {};
  
  // Controladores de Preço
  final Map<String, TextEditingController> _individualSemNotaControllers = {};
  final Map<String, TextEditingController> _individualComNotaControllers = {};
  final TextEditingController _globalSemNotaController = TextEditingController();
  final TextEditingController _globalComNotaController = TextEditingController();

  // NOVOS: Controladores de Porcentagem
  final TextEditingController _globalPercentController = TextEditingController();
  final Map<String, TextEditingController> _individualPercentControllers = {};

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _globalSemNotaController.dispose();
    _globalComNotaController.dispose();
    _globalPercentController.dispose();
    for (var c in _individualSemNotaControllers.values) c.dispose();
    for (var c in _individualComNotaControllers.values) c.dispose();
    for (var c in _individualPercentControllers.values) c.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final molds = await _firestoreService.getMoldsStream().first;
      final products = await _firestoreService.getProductsStream().first;
      
      if (mounted) {
        setState(() {
          _allMolds = molds;
          _allProducts = products;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _onMoldChanged(Mold? mold) {
    if (mold == null) return;

    setState(() {
      _selectedMold = mold;
      _filteredProducts = _allProducts.where((p) {
        return p.moldType == mold.name || p.name.toUpperCase().contains(mold.name.toUpperCase());
      }).toList();

      // Limpa controladores antigos
      _useGlobalPriceMap.clear();
      _individualSemNotaControllers.clear();
      _individualComNotaControllers.clear();
      _individualPercentControllers.clear();
      _globalPercentController.clear(); // Reseta a % global

      for (var p in _filteredProducts) {
        _useGlobalPriceMap[p.id!] = true;
        
        final pSem = _findPrice(p, 'Sem Nota');
        final pCom = _findPrice(p, 'Com Nota');
        
        _individualSemNotaControllers[p.id!] = TextEditingController(text: _formatPrice(pSem));
        _individualComNotaControllers[p.id!] = TextEditingController(text: _formatPrice(pCom));
        _individualPercentControllers[p.id!] = TextEditingController(); // Começa vazio
      }
      
      if (_filteredProducts.isNotEmpty) {
        final first = _filteredProducts.first;
        _globalSemNotaController.text = _formatPrice(_findPrice(first, 'Sem Nota'));
        _globalComNotaController.text = _formatPrice(_findPrice(first, 'Com Nota'));
      }
    });
  }

  double _findPrice(Product p, String type) {
    return p.priceVariations.firstWhere(
      (v) => v.description == type, 
      orElse: () => PriceVariation(description: type, price: 0)
    ).price;
  }

  String _formatPrice(double value) {
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }

  double? _parsePrice(String text) {
    return double.tryParse(text.replaceAll('.', '').replaceAll(',', '.'));
  }

  // =================================================================
  // LÓGICA DE CÁLCULO DE PORCENTAGEM
  // =================================================================
  void _applyGlobalPercentage(String value) {
    if (_filteredProducts.isEmpty) return;
    
    // Pega o valor base do primeiro item (referência global)
    final baseProduct = _filteredProducts.first;
    final baseSem = _findPrice(baseProduct, 'Sem Nota');
    final baseCom = _findPrice(baseProduct, 'Com Nota');

    final percent = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;

    // Calcula: Preço Base + (Preço Base * Porcentagem / 100)
    final newSem = baseSem + (baseSem * (percent / 100));
    final newCom = baseCom + (baseCom * (percent / 100));

    _globalSemNotaController.text = _formatPrice(newSem);
    _globalComNotaController.text = _formatPrice(newCom);
  }

  void _applyIndividualPercentage(String productId, String value) {
    // Acha o produto original na memória para pegar o preço base
    final product = _filteredProducts.firstWhere((p) => p.id == productId);
    final baseSem = _findPrice(product, 'Sem Nota');
    final baseCom = _findPrice(product, 'Com Nota');

    final percent = double.tryParse(value.replaceAll(',', '.')) ?? 0.0;

    final newSem = baseSem + (baseSem * (percent / 100));
    final newCom = baseCom + (baseCom * (percent / 100));

    _individualSemNotaControllers[productId]?.text = _formatPrice(newSem);
    _individualComNotaControllers[productId]?.text = _formatPrice(newCom);
  }

  void _savePrices() async {
    final double? globalSemNota = _parsePrice(_globalSemNotaController.text);
    final double? globalComNota = _parsePrice(_globalComNotaController.text);

    if (globalSemNota == null || globalComNota == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Preços globais inválidos!')));
      return;
    }

    setState(() => _isSaving = true);
    
    List<Map<String, dynamic>> updates = [];

    for (var product in _filteredProducts) {
      double newSemNota;
      double newComNota;

      if (_useGlobalPriceMap[product.id!] == true) {
        newSemNota = globalSemNota;
        newComNota = globalComNota;
      } else {
        newSemNota = _parsePrice(_individualSemNotaControllers[product.id!]!.text) ?? 0;
        newComNota = _parsePrice(_individualComNotaControllers[product.id!]!.text) ?? 0;
      }

      updates.add({
        'id': product.id,
        'semNota': newSemNota,
        'comNota': newComNota,
      });
    }

    try {
      await _firestoreService.batchUpdateCustomPrices(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${updates.length} produtos atualizados!'), backgroundColor: Colors.green));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reajuste de Preços Avançado')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator()) 
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: DropdownButtonFormField<Mold>(
                  decoration: const InputDecoration(labelText: 'Selecione o Molde', border: OutlineInputBorder()),
                  value: _selectedMold,
                  items: _allMolds.map((m) => DropdownMenuItem(value: m, child: Text(m.name))).toList(),
                  onChanged: _onMoldChanged,
                ),
              ),

              if (_selectedMold != null) ...[
                // ===========================================================
                // ÁREA GLOBAL COM PORCENTAGEM
                // ===========================================================
                Container(
                  color: Colors.blue.shade50,
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('REAJUSTE GLOBAL (Para todos marcados)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // CAMPO DE PORCENTAGEM
                          SizedBox(
                            width: 100,
                            child: TextFormField(
                              controller: _globalPercentController,
                              decoration: const InputDecoration(
                                labelText: 'Aplicar %', 
                                suffixText: '%',
                                filled: true, fillColor: Colors.white,
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                              onChanged: _applyGlobalPercentage,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // PREÇOS CALCULADOS
                          Expanded(
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _globalSemNotaController,
                                    decoration: const InputDecoration(labelText: 'Novo S/ Nota', prefixText: 'R\$ ', filled: true, fillColor: Colors.white, isDense: true),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [CurrencyInputFormatter()],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    controller: _globalComNotaController,
                                    decoration: const InputDecoration(labelText: 'Novo C/ Nota', prefixText: 'R\$ ', filled: true, fillColor: Colors.white, isDense: true),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [CurrencyInputFormatter()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text('Digite a % (ex: 5, 10, -5) para calcular automaticamente.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                
                const Divider(height: 1),

                Expanded(
                  child: ListView.separated(
                    itemCount: _filteredProducts.length,
                    separatorBuilder: (ctx, i) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = _filteredProducts[index];
                      final isGlobal = _useGlobalPriceMap[product.id!] ?? true;
                      
                      final currentSem = _findPrice(product, 'Sem Nota');
                      final currentCom = _findPrice(product, 'Com Nota');

                      return Container(
                        color: isGlobal ? null : Colors.orange.shade50, 
                        child: ExpansionTile(
                          leading: Checkbox(
                            value: isGlobal,
                            activeColor: Colors.blue,
                            onChanged: (val) {
                              setState(() {
                                _useGlobalPriceMap[product.id!] = val ?? true;
                              });
                            },
                          ),
                          title: Text(product.name, style: TextStyle(
                            fontWeight: isGlobal ? FontWeight.normal : FontWeight.bold,
                            color: isGlobal ? Colors.black : Colors.deepOrange,
                            fontSize: 14
                          )),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('SKU: ${product.sku}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              Text(
                                'Atual S/Nota: ${_currencyFormatter.format(currentSem)} | Atual C/Nota: ${_currencyFormatter.format(currentCom)}',
                                style: TextStyle(fontSize: 12, color: Colors.grey[800])
                              ),
                              if (isGlobal)
                                const Text('-> Vai usar o preço Global', style: TextStyle(fontSize: 11, color: Colors.blue, fontStyle: FontStyle.italic))
                              else
                                const Text('-> Modo MANUAL ativado', style: TextStyle(fontSize: 11, color: Colors.deepOrange, fontStyle: FontStyle.italic)),
                            ],
                          ),
                          
                          initiallyExpanded: !isGlobal,
                          
                          children: [
                            if (!isGlobal)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Ajuste Individual:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        // ===========================================================
                                        // CAMPO DE PORCENTAGEM INDIVIDUAL
                                        // ===========================================================
                                        SizedBox(
                                          width: 80,
                                          child: TextFormField(
                                            controller: _individualPercentControllers[product.id!],
                                            decoration: const InputDecoration(
                                              labelText: '%', 
                                              filled: true, fillColor: Colors.white,
                                              border: OutlineInputBorder(),
                                              isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 12)
                                            ),
                                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                            onChanged: (val) => _applyIndividualPercentage(product.id!, val),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: _individualSemNotaControllers[product.id!],
                                            decoration: const InputDecoration(
                                              labelText: 'S/ Nota', 
                                              prefixText: 'R\$ ',
                                              border: OutlineInputBorder(),
                                              fillColor: Colors.white, filled: true,
                                              isDense: true
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [CurrencyInputFormatter()],
                                            style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: _individualComNotaControllers[product.id!],
                                            decoration: const InputDecoration(
                                              labelText: 'C/ Nota', 
                                              prefixText: 'R\$ ',
                                              border: OutlineInputBorder(),
                                              fillColor: Colors.white, filled: true,
                                              isDense: true
                                            ),
                                            keyboardType: TextInputType.number,
                                            inputFormatters: [CurrencyInputFormatter()],
                                            style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              )
                            else
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text('Preço travado no padrão global. Desmarque a caixa para editar.', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
                              )
                          ],
                        ),
                      );
                    },
                  ),
                ),
                
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              for (var key in _useGlobalPriceMap.keys) _useGlobalPriceMap[key] = true;
                            });
                          },
                          child: const Text('Marcar Todos (Global)'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          icon: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white)) : const Icon(Icons.save),
                          label: Text(_isSaving ? 'Salvando...' : 'Aplicar Alterações'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
                          onPressed: _isSaving ? null : _savePrices,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
    );
  }
}