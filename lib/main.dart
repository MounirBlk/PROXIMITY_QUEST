// ignore_for_file: avoid_print, unused_import
import 'dart:io';
import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:proximity_quest/device_data_source.dart';
import 'package:proximity_quest/quest_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Proximity Quest',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ProximityScannerScreen(),
    );
  }
}

class ProximityScannerScreen extends StatefulWidget {
  const ProximityScannerScreen({super.key});

  @override
  State<ProximityScannerScreen> createState() => _ProximityScannerScreenState();
}

class _ProximityScannerScreenState extends State<ProximityScannerScreen> {
  final FlutterBluePlus flutterBlue = FlutterBluePlus();
  final FlutterBlePeripheral flutterBlePeripheral =
      FlutterBlePeripheral(); // INSTANCE POUR L'ADVERTISING
  List<ScanResult> scanResults = [];
  List<ScanResult> _rawScanResults =
      []; // Nouvelle liste pour les résultats bruts
  bool isScanning = false;
  bool isAdvertising = false; // Nouvel état pour l'advertising
  bool _questActive = false;

  final DeviceDataSource _deviceDataSource = DeviceDataSource();
  String _myDeviceId = ''; // Mon propre ID d'appareil

  // --- UUID de Service Spécifique à Proximity Quest ---
  // C'est l'identifiant que tes applications vont annoncer et scanner.
  static const String GAME_SERVICE_UUID =
      "B27A751F-A6E6-407B-866B-02095F2B57B7";

  @override
  void initState() {
    super.initState();
    _initializeBleRoles(); // Initialise l'ID, le scan ET l'advertising
  }

  // --- Fonction utilitaire pour afficher les SnackBar ---
  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _initializeBleRoles() async {
    _myDeviceId = await _deviceDataSource.getDeviceId();
    print('Mon Device ID: $_myDeviceId');

    // Demande toutes les permissions nécessaires d'abord
    await _requestPermissions();

    // Vérifie l'état du Bluetooth et démarre les rôles
    FlutterBluePlus.adapterState.listen((BluetoothAdapterState state) {
      if (!mounted) return;
      if (state == BluetoothAdapterState.on) {
        print("Bluetooth est ON. Démarrage du scan et de l'advertising.");
        _showSnackBar("Bluetooth activé. Démarrage...");
        _startScan();
        //_startAdvertising();
      } else {
        print("Bluetooth est OFF. Arrêt du scan et de l'advertising.");
        _showSnackBar("Bluetooth désactivé. Arrêt.", isError: true);
        setState(() {
          isScanning = false;
          isAdvertising = false;
        });
        FlutterBluePlus.stopScan();
        //flutterBlePeripheral.stop(); // Arrête l'advertising
      }
    });
  }

  Future<void> _requestPermissions() async {
    // Demande les permissions pour le scan (localisation, appareils à proximité)
    var locationStatus = await Permission.location.request();
    if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
      print('Permission de localisation refusée.');
      _showPermissionDeniedDialog('localisation');
      return;
    }

    // Demande la permission Bluetooth Advertising (Android 12+)
    if (Platform.isAndroid && defaultTargetPlatform == TargetPlatform.android) {
      // Pour Android 12+ (API 31+), BLUETOOTH_ADVERTISE est nécessaire
      if (await Permission.bluetoothAdvertise.request().isDenied) {
        print('Permission Bluetooth Advertise refusée.');
        _showPermissionDeniedDialog('Bluetooth Advertising');
      }
      // BLUETOOTH_SCAN et BLUETOOTH_CONNECT sont aussi importantes pour BLE Central
      if (await Permission.bluetoothScan.request().isDenied) {
        print('Permission Bluetooth Scan refusée.');
        _showPermissionDeniedDialog('Bluetooth Scan');
      }
      if (await Permission.bluetoothConnect.request().isDenied) {
        print('Permission Bluetooth Connect refusée.');
        _showPermissionDeniedDialog('Bluetooth Connect');
      }
    }
    // Assurez-vous que l'état de l'adaptateur Bluetooth est bon
    var adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      print(
        'Bluetooth est désactivé ou les permissions Bluetooth sont refusées: $adapterState',
      );
      _showBluetoothPermissionDialog();
    }
  }

  // --- Gestion de l'Advertising BLE ---
  Future<void> _startAdvertising() async {
    if (isAdvertising) return;

    try {
      // Configure l'annonceur
      AdvertiseData advertiseData = AdvertiseData(
        serviceUuid: GAME_SERVICE_UUID, // L'UUID de notre jeu
        includeDeviceName:
            true, // Inclut le nom de l'appareil (optionnel, mais utile)
        // manufacturerData: { // Exemple d'ajout de données fabricant si tu veux encoder _myDeviceId
        //   1234: Uint8List.fromList(utf8.encode(_myDeviceId.substring(0, 5))) // Exemple: premières 5 chars
        // },
      );
      // Configure les paramètres d'advertising
      AdvertiseSettings advertiseSettings = AdvertiseSettings(
        advertiseMode: AdvertiseMode
            .advertiseModeLowLatency, // Haute fréquence pour détection rapide
        txPowerLevel: AdvertiseTxPower
            .advertiseTxPowerHigh, // Forte puissance pour meilleure portée
        timeout: 0, // Advertising continu (0 = infini, si supporté par l'OS)
      );

      await flutterBlePeripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: advertiseSettings,
      );
      if (mounted) {
        setState(() {
          isAdvertising = true;
        });
        _showSnackBar("Advertising démarré.");
      }
      print("Advertising démarré avec Service UUID: $GAME_SERVICE_UUID");
    } catch (e) {
      print("Erreur au démarrage de l'advertising: $e");
      if (mounted) {
        setState(() {
          isAdvertising = false;
        });
        _showSnackBar(
          "Erreur au démarrage de l'advertising: ${e.toString().split(':')[0].trim()}",
          isError: true,
        );
      }
      _showErrorDialog(
        "Problème d'Advertising",
        "Impossible de démarrer l'advertising BLE. Vérifiez vos permissions et l'état du Bluetooth.\nErreur: ${e.toString()}",
      );
    }
  }

  Future<void> _stopAdvertising() async {
    try {
      await flutterBlePeripheral.stop();
      if (mounted) {
        setState(() {
          isAdvertising = false;
        });
        _showSnackBar("Advertising arrêté.");
      }
      print("Advertising arrêté.");
    } catch (e) {
      print("Erreur à l'arrêt de l'advertising: $e");
      if (mounted) {
        _showSnackBar(
          "Erreur à l'arrêt de l'advertising: ${e.toString().split(':')[0].trim()}",
          isError: true,
        );
      }
    }
  }
  // --- Fin de la gestion de l'Advertising BLE ---

  // --- Gestion du Scan BLE ---
  Future<void> _startScan() async {
    if (isScanning) return;

    setState(() {
      isScanning = true;
      scanResults = [];
      _rawScanResults = []; // Réinitialise la liste brute aussi
    });

    try {
      await FlutterBluePlus.stopScan();

      FlutterBluePlus.startScan(
        withServices: [Guid(GAME_SERVICE_UUID)],
        timeout: const Duration(seconds: 10),
      );

      FlutterBluePlus.scanResults.listen((results) {
        if (!mounted) return;
        setState(() {
          // --- Stocke TOUS les résultats dans _rawScanResults ---
          _rawScanResults = results;
          scanResults = _rawScanResults.where((result) {
            return result.device.remoteId.str.toUpperCase() !=
                _myDeviceId.toUpperCase();
          }).toList();

          final playersInProximity = scanResults
              .where((result) => result.rssi > -70)
              .toList();

          if (playersInProximity.isNotEmpty && !_questActive) {
            print(
              "Au moins un AUTRE joueur Proximity Quest détecté à proximité ! Déclenchement de la quête.",
            );
            _triggerQuest(playersInProximity);
          }
        });
      });

      FlutterBluePlus.isScanning.listen((scanning) {
        if (!mounted) return;
        setState(() {
          isScanning = scanning;
        });
        if (!scanning) {
          print("Scan arrêté. Redémarrage dans 5 secondes...");
          _showSnackBar("Scan arrêté. Redémarrage...");
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted && !isScanning) {
              _startScan();
            }
          });
        }
      });
      _showSnackBar("Scan démarré.");
    } catch (e) {
      print("Erreur au démarrage du scan: $e");
      if (mounted) {
        setState(() {
          isScanning = false;
        });
        _showSnackBar(
          "Erreur au démarrage du scan: ${e.toString().split(':')[0].trim()}",
          isError: true,
        );
      }
      _showErrorDialog(
        "Problème de Scan",
        "Impossible de démarrer le scan BLE. Vérifiez vos permissions et l'état du Bluetooth.\nErreur: ${e.toString()}",
      );
    }
  }
  // --- Fin de la gestion du Scan BLE ---

  void _triggerQuest(List<ScanResult> players) {
    _questActive = true;

    // Arrêter le scan et l'advertising pendant la quête pour économiser la batterie
    //_stopAdvertising();
    FlutterBluePlus.stopScan();

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => QuestScreen(players: players)),
    ).then((_) {
      // Une fois que l'utilisateur quitte la QuestScreen, réinitialise l'état
      _questActive = false;
      _startScan(); // Redémarre le scan
      //_startAdvertising(); // Redémarre l'advertising
    });
  }

  void _showBluetoothPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Bluetooth Requis"),
          content: const Text(
            "Veuillez activer le Bluetooth et accorder les permissions pour que l'application puisse fonctionner.",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showPermissionDeniedDialog(String permissionType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Permission de $permissionType Refusée"),
          content: Text(
            "L'application a besoin de la permission de $permissionType pour fonctionner correctement. Veuillez l'activer dans les paramètres de votre appareil.",
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    FlutterBluePlus.stopScan();
    //flutterBlePeripheral.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proximity Quest'),
        actions: [
          IconButton(
            icon: Icon(isScanning ? Icons.stop : Icons.play_arrow),
            onPressed: isScanning ? FlutterBluePlus.stopScan : _startScan,
            tooltip: 'Toggle Scan',
          ),
          /*IconButton(
            icon: Icon(isAdvertising ? Icons.wifi : Icons.wifi_off),
            onPressed: isAdvertising ? _stopAdvertising : _startAdvertising,
            tooltip: 'Toggle Advertising',
          ),*/
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Mon ID d\'appareil: $_myDeviceId',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Statut: ${isAdvertising ? 'Annonceur ON' : 'Annonceur OFF'} | ${isScanning ? 'Scanner ON' : 'Scanner OFF'}',
              style: TextStyle(
                color: (isAdvertising && isScanning)
                    ? Colors.green
                    : Colors.red,
              ),
            ),
          ),
          const Divider(),
          // Toggle Button pour choisir entre les résultats bruts et filtrés
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _showRawResults = !_showRawResults; // Inverse l'état
                });
              },
              child: Text(
                _showRawResults
                    ? 'Afficher joueurs détectés'
                    : 'Afficher TOUS les appareils (brut)',
              ),
            ),
          ),
          Expanded(
            child: _showRawResults
                ? (_rawScanResults.isEmpty
                      ? Center(
                          child: Text(
                            isScanning
                                ? 'Recherche d\'appareils bruts...'
                                : 'Aucun appareil brut détecté.',
                          ),
                        )
                      : ListView.builder(
                          itemCount: _rawScanResults.length,
                          itemBuilder: (context, index) {
                            final result = _rawScanResults[index];
                            return Card(
                              margin: const EdgeInsets.all(8.0),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Appareil: ${result.device.name.isNotEmpty ? result.device.name : 'Inconnu'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text('ID: ${result.device.remoteId.str}'),
                                    Text('RSSI: ${result.rssi} dBm'),
                                    // Afficher les services UUID détectés
                                    if (result
                                        .advertisementData
                                        .serviceUuids
                                        .isNotEmpty)
                                      Text(
                                        'Services: ${result.advertisementData.serviceUuids.map((g) => g.str.substring(4, 8)).join(', ')}',
                                      ) // Affiche une partie de l'UUID pour la lisibilité
                                    else
                                      const Text('Services: Aucun'),
                                    // Indiquer si cet appareil est censé être un joueur
                                    if (result.advertisementData.serviceUuids
                                        .contains(GAME_SERVICE_UUID))
                                      const Text(
                                        'Ceci est un appareil Proximity Quest !',
                                        style: TextStyle(
                                          color: Colors.blueAccent,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ))
                : (scanResults.isEmpty
                      ? Center(
                          child: Text(
                            isScanning
                                ? 'Recherche d\'autres joueurs de Proximity Quest...'
                                : 'Aucun autre joueur Proximity Quest détecté.',
                          ),
                        )
                      : ListView.builder(
                          itemCount: scanResults.length,
                          itemBuilder: (context, index) {
                            final result = scanResults[index];
                            return Card(
                              margin: const EdgeInsets.all(8.0),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Joueur: ${result.device.name.isNotEmpty ? result.device.name : 'Inconnu'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text('ID: ${result.device.remoteId.str}'),
                                    Text('RSSI: ${result.rssi} dBm'),
                                    if (result.rssi > -60)
                                      const Text(
                                        'Statut: Très Proche !',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    else if (result.rssi > -75)
                                      const Text(
                                        'Statut: Proche',
                                        style: TextStyle(color: Colors.orange),
                                      )
                                    else
                                      const Text('Statut: Éloigné'),
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
          ),
        ],
      ),
    );
  }

  // Nouvelle variable d'état pour le toggle
  bool _showRawResults = false;
}
