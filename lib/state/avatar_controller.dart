import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../avatar/avatar_config.dart';
import '../avatar/avatar_palette.dart';

class AvatarController extends ChangeNotifier {
  static const prefsKey = 'avatar_config';
  AvatarConfig _config;
  AvatarController(this._config);

  AvatarConfig get config => _config;

  ApiClient? _api;
  bool Function()? _loggedIn;

  /// Wire backend sync. [isLoggedIn] gates pushes so we never PATCH while
  /// unauthenticated. Called once from main after the controller loads.
  void attachSync(ApiClient api, bool Function() isLoggedIn) {
    _api = api;
    _loggedIn = isLoggedIn;
  }

  static Future<AvatarController> load() async =>
      AvatarController(await loadConfig());

  /// Also used by the boot splash, which runs before any controller exists —
  /// a prefs failure must degrade to the default livery, never block boot.
  static Future<AvatarConfig> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AvatarConfig.fromJson(prefs.getString(prefsKey));
    } catch (_) {
      return const AvatarConfig();
    }
  }

  /// Selecting a preset discards region tweaks — the chips are starting
  /// points, not a layer under the user's colors.
  Future<void> setPreset(String id) => _save(
      _config.copyWith(presetId: presetById(id).id, overrides: const {}));

  Future<void> setRegionColor(AvatarRegion region, Color color) =>
      _save(_config
          .copyWith(overrides: {..._config.overrides, region: color}));

  /// Back to the plain preset (the builder's reset row).
  Future<void> clearOverrides() =>
      _save(_config.copyWith(overrides: const {}));

  Future<void> setIconVariant(String id) => _save(
      _config.copyWith(iconVariant: AvatarConfig.validIconVariant(id)));

  Future<void> setPose(AvatarPose pose) =>
      _save(_config.copyWith(pose: pose));

  /// Persist a whole config at once — the builder screen edits a local
  /// draft and commits it through here when the user taps SAVE.
  Future<void> save(AvatarConfig config) => _save(config);

  /// Reconcile the local config with the server's stored avatar (from /me).
  /// Server wins when it has one; otherwise a non-default local config seeds
  /// the server once (so existing users' avatars migrate up). Adopting a
  /// server value only persists locally — it never echoes back to the server.
  Future<void> reconcileWithServer(String? serverAvatarJson) async {
    if (serverAvatarJson != null) {
      if (serverAvatarJson != _config.toJson()) {
        _config = AvatarConfig.fromJson(serverAvatarJson);
        notifyListeners();
        await _persistLocal();
      }
      return;
    }
    if (_config.toJson() != const AvatarConfig().toJson()) {
      await _pushToServer();
    }
  }

  Future<void> _save(AvatarConfig next) async {
    _config = next;
    notifyListeners();
    await _persistLocal();
    await _pushToServer();
  }

  Future<void> _persistLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, _config.toJson());
  }

  /// Best-effort: a network/auth failure leaves the local save intact; the
  /// next successful reconcile pushes it up.
  Future<void> _pushToServer() async {
    final api = _api;
    if (api == null || _loggedIn?.call() != true) return;
    try {
      await api.patchMe(avatar: _config.toJson());
    } catch (_) {/* swallowed — local is source of truth until next sync */}
  }
}
