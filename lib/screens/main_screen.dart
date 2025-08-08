// lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/client_model.dart';
import '../models/expense_model.dart';
import '../models/mold_model.dart';
import '../models/product_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/client_dialog.dart';
import '../widgets/expense_dialog.dart';
import '../widgets/mold_dialog.dart';
import '../widgets/product_dialog.dart';
import '../widgets/stock_item_dialog.dart';
import '../widgets/user_dialog.dart';
import 'clients_screen.dart';
import 'orders_screen.dart';
import 'products_screen.dart';
import 'production_screen.dart';
import 'settings_screen.dart';
import 'expenses_screen.dart';
import 'dashboard_screen.dart';
import 'molds_screen.dart';
import 'stock_screen.dart';
import 'manage_users_screen.dart';
import 'order_form_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  String _userRole = 'employee';
  bool _isLoadingRole = true;

  final List<Widget> _adminScreens = const [DashboardScreen(), OrdersScreen(), ProductionScreen(), StockScreen(), ClientsScreen(), ProductsScreen(), MoldsScreen(), ExpensesScreen(), ManageUsersScreen(), SettingsScreen()];
  final List<String> _adminTitles = const ['Dashboard', 'Cotações e Pedidos', 'Produção Diária', 'Controle de Estoque', 'Clientes', 'Catálogo de Produtos', 'Gerenciar Formas', 'Controle de Gastos', 'Gerenciar Usuários', 'Configurações da Empresa'];
  final List<NavigationRailDestination> _adminDestinations = const [NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Dashboard')), NavigationRailDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: Text('Pedidos')), NavigationRailDestination(icon: Icon(Icons.precision_manufacturing_outlined), selectedIcon: Icon(Icons.precision_manufacturing), label: Text('Produção')), NavigationRailDestination(icon: Icon(Icons.inventory_outlined), selectedIcon: Icon(Icons.inventory), label: Text('Estoque')), NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Clientes')), NavigationRailDestination(icon: Icon(Icons.style_outlined), selectedIcon: Icon(Icons.style), label: Text('Produtos')), NavigationRailDestination(icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman), label: Text('Formas')), NavigationRailDestination(icon: Icon(Icons.money_off_outlined), selectedIcon: Icon(Icons.money_off), label: Text('Gastos')), NavigationRailDestination(icon: Icon(Icons.manage_accounts_outlined), selectedIcon: Icon(Icons.manage_accounts), label: Text('Usuários')), NavigationRailDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: Text('Ajustes'))];
  final List<Widget> _employeeScreens = const [OrdersScreen(), ProductionScreen(), StockScreen(), ClientsScreen()];
  final List<String> _employeeTitles = const ['Cotações e Pedidos', 'Produção Diária', 'Controle de Estoque', 'Clientes'];
  final List<NavigationRailDestination> _employeeDestinations = const [NavigationRailDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: Text('Pedidos')), NavigationRailDestination(icon: Icon(Icons.precision_manufacturing_outlined), selectedIcon: Icon(Icons.precision_manufacturing), label: Text('Produção')), NavigationRailDestination(icon: Icon(Icons.inventory_outlined), selectedIcon: Icon(Icons.inventory), label: Text('Estoque')), NavigationRailDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: Text('Clientes'))];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final user = _authService.currentUser;
    if (user != null) {
      final role = await _authService.getUserRole(user.uid);
      if (mounted) {
        setState(() {
          _userRole = role;
          _isLoadingRole = false;
        });
      }
    } else {
      setState(() => _isLoadingRole = false);
    }
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(context: context, builder: (context) => AlertDialog(title: const Text('Sobre o Sistema'), content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('ProdSys - Sistema de Gestão v1.0.0'), const SizedBox(height: 20), const Text('Desenvolvido por:'), Text('Manthysr', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 10), InkWell(child: Text('Contato: cmanthysr@gmail.com', style: TextStyle(color: Colors.blue, decoration: TextDecoration.underline)), onTap: () => launchUrl(Uri.parse('mailto:cmanthysr@gmail.com')))]), actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fechar'))]));
  }

  Widget? _buildFab(BuildContext fabContext) {
    final bool isAdmin = _userRole == 'admin';
    String? tooltip;
    VoidCallback? onPressed;
    final currentTitle = (isAdmin ? _adminTitles : _employeeTitles)[_selectedIndex];

    switch (currentTitle) {
      case 'Cotações e Pedidos': tooltip = 'Nova Cotação'; onPressed = () => Navigator.of(fabContext).push(MaterialPageRoute(builder: (context) => const OrderFormScreen())); break;
      case 'Clientes': tooltip = 'Adicionar Cliente'; onPressed = () async { final result = await showDialog<Client>(context: fabContext, builder: (_) => const ClientDialog()); if (result != null && mounted) await _firestoreService.addClient(result); }; break;
      case 'Controle de Estoque': tooltip = 'Adicionar Estoque Manual'; onPressed = () async { final result = await showDialog<bool>(context: fabContext, builder: (_) => const StockItemDialog()); if (result == true && mounted) { ScaffoldMessenger.of(fabContext).showSnackBar(const SnackBar(content: Text('Estoque adicionado!'), backgroundColor: Colors.green)); } }; break;
      case 'Catálogo de Produtos': if (isAdmin) { tooltip = 'Adicionar Produto'; onPressed = () async { final result = await showDialog<Product>(context: fabContext, builder: (_) => const ProductDialog()); if (result != null && mounted) await _firestoreService.addProduct(result); }; } break;
      case 'Gerenciar Formas': if (isAdmin) { tooltip = 'Adicionar Forma'; onPressed = () async { final result = await showDialog<Mold>(context: fabContext, builder: (_) => const MoldDialog()); if (result != null && mounted) await _firestoreService.addMold(result); }; } break;
      case 'Controle de Gastos': if (isAdmin) { tooltip = 'Nova Despesa'; onPressed = () async { final result = await showDialog<Expense>(context: fabContext, builder: (_) => const ExpenseDialog()); if (result != null && mounted) await _firestoreService.addExpense(result); }; } break;
      case 'Gerenciar Usuários': if (isAdmin) { tooltip = 'Novo Funcionário'; onPressed = () async { final result = await showDialog<bool>(context: fabContext, builder: (_) => const UserDialog()); if (result == true && mounted) { ScaffoldMessenger.of(fabContext).showSnackBar(const SnackBar(content: Text('Funcionário criado com sucesso!'), backgroundColor: Colors.green)); } }; } break;
    }

    if (onPressed != null) {
      return FloatingActionButton(onPressed: onPressed, tooltip: tooltip, child: const Icon(Icons.add));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool isAdmin = _userRole == 'admin';
    final screens = isAdmin ? _adminScreens : _employeeScreens;
    final titles = isAdmin ? _adminTitles : _employeeTitles;
    final destinations = isAdmin ? _adminDestinations : _employeeDestinations;

    if (_selectedIndex >= screens.length) {
      _selectedIndex = 0;
    }

    final appBarHeight = AppBar().preferredSize.height;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoadingRole ? 'Carregando...' : titles[_selectedIndex]),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              await _authService.signOut();
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: <Widget>[
              if (!_isLoadingRole)
                SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height - appBarHeight - MediaQuery.of(context).padding.top,
                    ),
                    child: IntrinsicHeight(
                      child: NavigationRail(
                        selectedIndex: _selectedIndex,
                        onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
                        labelType: NavigationRailLabelType.all,
                        trailing: Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: IconButton(
                                icon: const Icon(Icons.info_outline),
                                tooltip: 'Sobre o Sistema',
                                onPressed: () => _showAboutDialog(context),
                              ),
                            ),
                          ),
                        ),
                        destinations: destinations,
                      ),
                    ),
                  ),
                ),
              
              if (!_isLoadingRole)
                const VerticalDivider(thickness: 1, width: 1),
              
              Expanded(
                child: _isLoadingRole
                    ? const Center(child: CircularProgressIndicator())
                    : screens[_selectedIndex],
              ),
            ],
          ),

          // ===== ASSINATURA UNIFICADA NO CANTO INFERIOR DIREITO =====
          Positioned(
            bottom: 10,
            right: 10,
            child: InkWell(
              onTap: () => launchUrl(Uri.parse('mailto:cmanthysr@gmail.com')),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.black.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'ProdSys',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    Text(
                      'Powered by Manthysr',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _isLoadingRole ? null : Builder(
        builder: (BuildContext innerContext) {
          return _buildFab(innerContext) ?? const SizedBox.shrink();
        },
      ),
    );
  }
}