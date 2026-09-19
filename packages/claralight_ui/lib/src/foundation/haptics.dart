import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The channel this package carries its own macOS haptics over.
///
/// Flutter answers `HapticFeedback.vibrate` with "not implemented" on macOS —
/// the taptic engine under every Force Touch trackpad simply is not wired up —
/// so the plugin in `macos/` supplies the half that is missing.
const _macOSHapticsChannel = MethodChannel('dev.claralight.ui/haptics');

/// One crisp tick, for the moment a value clicks into place.
///
/// On macOS this is `NSHapticFeedbackManager`'s alignment pattern, the one the
/// system plays when a dragged window catches a guide: the same event, felt
/// from the other side, as a handle catching a snap point.
///
/// Haptics are a courtesy and never a signal. A Mac with no Force Touch
/// trackpad, a desktop embedder with no haptics at all, or a machine with the
/// feedback switched off in System Settings all stay quiet, and none of that is
/// worth an exception in the middle of a gesture.
Future<void> clSelectionHaptic() async {
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      await _macOSHapticsChannel.invokeMethod<void>('selectionClick');
    } else {
      await HapticFeedback.selectionClick();
    }
  } on MissingPluginException {
    // Either a host that has not regenerated its plugin registration, or a
    // platform whose embedder never implemented haptics in the first place.
  } on PlatformException {
    // Haptics are unavailable on this machine.
  }
}
