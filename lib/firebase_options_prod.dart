// lib/firebase_options.dart
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        // Vamos adicionar a configuração do Android aqui no futuro
        throw UnsupportedError('Plataforma não suportada ainda');
      case TargetPlatform.iOS:
        throw UnsupportedError('Plataforma não suportada ainda');
      case TargetPlatform.macOS:
        throw UnsupportedError('Plataforma não suportada ainda');
      case TargetPlatform.windows:
        return windows; // Usaremos a configuração do Windows
      case TargetPlatform.linux:
        throw UnsupportedError('Plataforma não suportada ainda');
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: "AIzaSyDliz2SPerLmIBsTMZKIFqt79c9nUk74dQ",
    appId: "1:1064736531393:web:dec4b37beb27718de00540",
    messagingSenderId: "1064736531393",
    projectId: "sistema-gestao-cliente",
    authDomain: "sistema-gestao-cliente.firebaseapp.com",
    storageBucket: "sistema-gestao-cliente.firebasestorage.app",
  );
}