import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(
    const MaterialApp(home: GamepadScreen(), debugShowCheckedModeBanner: false),
  );
}

class GamepadScreen extends StatefulWidget {
  const GamepadScreen({super.key});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  Offset leftStick = Offset.zero;
  Offset rightStick = Offset.zero;
  bool isPressed = false;
  RawDatagramSocket? udpSocket;
  String serverIp = '';
  final int discoveryPort = 4211; // Server discovery port
  final int commandPort = 4210; // Command port
  DateTime lastSendLeft = DateTime.now();
  DateTime lastSendRight = DateTime.now();
  final Duration sendInterval = Duration(milliseconds: 10); 

  @override
  void initState() {
    super.initState();
    _initSocket();
  }

  // Init UDP socket and send discovery message
  void _initSocket() async {
    udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    udpSocket!.broadcastEnabled = true;

    String discoveryMessage = "who-is-pc";
    udpSocket!.send(
      discoveryMessage.codeUnits,
      InternetAddress("255.255.255.255"),
      discoveryPort,
    );

    udpSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = udpSocket!.receive();
        if (datagram == null) return;

        String message = String.fromCharCodes(datagram.data).trim();
        if (message == "esp32-discovery") {
          setState(() {
            // Define the server IP address when the discovery message is received
            serverIp = datagram.address.address;
          });
          print("Servidor descoberto: $serverIp");
        }
        print("message: $message");
      }
    });
  }

  // send UDP message to the server
  void _sendUdpMessage(String message) {
    if (serverIp.isEmpty) return;

    if (udpSocket != null) {
      final int result = udpSocket!.send(
        message.codeUnits,
        InternetAddress(serverIp),
        commandPort,
      );

      if (result > 0) {
        print("Mensagem enviada: $message");
      } else {
        print("Erro ao enviar mensagem ou bloqueio.");
      }
    }
  }

  void _updateStick(Offset localPosition, void Function(Offset) updateFn) {
    final center = const Offset(75, 75);
    final delta = localPosition - center;
    final distance = delta.distance;
    const maxDistance = 50.0;

    if (distance > maxDistance) {
      final angle = atan2(delta.dy, delta.dx);
      updateFn(Offset(cos(angle) * maxDistance, sin(angle) * maxDistance));
    } else {
      updateFn(delta);
    }
  }

  Widget _buildJoystick(
    String side,
    Offset offset,
    void Function(Offset) onUpdate,
  ) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _updateStick(details.localPosition, onUpdate);
        });

        final now = DateTime.now();
        final isLeft = side == 'left';

        if ((isLeft && now.difference(lastSendLeft) > sendInterval) ||
            (!isLeft && now.difference(lastSendRight) > sendInterval)) {
          _sendUdpMessage(
            "X:$side,dx:${offset.dx.toStringAsFixed(2)},dy:${offset.dy.toStringAsFixed(2)}",
          );
          if (isLeft) {
            lastSendLeft = now;
          } else {
            lastSendRight = now;
          }
        }
      },

      onPanEnd: (_) {
        setState(() {
          onUpdate(Offset.zero);
        });
        _sendUdpMessage("X:$side,dx:0,dy:0");
      },
      child: Container(
        width: 150,
        height: 150,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF1E1E2E),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 6,
              offset: const Offset(2, 3),
            ),
          ],
        ),
        child: Stack(
          children: [
            Center(
              child: Transform.translate(
                offset: offset,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF4FC3F7),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.5),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton() {
    return GestureDetector(
      onTap: () {
        setState(() {
          isPressed = true;
        });
        _sendUdpMessage("f");
        Future.delayed(const Duration(milliseconds: 150), () {
          setState(() {
            isPressed = false;
          });
        });
      },
      child: AnimatedScale(
        scale: isPressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 150),
        child: Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: const Color(0xFF3F51B5),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withOpacity(0.5),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(color: Colors.white10, width: 2),
          ),
          child: const Center(
            child: Text(
              "M1",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    double sensitivity = 1.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1C),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 10, right: 10),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  color: const Color(0xFF1E1E2E),
                  onSelected: (value) {
                    if (value == 'Sensitivity') {
                      showDialog(
                        context: context,
                        builder:
                            (_) => AlertDialog(
                              backgroundColor: const Color(0xFF2E2E3E),
                              title: const Text(
                                "Change Sensitivity",
                                style: TextStyle(color: Colors.white),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    sensitivity.toStringAsFixed(2),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                    ),
                                  ),
                                  Slider(
                                    value: sensitivity,
                                    min: 0.1,
                                    max: 3.0,
                                    divisions: 29,
                                    label: sensitivity.toStringAsFixed(2),
                                    onChanged: (value) {
                                      setState(() {
                                        sensitivity = value;
                                      });
                                    },
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text("Close"),
                                ),
                              ],
                            ),
                      );
                    }
                  },
                  itemBuilder:
                      (context) => [
                        const PopupMenuItem(
                          value: 'Sensitivity',
                          child: Text(
                            "Change Sensitivity",
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                ),
              ),
            ),

            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: const Text(
                  "Gamepad",
                  style: TextStyle(
                    fontSize: 30,
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildJoystick(
                  'left',
                  leftStick,
                  (val) => leftStick = val,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: _buildJoystick(
                  'right',
                  rightStick,
                  (val) => rightStick = val,
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 140),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildMenuButton("Select"),
                    const SizedBox(width: 40),
                    _buildMenuButton("Start"),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 55, bottom: 190),
                child: _buildActionButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuButton(String label) {
    return GestureDetector(
      onTap: () {
        if (label == "Start") {
          _sendUdpMessage("p");
        } else if (label == "Select") {
          _sendUdpMessage("s");
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2C2C3E),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 4,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w500,
            fontSize: 16,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
