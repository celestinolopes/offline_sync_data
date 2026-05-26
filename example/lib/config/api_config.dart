import 'dart:io';

/// URL base do json-server local.
///
/// - iOS Simulator / desktop: `localhost`
/// - Android Emulator: `10.0.2.2` (alias do host)
/// - Dispositivo físico: `flutter run --dart-define=API_BASE_URL=http://<IP>:3000`
class ApiConfig {
  ApiConfig._();

  static const entityName = 'tasks';
  static const _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    return Platform.isAndroid
        ? 'http://10.0.2.2:3000'
        : 'http://localhost:3000';
  }

  static String get tasksEndpoint => '$baseUrl/$entityName';
}
