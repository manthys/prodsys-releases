// lib/main.dart

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Imports para o atualizador
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:auto_updater/auto_updater.dart';
import 'package:version/version.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ProdSys',
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
  bool _isCheckingForUpdate = false; // Trava para evitar múltiplas verificações

  @override
  void initState() {
    super.initState();
    _initiateUpdateCheck();
  }

  void _initiateUpdateCheck() {
    // Adiciona um atraso para dar tempo ao app de se estabilizar
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _checkForUpdates();
      }
    });
  }
  
  Future<void> _checkForUpdates() async {
    // Se já estiver verificando, não faz nada
    if (_isCheckingForUpdate) return;
    setState(() => _isCheckingForUpdate = true);

    const String githubUser = 'manthys';
    const String repoName = 'prodsys-releases';
    final url = Uri.parse('https://api.github.com/repos/$githubUser/$repoName/releases/latest');

    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersionStr = packageInfo.version;

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final latestVersionStr = (json['tag_name'] as String).replaceAll('v', '');
        
        if (json['assets'] != null && (json['assets'] as List).isNotEmpty) {
          final downloadUrl = json['assets'][0]['browser_download_url'];

          final currentVersion = Version.parse(currentVersionStr);
          final latestVersion = Version.parse(latestVersionStr);
          
          print('--- Verificação de Atualização ---');
          print('Versão Instalada: $currentVersion');
          print('Última Versão no GitHub: $latestVersion');
          
          if (latestVersion > currentVersion) {
            print('Nova versão encontrada! Mostrando diálogo...');
            _showUpdateDialog(latestVersionStr, downloadUrl);
          } else {
            print('O software já está atualizado.');
          }
        }
      }
    } catch (e) {
      print('Erro ao verificar atualização: $e');
    } finally {
      if(mounted) {
        setState(() => _isCheckingForUpdate = false);
      }
    }
  }
  
  void _showUpdateDialog(String newVersion, String downloadUrl) async {
    // ===== VERIFICAÇÃO DE SEGURANÇA FINAL =====
    // Re-verifica a versão do pacote imediatamente antes de mostrar o diálogo
    final packageInfo = await PackageInfo.fromPlatform();
    if (packageInfo.version == newVersion) {
      print('VERIFICAÇÃO FINAL: A versão já é a mais recente. Abortando diálogo de atualização.');
      return; // Aborta a exibição do pop-up se a versão já for a correta.
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Atualização Disponível!'),
          content: Text('Uma nova versão ($newVersion) do ProdSys está disponível. Deseja baixar e instalar agora?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Depois'),
            ),
            ElevatedButton(
              onPressed: () async {
                final feedURL = 'https://github.com/manthys/prodsys-releases/releases/latest/download/appcast.xml';
                await autoUpdater.setFeedURL(feedURL);
                await autoUpdater.checkForUpdates(inBackground: false);
                Navigator.of(context).pop();
              },
              child: const Text('Atualizar Agora'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: authService.user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        
        if (snapshot.hasData) {
          return const MainScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}