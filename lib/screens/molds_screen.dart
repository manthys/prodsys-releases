// lib/screens/molds_screen.dart
import 'package:flutter/material.dart';
import '../models/mold_model.dart';
import '../services/firestore_service.dart';
import '../widgets/mold_dialog.dart';

class MoldsScreen extends StatelessWidget {
  const MoldsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    void showMoldDialog({Mold? mold}) async {
      final result = await showDialog<Mold>(
        context: context,
        builder: (context) => MoldDialog(mold: mold),
      );
      if (result != null) {
        if (mold == null) {
          await firestoreService.addMold(result);
        } else {
          await firestoreService.updateMold(result);
        }
      }
    }

    void confirmDelete(Mold mold) async {
       final bool? confirmar = await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirmar Exclusão'),
          content: Text('Tem certeza que deseja excluir a forma "${mold.name}"?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Não')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Sim, Excluir')),
          ],
        ),
      );
      if (confirmar == true) {
        await firestoreService.deleteMold(mold.id!);
      }
    }

    return Scaffold(
      body: StreamBuilder<List<Mold>>(
        stream: firestoreService.getMoldsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Nenhuma forma cadastrada.'));
          }

          final molds = snapshot.data!;
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: molds.length,
            itemBuilder: (context, index) {
              final mold = molds[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Text(mold.quantityAvailable.toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  title: Text(mold.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Formas disponíveis'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.grey),
                    onPressed: () => confirmDelete(mold),
                  ),
                  onTap: () => showMoldDialog(mold: mold),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showMoldDialog(),
        tooltip: 'Adicionar Forma',
        child: const Icon(Icons.add),
      ),
    );
  }
}