import 'dart:js_interop';

@JS('playChime')
external void _jsPlayChime();

class SoundService {
  static void playChime() {
    try {
      _jsPlayChime();
    } catch (_) {}
  }
}
