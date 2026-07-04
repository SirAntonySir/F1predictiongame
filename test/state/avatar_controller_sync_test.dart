import 'package:flutter_test/flutter_test.dart';
import 'package:predictiongame/api/api_client.dart';
import 'package:predictiongame/api/models/user.dart';
import 'package:predictiongame/avatar/avatar_config.dart';
import 'package:predictiongame/avatar/avatar_palette.dart';
import 'package:predictiongame/state/avatar_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Records patchMe calls; everything else is unimplemented (the controller
/// only ever calls patchMe).
class _FakeApi implements ApiClient {
  final List<String?> patchedAvatars = [];
  @override
  Future<User> patchMe({String? displayName, String? avatar}) async {
    patchedAvatars.add(avatar);
    return User(
        id: 'u', email: 'e@x.com', displayName: 'U',
        avatar: avatar, createdAt: DateTime(2026));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('save pushes the config to the server when logged in', () async {
    final api = _FakeApi();
    final c = await AvatarController.load();
    c.attachSync(api, () => true);

    await c.setPreset('bolt');
    expect(api.patchedAvatars.length, 1);
    expect(api.patchedAvatars.single, c.config.toJson());
  });

  test('save does not push when logged out', () async {
    final api = _FakeApi();
    final c = await AvatarController.load();
    c.attachSync(api, () => false);

    await c.setPreset('bolt');
    expect(api.patchedAvatars, isEmpty);
  });

  test('reconcile adopts the server avatar (server wins)', () async {
    final api = _FakeApi();
    final c = await AvatarController.load();
    c.attachSync(api, () => true);

    final server =
        const AvatarConfig(presetId: 'verde', pose: AvatarPose.pose2).toJson();
    await c.reconcileWithServer(server);

    expect(c.config.presetId, 'verde');
    expect(c.config.pose, AvatarPose.pose2);
    // Adopting a server value must not echo back to the server.
    expect(api.patchedAvatars, isEmpty);
    // And it persists locally.
    final reloaded = await AvatarController.load();
    expect(reloaded.config.presetId, 'verde');
  });

  test('reconcile seeds a non-default local config up when server has none',
      () async {
    final api = _FakeApi();
    SharedPreferences.setMockInitialValues({
      AvatarController.prefsKey:
          const AvatarConfig(presetId: 'papaya').toJson(),
    });
    final c = await AvatarController.load();
    c.attachSync(api, () => true);

    await c.reconcileWithServer(null);
    expect(api.patchedAvatars.single, c.config.toJson());
  });

  test('reconcile does not seed a default local config', () async {
    final api = _FakeApi();
    final c = await AvatarController.load(); // default undercut
    c.attachSync(api, () => true);

    await c.reconcileWithServer(null);
    expect(api.patchedAvatars, isEmpty);
  });
}
