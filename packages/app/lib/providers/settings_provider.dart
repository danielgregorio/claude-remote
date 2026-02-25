import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// User preferences.
class AppSettings {
  final bool notificationsEnabled;
  final bool notifyOnPermission;
  final bool notifyOnInput;
  final bool notifyOnComplete;
  final bool notifyOnError;
  final bool autoReconnect;

  /// When true, only pinned sessions trigger notifications.
  /// When false, all sessions trigger notifications.
  final bool notifyOnlyPinned;

  const AppSettings({
    this.notificationsEnabled = true,
    this.notifyOnPermission = true,
    this.notifyOnInput = true,
    this.notifyOnComplete = false,
    this.notifyOnError = true,
    this.autoReconnect = true,
    this.notifyOnlyPinned = false,
  });

  AppSettings copyWith({
    bool? notificationsEnabled,
    bool? notifyOnPermission,
    bool? notifyOnInput,
    bool? notifyOnComplete,
    bool? notifyOnError,
    bool? autoReconnect,
    bool? notifyOnlyPinned,
  }) =>
      AppSettings(
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        notifyOnPermission: notifyOnPermission ?? this.notifyOnPermission,
        notifyOnInput: notifyOnInput ?? this.notifyOnInput,
        notifyOnComplete: notifyOnComplete ?? this.notifyOnComplete,
        notifyOnError: notifyOnError ?? this.notifyOnError,
        autoReconnect: autoReconnect ?? this.autoReconnect,
        notifyOnlyPinned: notifyOnlyPinned ?? this.notifyOnlyPinned,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  static const _prefix = 'settings_';
  final FlutterSecureStorage _storage;

  SettingsNotifier({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super(const AppSettings()) {
    _load();
  }

  Future<void> _load() async {
    state = AppSettings(
      notificationsEnabled:
          await _readBool('notifications_enabled', true),
      notifyOnPermission:
          await _readBool('notify_on_permission', true),
      notifyOnInput: await _readBool('notify_on_input', true),
      notifyOnComplete: await _readBool('notify_on_complete', false),
      notifyOnError: await _readBool('notify_on_error', true),
      autoReconnect: await _readBool('auto_reconnect', true),
      notifyOnlyPinned: await _readBool('notify_only_pinned', false),
    );
  }

  Future<bool> _readBool(String key, bool defaultValue) async {
    final value = await _storage.read(key: '$_prefix$key');
    if (value == null) return defaultValue;
    return value == 'true';
  }

  Future<void> _writeBool(String key, bool value) async {
    await _storage.write(key: '$_prefix$key', value: value.toString());
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _writeBool('notifications_enabled', value);
    state = state.copyWith(notificationsEnabled: value);
  }

  Future<void> setNotifyOnPermission(bool value) async {
    await _writeBool('notify_on_permission', value);
    state = state.copyWith(notifyOnPermission: value);
  }

  Future<void> setNotifyOnInput(bool value) async {
    await _writeBool('notify_on_input', value);
    state = state.copyWith(notifyOnInput: value);
  }

  Future<void> setNotifyOnComplete(bool value) async {
    await _writeBool('notify_on_complete', value);
    state = state.copyWith(notifyOnComplete: value);
  }

  Future<void> setNotifyOnError(bool value) async {
    await _writeBool('notify_on_error', value);
    state = state.copyWith(notifyOnError: value);
  }

  Future<void> setAutoReconnect(bool value) async {
    await _writeBool('auto_reconnect', value);
    state = state.copyWith(autoReconnect: value);
  }

  Future<void> setNotifyOnlyPinned(bool value) async {
    await _writeBool('notify_only_pinned', value);
    state = state.copyWith(notifyOnlyPinned: value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
