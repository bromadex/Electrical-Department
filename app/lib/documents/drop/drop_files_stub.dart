import 'dart:typed_data';

/// Phones have no drag and drop; nothing to listen for.
Object? listenForDrops({
  required void Function(bool over) onOver,
  required void Function(List<({String name, Uint8List bytes})> files) onDrop,
}) => null;

void stopListening(Object? handle) {}
