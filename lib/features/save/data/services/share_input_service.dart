import 'dart:async';

import 'package:share_handler/share_handler.dart';

class ShareInputService {
  final StreamController<Object?> _shareEvents = StreamController<Object?>.broadcast();
  Stream<Object?> get shareEvents => _shareEvents.stream;

  final _share = ShareHandler.instance;

  Future<void> init() async {
    final initial = await _share.getInitialSharedMedia();
    if (initial != null) _emitShare(initial);
    _share.sharedMediaStream.listen((media) {
      _emitShare(media);
    });
  }

  void _emitShare(SharedMedia media) {
    final content = media.content?.trim() ?? '';
    if (content.isEmpty) return;
    _shareEvents.add(content);
  }
}
