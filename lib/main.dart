import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Trava a tela em paisagem automaticamente (o jogo do print é sempre landscape)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]).then((_) {
    // Modo imersivo: some com a barra de status/navegação pra ganhar espaço
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    runApp(
      const MaterialApp(
        home: GamepadScreen(),
        debugShowCheckedModeBanner: false,
      ),
    );
  });
}

class GamepadScreen extends StatefulWidget {
  const GamepadScreen({super.key});

  @override
  State<GamepadScreen> createState() => _GamepadScreenState();
}

class _GamepadScreenState extends State<GamepadScreen> {
  // ---------------- Analógicos ----------------
  Offset leftStick = Offset.zero;
  Offset rightStick = Offset.zero;

  // Guarda o início do gesto de cada stick pra diferenciar "clique" de "arrastar"
  Offset? _leftDragStart;
  Offset? _rightDragStart;
  static const double _clickMoveTolerance = 8.0;

  // Estado do stick esquerdo convertido em "botões" w/a/s/d (com histerese
  // pra não ficar oscilando D:/U: perto do limiar — isso é o debounce dele).
  final Map<String, bool> _dirHeld = {'w': false, 'a': false, 's': false, 'd': false};

  // ---------------- Rede ----------------
  RawDatagramSocket? udpSocket;
  String serverIp = '';
  bool manualIp = false; // true = usuário digitou o IP na mão, ignora discovery automático
  final int discoveryPort = 4211;
  final int commandPort = 4210;
  Timer? _discoveryTimer;

  DateTime lastSendRight = DateTime.now();
  final Duration sendInterval = const Duration(milliseconds: 10);

  double sensitivity = 1.0;

  @override
  void initState() {
    super.initState();
    _initSocket();
  }

  @override
  void dispose() {
    _discoveryTimer?.cancel();
    udpSocket?.close();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ================= REDE =================

  void _initSocket() async {
    udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    udpSocket!.broadcastEnabled = true;

    _broadcastDiscovery();
    // Tenta de novo a cada 2s até conectar (e continua tentando se cair a conexão)
    _discoveryTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (serverIp.isEmpty && !manualIp) _broadcastDiscovery();
    });

    udpSocket!.listen((event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = udpSocket!.receive();
        if (datagram == null) return;

        String message = String.fromCharCodes(datagram.data).trim();
        if (message == "esp32-discovery" && !manualIp) {
          setState(() {
            serverIp = datagram.address.address;
          });
        }
      }
    });
  }

  void _broadcastDiscovery() {
    udpSocket?.send(
      "who-is-pc".codeUnits,
      InternetAddress("255.255.255.255"),
      discoveryPort,
    );
  }

  void _sendUdpMessage(String message) {
    if (serverIp.isEmpty || udpSocket == null) return;
    udpSocket!.send(message.codeUnits, InternetAddress(serverIp), commandPort);
  }

  // Botão pressionado / solto (protocolo novo: "D:<code>" / "U:<code>")
  void _sendDown(String code) => _sendUdpMessage("D:$code");
  void _sendUp(String code) => _sendUdpMessage("U:$code");

  void _reconnect() {
    setState(() {
      serverIp = '';
      manualIp = false;
    });
    _broadcastDiscovery();
  }

  void _showManualIpDialog() {
    final controller = TextEditingController(text: manualIp ? serverIp : '');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF2E2E3E),
        title: const Text("Conectar manualmente", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "Ex: 192.168.0.15",
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () {
              final ip = controller.text.trim();
              if (ip.isNotEmpty) {
                setState(() {
                  serverIp = ip;
                  manualIp = true;
                });
              }
              Navigator.pop(context);
            },
            child: const Text("Conectar"),
          ),
        ],
      ),
    );
  }

  // ================= STICK ESQUERDO -> W/A/S/D =================
  // Em vez de mandar "X:left,dx,dy" cru (que dependia do server decodificar
  // threshold), agora o proprio app decide quando cada direção deve estar
  // "pressionada" e manda D:/U: igual manda pros botões normais. Usa
  // histerese (limiar de ligar != limiar de desligar) como debounce, pra
  // não ficar chaveando repetido quando o dedo fica bem na borda do limiar.

  void _updateDirKey(String code, bool shouldHold) {
    if (_dirHeld[code] == shouldHold) return;
    _dirHeld[code] = shouldHold;
    if (shouldHold) {
      _sendDown(code);
    } else {
      _sendUp(code);
    }
  }

  void _updateLeftStickKeys(double maxDist) {
    final onThresh = maxDist * 0.35;
    final offThresh = maxDist * 0.20;
    final dx = leftStick.dx;
    final dy = leftStick.dy;

    _updateDirKey('a', _dirHeld['a']! ? dx < -offThresh : dx < -onThresh);
    _updateDirKey('d', _dirHeld['d']! ? dx > offThresh : dx > onThresh);
    _updateDirKey('w', _dirHeld['w']! ? dy < -offThresh : dy < -onThresh);
    _updateDirKey('s', _dirHeld['s']! ? dy > offThresh : dy > onThresh);
  }

  void _releaseAllDirKeys() {
    for (final code in _dirHeld.keys.toList()) {
      _updateDirKey(code, false);
    }
  }

  // ================= STICKS (visual) =================

  void _updateStick(Offset localPosition, double size, void Function(Offset) updateFn) {
    final center = Offset(size / 2, size / 2);
    final delta = localPosition - center;
    final distance = delta.distance;
    final maxDistance = (size / 3) * sensitivity.clamp(0.3, 1.5);

    if (distance > maxDistance) {
      final angle = atan2(delta.dy, delta.dx);
      updateFn(Offset(cos(angle) * maxDistance, sin(angle) * maxDistance));
    } else {
      updateFn(delta);
    }
  }

  Widget _buildJoystick({
    required String side,
    required Offset offset,
    required void Function(Offset) onUpdate,
    required String clickCode,
    required double size,
  }) {
    final isLeft = side == 'left';
    final knobSize = size / 3;
    final maxDist = (size / 3) * sensitivity.clamp(0.3, 1.5);

    return GestureDetector(
      onPanStart: (details) {
        if (isLeft) {
          _leftDragStart = details.localPosition;
        } else {
          _rightDragStart = details.localPosition;
        }
      },
      onPanUpdate: (details) {
        setState(() {
          _updateStick(details.localPosition, size, onUpdate);
        });

        if (isLeft) {
          _updateLeftStickKeys(maxDist);
        } else {
          final now = DateTime.now();
          if (now.difference(lastSendRight) > sendInterval) {
            _sendUdpMessage(
              "X:right,dx:${rightStick.dx.toStringAsFixed(2)},dy:${rightStick.dy.toStringAsFixed(2)}",
            );
            lastSendRight = now;
          }
        }
      },
      onPanEnd: (details) {
        final start = isLeft ? _leftDragStart : _rightDragStart;
        final end = isLeft ? leftStick : rightStick;
        // Se o dedo praticamente não saiu do centro, conta como "clique" do stick
        if (start != null && end.distance < _clickMoveTolerance) {
          _sendDown(clickCode);
          Future.delayed(const Duration(milliseconds: 60), () {
            _sendUp(clickCode);
          });
        }
        if (isLeft) {
          _releaseAllDirKeys();
        } else {
          _sendUdpMessage("X:right,dx:0,dy:0");
        }
        setState(() {
          onUpdate(Offset.zero);
        });
      },
      child: Container(
        width: size,
        height: size,
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
                  width: knobSize,
                  height: knobSize,
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

  // ================= BOTÕES GENÉRICOS =================

  // Botão simples: manda D: no toque e U: ao soltar (o PC decide se foi tap ou hold)
  Widget _buildPressButton({
    required String code,
    required Widget child,
    double size = 60,
    Color color = const Color(0xFF2C2C3E),
    BoxShape shape = BoxShape.circle,
    BorderRadius? borderRadius,
  }) {
    return _PressButton(
      code: code,
      size: size,
      color: color,
      shape: shape,
      borderRadius: borderRadius,
      onDown: _sendDown,
      onUp: _sendUp,
      child: child,
    );
  }

  Widget _label(String text, {double fontSize = 20, Color color = Colors.white}) {
    return Text(
      text,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.bold,
        color: color,
        fontFamily: 'monospace',
      ),
    );
  }

  // Gatilhos (LT/LB, RT/RB) — formato retangular tipo "trigger"
  Widget _buildTrigger(String code, String text, double scale, {Color color = const Color(0xFF3F51B5)}) {
    return _buildPressButton(
      code: code,
      size: 46 * scale,
      color: color,
      shape: BoxShape.rectangle,
      borderRadius: BorderRadius.circular(10 * scale),
      child: Center(child: _label(text, fontSize: 14 * scale)),
    );
  }

  // Botões de face (Y/X/B/A) em losango
  Widget _buildFaceButtons(double scale) {
    final box = 170 * scale;
    final btn = 60 * scale;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 55 * scale,
            child: _buildPressButton(
              code: "Y",
              size: btn,
              color: const Color(0xFFD4A017),
              child: Center(child: _label("Y", fontSize: 20 * scale)),
            ),
          ),
          Positioned(
            top: 55 * scale,
            left: 0,
            child: _buildPressButton(
              code: "X",
              size: btn,
              color: const Color(0xFF3F51B5),
              child: Center(child: _label("X", fontSize: 20 * scale)),
            ),
          ),
          Positioned(
            top: 55 * scale,
            left: 110 * scale,
            child: _buildPressButton(
              code: "B",
              size: btn,
              color: const Color(0xFFC0392B),
              child: Center(child: _label("B", fontSize: 20 * scale)),
            ),
          ),
          Positioned(
            top: 110 * scale,
            left: 55 * scale,
            child: _buildPressButton(
              code: "A",
              size: btn,
              color: const Color(0xFF27AE60),
              child: Center(child: _label("A", fontSize: 20 * scale)),
            ),
          ),
        ],
      ),
    );
  }

  // D-pad (Mark/Emotes, Meds, Itens, Trocar Arma)
  Widget _buildDpad(double scale) {
    final box = 150 * scale;
    final btn = 46 * scale;
    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 52 * scale,
            child: _buildPressButton(
              code: "DU",
              size: btn,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8 * scale),
              child: Center(child: Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 22 * scale)),
            ),
          ),
          Positioned(
            top: 52 * scale,
            left: 0,
            child: _buildPressButton(
              code: "DL",
              size: btn,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8 * scale),
              child: Center(child: Icon(Icons.keyboard_arrow_left, color: Colors.white, size: 22 * scale)),
            ),
          ),
          Positioned(
            top: 52 * scale,
            left: 104 * scale,
            child: _buildPressButton(
              code: "DR",
              size: btn,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8 * scale),
              child: Center(child: Icon(Icons.keyboard_arrow_right, color: Colors.white, size: 22 * scale)),
            ),
          ),
          Positioned(
            top: 104 * scale,
            left: 52 * scale,
            child: _buildPressButton(
              code: "DD",
              size: btn,
              shape: BoxShape.rectangle,
              borderRadius: BorderRadius.circular(8 * scale),
              child: Center(child: Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 22 * scale)),
            ),
          ),
        ],
      ),
    );
  }

  // ================= MENU (engrenagem) com Sensibilidade + M1 escondido + IP manual =================

  void _showSensitivityDialog() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF2E2E3E),
          title: const Text("Sensibilidade", style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(sensitivity.toStringAsFixed(2), style: const TextStyle(color: Colors.white70)),
              Slider(
                value: sensitivity,
                min: 0.3,
                max: 1.5,
                divisions: 24,
                label: sensitivity.toStringAsFixed(2),
                onChanged: (value) {
                  setDialogState(() => sensitivity = value);
                  setState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fechar"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1C),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Fator de escala baseado na altura disponível.
            final scale = (constraints.maxHeight / 380).clamp(0.55, 1.2);

            // Padding horizontal maior: puxa os sticks (e tudo que fica
            // grudado neles) mais pro centro da tela, em vez de ficarem
            // colados na quina.
            final horizontalPad = 34 * scale;
            // Padding vertical do cluster (distância do stick até a base da tela).
            final verticalPad = 16 * scale;
            // D-pad e botões de face ficam um pouco menores que o stick
            // (75% da escala normal) e bem coladinhos nele (gap pequeno),
            // assim eles "descem", ficando longe da fileira de gatilhos.
            final topBtnScale = scale * 0.75;
            final clusterGap = 4 * scale;

            return Stack(
              children: [
                // ---------- Status de conexão (discreto) ----------
                Positioned(
                  top: 6 * scale,
                  left: 10 * scale,
                  child: Row(
                    children: [
                      Container(
                        width: 8 * scale,
                        height: 8 * scale,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: serverIp.isEmpty ? Colors.redAccent : Colors.greenAccent,
                        ),
                      ),
                      SizedBox(width: 6 * scale),
                      Text(
                        serverIp.isEmpty
                            ? "Procurando PC..."
                            : (manualIp ? "$serverIp (manual)" : serverIp),
                        style: TextStyle(color: Colors.white38, fontSize: 11 * scale),
                      ),
                    ],
                  ),
                ),

                // ---------- Menu "..." (sensibilidade + IP manual + reconectar + M1) ----------
                Positioned(
                  top: 0,
                  right: 0,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, color: Colors.white54, size: 22 * scale),
                    color: const Color(0xFF1E1E2E),
                    onSelected: (value) {
                      if (value == 'sensitivity') {
                        _showSensitivityDialog();
                      } else if (value == 'manual_ip') {
                        _showManualIpDialog();
                      } else if (value == 'reconnect') {
                        _reconnect();
                      } else if (value == 'm1') {
                        _sendDown("M1");
                        Future.delayed(const Duration(milliseconds: 60), () => _sendUp("M1"));
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'sensitivity',
                        child: Text("Sensibilidade", style: TextStyle(color: Colors.white70)),
                      ),
                      const PopupMenuItem(
                        value: 'manual_ip',
                        child: Text("Conectar por IP manual", style: TextStyle(color: Colors.white70)),
                      ),
                      const PopupMenuItem(
                        value: 'reconnect',
                        child: Text("Procurar PC de novo", style: TextStyle(color: Colors.white70)),
                      ),
                      const PopupMenuItem(
                        value: 'm1',
                        child: Text("Ativar M1", style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ),
                ),

                // ---------- Gatilhos superiores (um pouco mais pra baixo) ----------
                Positioned(
                  top: 36 * scale,
                  left: horizontalPad,
                  child: Row(
                    children: [
                      _buildTrigger("LT", "LT", scale),
                      SizedBox(width: 8 * scale),
                      _buildTrigger("LB", "LB", scale, color: const Color(0xFF455A64)),
                    ],
                  ),
                ),
                Positioned(
                  top: 36 * scale,
                  right: horizontalPad,
                  child: Row(
                    children: [
                      _buildTrigger("RB", "RB", scale, color: const Color(0xFF455A64)),
                      SizedBox(width: 8 * scale),
                      _buildTrigger("RT", "RT", scale),
                    ],
                  ),
                ),

                // ---------- Botões Map / Menu(Bag) ----------
                Positioned(
                  bottom: 10 * scale,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMenuTextButton("Map", "MAP", scale),
                      SizedBox(width: 30 * scale),
                      _buildMenuTextButton("Menu", "MENU", scale),
                    ],
                  ),
                ),

                // ---------- Cluster esquerdo: D-pad (menor) grudado em cima do stick ----------
                Positioned(
                  left: horizontalPad,
                  bottom: verticalPad,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildDpad(topBtnScale),
                      SizedBox(height: clusterGap),
                      _buildJoystick(
                        side: 'left',
                        offset: leftStick,
                        onUpdate: (val) => leftStick = val,
                        clickCode: 'LCLICK',
                        size: 150 * scale,
                      ),
                    ],
                  ),
                ),

                // ---------- Cluster direito: botões de face (menores) grudados em cima do stick ----------
                Positioned(
                  right: horizontalPad,
                  bottom: verticalPad,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildFaceButtons(topBtnScale),
                      SizedBox(height: clusterGap),
                      _buildJoystick(
                        side: 'right',
                        offset: rightStick,
                        onUpdate: (val) => rightStick = val,
                        clickCode: 'RCLICK',
                        size: 150 * scale,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildMenuTextButton(String label, String code, double scale) {
    return _PressButton(
      code: code,
      size: 0, // ignorado, usamos padding fixo abaixo
      color: const Color(0xFF2C2C3E),
      shape: BoxShape.rectangle,
      borderRadius: BorderRadius.circular(12 * scale),
      onDown: _sendDown,
      onUp: _sendUp,
      customPadding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 10 * scale),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.w500,
          fontSize: 15 * scale,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

// Botão reutilizável que manda D:/U: no press/release, dá feedback visual
// (escala) e tem debounce: ignora onTapDown repetido enquanto já está
// pressionado, ignora onTapUp se já estava solto, e exige um intervalo
// mínimo entre uma troca e outra pra não disparar cliques fantasmas.
class _PressButton extends StatefulWidget {
  final String code;
  final double size;
  final Color color;
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final Widget child;
  final EdgeInsets? customPadding;
  final void Function(String) onDown;
  final void Function(String) onUp;

  const _PressButton({
    required this.code,
    required this.size,
    required this.color,
    required this.shape,
    required this.child,
    required this.onDown,
    required this.onUp,
    this.borderRadius,
    this.customPadding,
  });

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _down = false;
  DateTime _lastChange = DateTime.fromMillisecondsSinceEpoch(0);
  static const _debounce = Duration(milliseconds: 40);

  void _handleDown() {
    if (_down) return; // já pressionado, ignora repique
    final now = DateTime.now();
    if (now.difference(_lastChange) < _debounce) return;
    _lastChange = now;
    setState(() => _down = true);
    widget.onDown(widget.code);
  }

  void _handleUp() {
    if (!_down) return; // já solto, ignora repique
    _lastChange = DateTime.now();
    setState(() => _down = false);
    widget.onUp(widget.code);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _handleDown(),
      onTapUp: (_) => _handleUp(),
      onTapCancel: _handleUp,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: widget.customPadding == null ? widget.size : null,
          height: widget.customPadding == null ? widget.size : null,
          padding: widget.customPadding,
          decoration: BoxDecoration(
            color: widget.color,
            shape: widget.customPadding == null ? widget.shape : BoxShape.rectangle,
            borderRadius: widget.customPadding != null
                ? widget.borderRadius
                : (widget.shape == BoxShape.rectangle ? widget.borderRadius : null),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(color: Colors.white10, width: 1.5),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}