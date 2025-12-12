// lib/mobile.dart (VERSÃO FINAL SIMPLIFICADA)

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Imports relativos simples para as telas
import 'screens/login_screen.dart';
import 'screens/mobile_home_screen.dart'; 
import 'services/auth_service.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// NÃO PRECISAMOS MAIS DOS ARQUIVOS DE OPÇÕES DO FIREBASE AQUI
// import 'firebase_options_dev.dart' as dev_options;
// import 'firebase_options_prod.dart' as prod_options;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await initializeDateFormatting('pt_BR', null);
  Intl.defaultLocale = 'pt_BR';

  // =================================================================
  // INICIALIZAÇÃO SIMPLIFICADA
  // =================================================================
  // Ao chamar sem "options", o Firebase vai procurar automaticamente
  // o arquivo google-services.json que o "flavor" (dev ou prod) forneceu.
  await Firebase.initializeApp();
  
  runApp(const MobileApp());
}

class MobileApp extends StatelessWidget {
  const MobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProdSys App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('pt', 'BR'),
      ],
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService authService = AuthService();

  @override
  void initState() {
    super.initState();
  }
  
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Vamos mostrar a tela de splash do Flutter aqui
          return const Scaffold(
            body: Center(
              child: FlutterLogo(size: 100),
            ),
          );
        }
        
        if (snapshot.hasData) {
          return MobileHomeScreen(); 
        } else {
          return LoginScreen(); 
        }
      },
    );
  }
}