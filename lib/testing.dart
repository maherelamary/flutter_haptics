/// Test doubles for `package:flutter_haptics`.
///
/// Kept out of the main library so the production surface stays the API an
/// app actually calls. Import it only from tests:
///
/// ```dart
/// import 'package:flutter_haptics/flutter_haptics.dart';
/// import 'package:flutter_haptics/testing.dart';
///
/// setUp(() => FlutterHapticsPlatform.instance = FakeHapticsPlatform());
/// tearDown(FlutterHapticsPlatform.reset);
/// ```
library;

export 'src/testing/fake_haptics_platform.dart';
