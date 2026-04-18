import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class WsService {
  WebSocketChannel? _channel;
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();
  bool _connected = false;
  Timer? _reconnectTimer;

  Stream<Map<String, dynamic>> get events => _eventController.stream;
  bool get connected => _connected;

  void connect() {
    final uri = Uri.parse('${AppConfig.wsUrl}?token=${AppConfig.authToken}');
    _channel = WebSocketChannel.connect(uri);
    _connected = true;

    _channel!.stream.listen(
      (data) {
        try {
          final event = jsonDecode(data as String) as Map<String, dynamic>;
          _eventController.add(event);
        } catch (_) {}
      },
      onDone: () {
        _connected = false;
        _eventController.add({'type': 'disconnected'});
        _scheduleReconnect();
      },
      onError: (e) {
        _connected = false;
        _scheduleReconnect();
      },
    );
  }

  void subscribe(String sessionId) {
    _send({'action': 'subscribe', 'sessionId': sessionId});
  }

  void unsubscribe() {
    _send({'action': 'unsubscribe'});
  }

  void sendPrompt(String sessionId, String content) {
    _send({'action': 'prompt', 'sessionId': sessionId, 'content': content});
  }

  void _send(Map<String, dynamic> data) {
    if (_channel != null && _connected) {
      _channel!.sink.add(jsonEncode(data));
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _eventController.close();
  }
}
