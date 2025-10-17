import 'dart:async';

import 'package:router_os_client/router_os_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MikrotikCredentialsMissingException implements Exception {
  final String message;
  MikrotikCredentialsMissingException(this.message);

  @override
  String toString() => 'MikrotikCredentialsMissingException: $message';
}

class MikrotikConnectionException implements Exception {
  final String message;
  final dynamic originalException;
  MikrotikConnectionException(this.message, [this.originalException]);

  @override
  String toString() => 'MikrotikConnectionException: $message';
}

class MikrotikConnector {
  static Future<RouterOSClient> connect() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('ip');
    final user = prefs.getString('user');
    final pass = prefs.getString('pass');
    final portString = prefs.getString('port');
    final port = portString != null ? (int.tryParse(portString) ?? 8728) : 8728;

    if (ip == null || user == null || pass == null) {
      throw MikrotikCredentialsMissingException('IP address, username, or password are not set.');
    }

    final client = RouterOSClient(
      address: ip,
      user: user,
      password: pass,
      port: port,
      verbose: true,
    );

    try {
      final bool loggedIn = await client.login().timeout(const Duration(seconds: 10));
      if (loggedIn) {
        return client;
      } else {
        throw MikrotikConnectionException('Login failed.');
      }
    } on TimeoutException {
      throw MikrotikConnectionException('Connection timed out.');
    } catch (e) {
      throw MikrotikConnectionException('An unexpected error occurred.', e);
    }
  }
}