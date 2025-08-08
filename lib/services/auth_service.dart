// lib/services/auth_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<User?> get user => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential?> signInWithEmailAndPassword(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      print(e.toString());
      return null;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  // FUNÇÃO ATUALIZADA para aceitar o nome
  Future<String?> createEmployeeUser(String email, String password, String displayName) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      
      if (userCredential.user != null) {
        // Atualiza o perfil do usuário no Firebase Auth com o nome
        await userCredential.user!.updateDisplayName(displayName);

        // Salva os dados no Firestore
        UserModel newUser = UserModel(
          uid: userCredential.user!.uid,
          email: email,
          role: 'employee',
          displayName: displayName,
        );
        await _db.collection('users').doc(newUser.uid).set(newUser.toJson());
        
        // Recarrega o usuário para garantir que o nome seja atualizado na sessão atual
        await userCredential.user!.reload();
        
        return null;
      }
      return "Não foi possível obter os dados do usuário criado.";
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') return 'A senha fornecida é muito fraca.';
      else if (e.code == 'email-already-in-use') return 'Este email já está em uso.';
      return 'Ocorreu um erro: ${e.message}';
    } catch (e) {
      return 'Ocorreu um erro inesperado.';
    }
  }
  
  Future<String> getUserRole(String uid) async {
    try {
      final doc = await _db.collection('users').doc(uid).get();
      if (doc.exists) {
        return doc.data()?['role'] ?? 'employee';
      }
      return 'employee';
    } catch (e) {
      return 'employee';
    }
  }

  Stream<List<UserModel>> getUsersStream() {
    return _db.collection('users').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => UserModel.fromFirestore(doc.data(), doc.id)).toList();
    });
  }

  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null;
    } on FirebaseAuthException catch (e) {
      return "Erro ao enviar email: ${e.message}";
    } catch (e) {
      return "Ocorreu um erro inesperado.";
    }
  }

  Future<void> updateUserRole(String uid, String newRole) {
    return _db.collection('users').doc(uid).update({'role': newRole});
  }

  Future<String?> deleteUser(String uid) async {
    try {
      await _db.collection('users').doc(uid).delete();
      // Lembrete: A exclusão do Auth() em si ainda é um passo manual no Console do Firebase.
      return null;
    } catch (e) {
      return "Ocorreu um erro ao excluir o usuário do banco de dados.";
    }
  }
}