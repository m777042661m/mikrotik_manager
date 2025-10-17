import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/services.dart';

import 'package:router_os_client/router_os_client.dart';

import 'mikrotik_connector.dart';

class BulkAddIsolateData {
  final SendPort sendPort;
  final int count;
  final int length;
  final String prefix;
  final String sharedUsers;
  final String? selectedProfile;
  final String charType;
  final String cardType;
  final bool linkPasswordToFirstUser;
  final bool isVersion7OrNewer;
  final RootIsolateToken rootIsolateToken;
  final String customer;

  BulkAddIsolateData({
    required this.sendPort,
    required this.count,
    required this.length,
    required this.prefix,
    required this.sharedUsers,
    required this.selectedProfile,
    required this.charType,
    required this.cardType,
    required this.linkPasswordToFirstUser,
    required this.isVersion7OrNewer,
    required this.rootIsolateToken,
    required this.customer,
  });
}

void bulkAddIsolate(BulkAddIsolateData data) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(data.rootIsolateToken);
  final sendPort = data.sendPort;
  int successCount = 0;
  final List<Map<String, String>> newlyCreatedUsers = [];
  String firstGeneratedUsername = '';

  RouterOSClient? client;
  try {
    client = await MikrotikConnector.connect();

    for (int i = 0; i < data.count; i++) {
      final randomPartLength = data.length - data.prefix.length;
      if (randomPartLength < 1) {
        throw Exception('Prefix length cannot be longer than the total length.');
      }

      final username =
          data.prefix + _generateRandomString(randomPartLength, data.charType);

      String password = "";
      if (data.linkPasswordToFirstUser && i == 0) {
        firstGeneratedUsername = username;
        password = firstGeneratedUsername;
      } else if (data.linkPasswordToFirstUser && i > 0) {
        password = firstGeneratedUsername;
      } else if (data.cardType == 'username_and_password_equal') {
        password = username;
      } else if (data.cardType == 'username_and_password_different') {
        password = _generateRandomString(randomPartLength, data.charType);
      }

      final List<String> addUserCommand = [
        '/tool/user-manager/user/add',
        '=username=$username',
        '=password=$password',
        '=shared-users=${data.sharedUsers}',
      ];
      if (!data.isVersion7OrNewer) {
        addUserCommand.add('=customer=${data.customer}');
      }
      await client.talk(addUserCommand);

      await client.talk([
        '/tool/user-manager/user/create-and-activate-profile',
        '=customer=${data.customer}',
        '=numbers=$username',
        '=profile=${data.selectedProfile}',
      ]);

      newlyCreatedUsers.add({'username': username, 'password': password});
      successCount++;

      sendPort.send({'type': 'progress', 'progress': (i + 1) / data.count, 'status': 'Generating user ${i + 1} of ${data.count}'});
    }

    sendPort.send({'type': 'success', 'users': newlyCreatedUsers, 'count': successCount, 'address': client.address});
  } on MikrotikCredentialsMissingException catch (e) {
    sendPort.send({'type': 'error', 'message': 'خطأ في بيانات الدخول: ${e.message}', 'count': successCount});
  } on MikrotikConnectionException catch (e) {
    sendPort.send({'type': 'error', 'message': 'خطأ في الاتصال: ${e.message}', 'count': successCount});
  } on TimeoutException {
    sendPort.send({'type': 'error', 'message': 'فشل الاتصال بالراوتر (انتهت مهلة الاتصال).', 'count': successCount});
  } catch (e) {
    sendPort.send({'type': 'error', 'message': e.toString(), 'count': successCount});
  } finally {
    client?.close();
  }
}

String _generateRandomString(int length, String type) {
  const charsMixed = 'abcdefghijklmnopqrstuvwxyz0123456789';
  const charsLetters = 'abcdefghijklmnopqrstuvwxyz';
  const charsNumbers = '0123456789';
  String chars;
  switch (type) {
    case 'letters':
      chars = charsLetters;
      break;
    case 'numbers':
      chars = charsNumbers;
      break;
    default:
      chars = charsMixed;
  }
  return String.fromCharCodes(Iterable.generate(
      length, (_) => chars.codeUnitAt(Random().nextInt(chars.length))));
}
