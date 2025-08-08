// lib/models/user_model.dart

class UserModel {
  final String uid;
  final String email;
  final String role;
  final String displayName; // <-- NOVO CAMPO

  UserModel({
    required this.uid,
    required this.email,
    required this.role,
    required this.displayName, // <-- NOVO CAMPO
  });

  factory UserModel.fromFirestore(Map<String, dynamic> data, String documentId) {
    return UserModel(
      uid: documentId,
      email: data['email'] ?? '',
      role: data['role'] ?? 'employee',
      displayName: data['displayName'] ?? 'Nome não cadastrado', // <-- NOVO CAMPO
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'role': role,
      'displayName': displayName, // <-- NOVO CAMPO
    };
  }
}