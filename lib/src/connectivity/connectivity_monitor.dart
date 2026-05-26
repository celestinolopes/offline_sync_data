import 'dart:async';

import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Provides network availability signals to the synchronization manager.
abstract class ConnectivityMonitor {
  Future<bool> get isConnected;

  Stream<bool> get onConnectivityChanged;
}

/// Verifies real internet reachability via [internet_connection_checker_plus].
///
/// Unlike interface-only checks (Wi-Fi without routing), this probes global
/// endpoints (or [customCheckOptions]) with subsecond HEAD requests. See the
/// [package documentation](https://pub.dev/packages/internet_connection_checker_plus).
class InternetConnectionMonitor implements ConnectivityMonitor {
  InternetConnectionMonitor({
    InternetConnection? connection,
    Duration checkInterval = const Duration(milliseconds: 500),
    List<InternetCheckOption>? customCheckOptions,
    bool useDefaultOptions = true,
    bool enableStrictCheck = false,
    ConnectivityCheckCallback? customConnectivityCheck,
    Future<bool> Function()? hasInternetAccessOverride,
    Stream<InternetStatus>? statusChangesOverride,
  })  : _connection = connection ??
            InternetConnection.createInstance(
              checkInterval: checkInterval,
              customCheckOptions: customCheckOptions,
              useDefaultOptions: useDefaultOptions,
              enableStrictCheck: enableStrictCheck,
              customConnectivityCheck: customConnectivityCheck,
            ),
        _hasInternetAccessOverride = hasInternetAccessOverride,
        _statusChangesOverride = statusChangesOverride;

  final InternetConnection _connection;
  final Future<bool> Function()? _hasInternetAccessOverride;
  final Stream<InternetStatus>? _statusChangesOverride;

  /// Interval between background checks while [onConnectivityChanged] has
  /// listeners. Defaults to 500 milliseconds.
  Duration get checkInterval => _connection.checkInterval;

  @override
  Future<bool> get isConnected =>
      _hasInternetAccessOverride?.call() ?? _connection.hasInternetAccess;

  @override
  Stream<bool> get onConnectivityChanged => (_statusChangesOverride ??
          _connection.onStatusChange)
      .map((status) => status == InternetStatus.connected)
      .distinct();
}

/// @nodoc
@Deprecated('Use [InternetConnectionMonitor] instead.')
typedef ConnectivityPlusMonitor = InternetConnectionMonitor;
