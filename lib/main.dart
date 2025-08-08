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
  late String _updateUrl;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    const String githubUser = 'manthys';
    const String repoName = 'prodsys-releases';
    // A URL para o auto_updater deve apontar para o feed de releases
    _updateUrl = 'https://github.com/$githubUser/$repoName/releases/latest/download/appcast.xml';

    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version;

      final response = await http.get(Uri.parse('https://api.github.com/repos/$githubUser/$repoName/releases/latest'));
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final latestVersion = (json['tag_name'] as String).replaceAll('v', '');
        
        if (_isUpdateAvailable(currentVersion, latestVersion)) {
          _showUpdateDialog(latestVersion);
        }
      }
    } catch (e) {
      print('Erro ao verificar atualização: $e');
    }
  }
  
  bool _isUpdateAvailable(String currentVersion, String latestVersion) {
    return currentVersion.compareTo(latestVersion) < 0;
  }

  void _showUpdateDialog(String newVersion) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Atualização Disponível!'),
          content: Text('Uma nova versão ($newVersion) do ProdSys está disponível. O programa será fechado para ser atualizado.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Depois'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // ===== CÓDIGO CORRIGIDO AQUI =====
                await autoUpdater.setFeedURL(_updateUrl);
                await autoUpdater.checkForUpdates(inBackground: false);
                // O pacote cuidará de fechar e instalar
              },
              child: const Text('Atualizar e Reiniciar'),
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