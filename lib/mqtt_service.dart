import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:uuid/uuid.dart';

class MqttService with ChangeNotifier {
  MqttServerClient? _client;
  String? _deviceId;
  final String _broker = 'ue1f6bff.ala.us-east-1.emqxsl.com';
  final int _port = 8883;
  final String _username = '777042661';
  final String _password = 'mohammed77#7042661';
  final String _mainTopic = 'MyChatApp/ali/inbox';
  String? _responseTopic;

  final StreamController<Map<String, dynamic>> _messageStreamController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageStreamController.stream;

  MqttService() {
    _initialize();
  }

  Future<void> _initialize() async {
    _deviceId = await _getDeviceId();
    if (_deviceId != null) {
      _responseTopic = 'MyChatApp/client/$_deviceId/response';
      _connect();
    }
  }

  Future<String?> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      }
    } catch (e) {
      
    }
    return null;
  }

  void _connect() async {
    if (_deviceId == null) {
      
      return;
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connecting ||
        _client?.connectionStatus?.state == MqttConnectionState.connected) {
      
      return;
    }

    _client = MqttServerClient.withPort(_broker, 'flutter_client_$_deviceId', _port);
    _client!.secure = true;
    _client!.securityContext = SecurityContext.defaultContext;
    _client!.keepAlivePeriod = 60;
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.pongCallback = _pong;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier('flutter_client_$_deviceId')
        .authenticateAs(_username, _password)
        .withWillTopic('willtopic')
        .withWillMessage('My will message')
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMessage;

    try {
      
      await _client!.connect();
    } catch (e) {
      
      _client!.disconnect();
    }
  }
  
  void checkAndReconnect() {
    
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      
      _connect();
    } else {
      
    }
  }

  void _onConnected() {
    
    _client!.subscribe(_responseTopic!, MqttQos.atLeastOnce);

    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
      final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
      final pt = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
      
      try {
        final messageJson = jsonDecode(pt) as Map<String, dynamic>;
        _messageStreamController.add(messageJson);
      } catch (e) {
        
      }
    });
  }

  void _onDisconnected() {
    
  }

  void _onSubscribed(String topic) {
    
  }

  void _pong() {
    
  }

  void publish(Map<String, dynamic> message) {
    if (_client?.connectionStatus?.state != MqttConnectionState.connected) {
      
      // لا تعيد المحاولة تلقائياً هنا، اترك المنطق في الواجهة يقرر إعادة الإرسال
      checkAndReconnect();
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('فشل الإرسال، جارٍ إعادة الاتصال. حاول مرة أخرى بعد قليل.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    message['reply_to'] = _responseTopic;
    message['device_id'] = _deviceId;

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(message));
    _client!.publishMessage(_mainTopic, MqttQos.atLeastOnce, builder.payload!);
  }

  // ==== تم تعديل اسم الدالة لتكون أكثر عمومية ====
  String generateUniqueId() {
    return const Uuid().v4();
  }

  @override
  void dispose() {
    _messageStreamController.close();
    _client?.disconnect();
    super.dispose();
  }
}

// مفتاح عام للوصول إلى ScaffoldMessenger من أي مكان
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();