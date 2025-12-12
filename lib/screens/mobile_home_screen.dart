// lib/screens/mobile_home_screen.dart (VERSÃO ATUALIZADA COM FAB)

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'mobile_dashboard_screen.dart';
import 'mobile_orders_screen.dart';
import 'mobile_production_stock_screen.dart';
import 'mobile_clients_screen.dart';
import 'mobile_order_form_screen.dart'; // <-- IMPORTAÇÃO DA NOVA TELA

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({super.key});

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();

  final List<String> _titles = [
    'Dashboard',
    'Pedidos',
    'Produção/Estoque',
    'Clientes',
  ];

  final List<Widget> _screens = [
    const MobileDashboardScreen(), 
    const MobileOrdersScreen(),
    const MobileProductionStockScreen(),
    const MobileClientsScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sair',
            onPressed: () async {
              await _authService.signOut();
            },
          ),
        ],
      ),
      body: _screens[_selectedIndex],
      
      // =================================================================
      // BOTÃO DE AÇÃO FLUTUANTE (FAB) ADICIONADO AQUI
      // =================================================================
      floatingActionButton: _selectedIndex == 1 // Mostra o FAB apenas na aba "Pedidos" (índice 1)
        ? FloatingActionButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const MobileOrderFormScreen()),
              );
            },
            tooltip: 'Nova Cotação',
            child: const Icon(Icons.add),
          )
        : null, // Não mostra o FAB nas outras abas
        
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'Início'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), activeIcon: Icon(Icons.receipt_long), label: 'Pedidos'),
          BottomNavigationBarItem(icon: Icon(Icons.precision_manufacturing_outlined), activeIcon: Icon(Icons.precision_manufacturing), label: 'Produção'),
          BottomNavigationBarItem(icon: Icon(Icons.people_outline), activeIcon: Icon(Icons.people), label: 'Clientes'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}