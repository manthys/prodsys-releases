// lib/screens/vehicles_screen.dart

import 'package:flutter/material.dart';
import '../models/vehicle_model.dart';
import '../services/firestore_service.dart';

class VehiclesScreen extends StatelessWidget {
  const VehiclesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final FirestoreService firestoreService = FirestoreService();

    void showVehicleDialog({Vehicle? vehicle}) {
      final nameController = TextEditingController(text: vehicle?.name);
      final plateController = TextEditingController(text: vehicle?.plate);
      final driverController = TextEditingController(text: vehicle?.driverName);
      final loadController = TextEditingController(text: vehicle?.maxLoadKg.toString());

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(vehicle == null ? 'Novo Veículo' : 'Editar Veículo'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nome/Modelo (Ex: Fiat Strada)')),
                TextField(controller: plateController, decoration: const InputDecoration(labelText: 'Placa')),
                TextField(controller: driverController, decoration: const InputDecoration(labelText: 'Motorista Padrão')),
                TextField(controller: loadController, decoration: const InputDecoration(labelText: 'Carga Máxima (kg)'), keyboardType: TextInputType.number),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ElevatedButton(
              onPressed: () {
                final v = Vehicle(
                  id: vehicle?.id,
                  name: nameController.text,
                  plate: plateController.text,
                  driverName: driverController.text,
                  maxLoadKg: double.tryParse(loadController.text.replaceAll(',', '.')) ?? 0.0,
                );
                if (vehicle == null) {
                  firestoreService.addVehicle(v);
                } else {
                  firestoreService.updateVehicle(v);
                }
                Navigator.pop(context);
              },
              child: const Text('Salvar'),
            )
          ],
        ),
      );
    }

    return Scaffold(
      // --- CORREÇÃO AQUI: Adicionado AppBar para ter o botão de voltar ---
      appBar: AppBar(
        title: const Text('Gerenciar Veículos'),
      ),
      body: StreamBuilder<List<Vehicle>>(
        stream: firestoreService.getVehiclesStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final vehicles = snapshot.data!;
          
          if (vehicles.isEmpty) {
            return const Center(child: Text('Nenhum veículo cadastrado.'));
          }

          return ListView.builder(
            itemCount: vehicles.length,
            itemBuilder: (context, index) {
              final v = vehicles[index];
              return ListTile(
                leading: const Icon(Icons.local_shipping),
                title: Text(v.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${v.plate} - ${v.driverName} | Max: ${v.maxLoadKg}kg'),
                trailing: IconButton(icon: const Icon(Icons.edit), onPressed: () => showVehicleDialog(vehicle: v)),
                onLongPress: () => firestoreService.deleteVehicle(v.id!),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        child: const Icon(Icons.add),
        onPressed: () => showVehicleDialog(),
      ),
    );
  }
}