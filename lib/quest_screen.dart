// --- L'écran de quête (QuestScreen) reste inchangé ---
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// L'écran de quête (QuestScreen) reste inchangé
class QuestScreen extends StatelessWidget {
  final List<ScanResult> players;

  const QuestScreen({super.key, required this.players});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quête de Proximité Déclenchée !')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Préparez-vous pour le défi !',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              'Joueurs détectés : ${players.map((p) => p.device.name.isNotEmpty ? p.device.name : p.device.remoteId.str).join(', ')}',
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Terminer la quête (pour l\'instant)'),
            ),
          ],
        ),
      ),
    );
  }
}
