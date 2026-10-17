import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';

/// Real protocol pings performed from the phone itself:
/// Java Server List Ping (TCP) and Bedrock RakNet unconnected ping (UDP).
class MinecraftPing {
  const MinecraftPing._();

  static const Duration _timeout = Duration(seconds: 5);

  static Future<PingResult> java({required String host, required int port}) async {
    final Stopwatch watch = Stopwatch()..start();
    Socket? socket;
    _SocketReader? reader;
    try {
      socket = await Socket.connect(host, port, timeout: _timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      reader = _SocketReader(socket);

      final BytesBuilder handshake = BytesBuilder();
      _writeVarInt(handshake, 0x00);
      _writeVarInt(handshake, 767); // protocol version; servers answer regardless
      final Uint8List hostBytes = Uint8List.fromList(utf8.encode(host));
      _writeVarInt(handshake, hostBytes.length);
      handshake.add(hostBytes);
      handshake.add(<int>[(port >> 8) & 0xFF, port & 0xFF]);
      _writeVarInt(handshake, 1);
      final Uint8List payload = handshake.toBytes();
      final BytesBuilder packet = BytesBuilder();
      _writeVarInt(packet, payload.length);
      packet.add(payload);
      socket.add(packet.toBytes());

      final BytesBuilder statusRequest = BytesBuilder();
      _writeVarInt(statusRequest, 1);
      _writeVarInt(statusRequest, 0x00);
      socket.add(statusRequest.toBytes());
      await socket.flush();

      final int packetLength = await reader.readVarInt();
      if (packetLength <= 0) throw const FormatException('Empty status packet');
      final int packetId = await reader.readVarInt();
      if (packetId != 0) throw FormatException('Unexpected packet id $packetId');
      final int jsonLength = await reader.readVarInt();
      final Uint8List jsonBytes = await reader.readExact(jsonLength);
      final dynamic decoded = jsonDecode(utf8.decode(jsonBytes, allowMalformed: true));

      Map<String, dynamic> players = <String, dynamic>{};
      Map<String, dynamic> version = <String, dynamic>{};
      String motd = '';
      if (decoded is Map) {
        if (decoded['players'] is Map) players = Map<String, dynamic>.from(decoded['players'] as Map);
        if (decoded['version'] is Map) version = Map<String, dynamic>.from(decoded['version'] as Map);
        final Object? description = decoded['description'];
        if (description is String) {
          motd = description;
        } else if (description is Map) {
          motd = description['text']?.toString() ?? '';
        }
      }
      watch.stop();
      return PingResult(
        online: true,
        latencyMs: watch.elapsedMilliseconds,
        playersOnline: (players['online'] as num?)?.toInt(),
        playersMax: (players['max'] as num?)?.toInt(),
        motd: _stripFormatting(motd),
        version: version['name']?.toString() ?? '',
      );
    } catch (error) {
      watch.stop();
      return PingResult(online: false, latencyMs: watch.elapsedMilliseconds, error: error.toString());
    } finally {
      try {
        await reader?.dispose();
      } catch (_) {
        // reader already disposed
      }
      try {
        await socket?.close();
      } catch (_) {
        // socket already closed
      }
    }
  }

  static Future<PingResult> bedrock({required String host, required int port}) async {
    final Stopwatch watch = Stopwatch()..start();
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final List<int> magic = <int>[
        0x00, 0xff, 0xff, 0x00, 0xfe, 0xfe, 0xfe, 0xfe,
        0xfd, 0xfd, 0xfd, 0xfd, 0x12, 0x34, 0x56, 0x78,
      ];
      final BytesBuilder payload = BytesBuilder();
      payload.addByte(0x01);
      final int now = DateTime.now().millisecondsSinceEpoch;
      for (int i = 7; i >= 0; i--) {
        payload.addByte((now >> (i * 8)) & 0xFF);
      }
      payload.add(magic);
      const int guid = 123456789;
      for (int i = 7; i >= 0; i--) {
        payload.addByte((guid >> (i * 8)) & 0xFF);
      }
      final Uint8List packet = payload.toBytes();

      final Completer<Uint8List> completer = Completer<Uint8List>();
      late StreamSubscription<RawSocketEvent> sub;
      sub = socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final Datagram? datagram = socket?.receive();
          if (datagram != null && !completer.isCompleted) {
            completer.complete(Uint8List.fromList(datagram.data));
          }
        }
      });
      final InternetAddress address = InternetAddress.tryParse(host) ?? (await InternetAddress.lookup(host)).first;
      socket.send(packet, address, port);
      final Uint8List data = await completer.future.timeout(_timeout);
      await sub.cancel();

      if (data.isEmpty || data[0] != 0x1c) throw const FormatException('Unexpected RakNet reply');
      // 1 (id) + 8 (time) + 8 (guid) + 16 (magic) + 2 (length) = 35
      final int strLen = ((data[33] & 0xFF) << 8) | (data[34] & 0xFF);
      final int available = data.length - 35;
      final String text = String.fromCharCodes(data.sublist(35, 35 + (strLen < available ? strLen : available)));
      final List<String> fields = text.split(';');
      watch.stop();
      return PingResult(
        online: true,
        latencyMs: watch.elapsedMilliseconds,
        playersOnline: fields.length > 4 ? int.tryParse(fields[4]) : null,
        playersMax: fields.length > 5 ? int.tryParse(fields[5]) : null,
        motd: <String>[
          if (fields.length > 1) fields[1],
          if (fields.length > 7) fields[7],
        ].join(' ').trim(),
        version: fields.isNotEmpty ? fields[0] : '',
      );
    } catch (error) {
      watch.stop();
      return PingResult(online: false, latencyMs: watch.elapsedMilliseconds, error: error.toString());
    } finally {
      socket?.close();
    }
  }

  static String _stripFormatting(String input) {
    return input.replaceAll(RegExp(r'§[0-9a-fk-orA-FK-OR]'), '');
  }
}

void _writeVarInt(BytesBuilder builder, int value) {
  int v = value;
  while (true) {
    if ((v & ~0x7F) == 0) {
      builder.addByte(v);
      return;
    }
    builder.addByte((v & 0x7F) | 0x80);
    v = v >> 7;
  }
}

class _SocketReader {
  _SocketReader(this._socket) {
    _subscription = _socket.listen(
      (Uint8List chunk) {
        _buffer.add(chunk);
        _pump();
      },
      onError: (Object error) {
        _failWaiters(error);
      },
      onDone: () {
        _failWaiters(const FormatException('Connection closed'));
      },
      cancelOnError: true,
    );
  }

  final Socket _socket;
  final BytesBuilder _buffer = BytesBuilder();
  Completer<int>? _varIntWaiter;
  Completer<Uint8List>? _exactWaiter;
  int _exactNeeded = 0;
  late final StreamSubscription<Uint8List> _subscription;

  int _readOffset = 0;

  List<int> get _bytes => _buffer.toBytes();

  void _failWaiters(Object error) {
    if (_varIntWaiter != null && !_varIntWaiter!.isCompleted) _varIntWaiter!.completeError(error);
    if (_exactWaiter != null && !_exactWaiter!.isCompleted) _exactWaiter!.completeError(error);
  }

  void _pump() {
    if (_varIntWaiter != null && !_varIntWaiter!.isCompleted) {
      final int? value = _tryReadVarInt();
      if (value != null) {
        _varIntWaiter!.complete(value);
        _varIntWaiter = null;
      }
    }
    if (_exactWaiter != null && !_exactWaiter!.isCompleted && _available >= _exactNeeded) {
      final Uint8List data = _take(_exactNeeded);
      _exactWaiter!.complete(data);
      _exactWaiter = null;
    }
  }

  int get _available => _bytes.length - _readOffset;

  int? _tryReadVarInt() {
    final List<int> data = _bytes;
    int result = 0;
    int shift = 0;
    int index = _readOffset;
    while (index < data.length) {
      final int byte = data[index];
      result |= (byte & 0x7F) << shift;
      index++;
      if ((byte & 0x80) == 0) {
        _readOffset = index;
        return result;
      }
      shift += 7;
      if (shift > 35) return null;
    }
    return null;
  }

  Uint8List _take(int length) {
    final List<int> data = _bytes;
    final Uint8List out = Uint8List.fromList(data.sublist(_readOffset, _readOffset + length));
    _readOffset += length;
    return out;
  }

  Future<int> readVarInt() {
    final int? immediate = _tryReadVarInt();
    if (immediate != null) return Future<int>.value(immediate);
    _varIntWaiter = Completer<int>();
    return _varIntWaiter!.future.timeout(const Duration(seconds: 6));
  }

  Future<Uint8List> readExact(int length) {
    if (_available >= length) return Future<Uint8List>.value(_take(length));
    _exactNeeded = length;
    _exactWaiter = Completer<Uint8List>();
    return _exactWaiter!.future.timeout(const Duration(seconds: 6));
  }

  Future<void> dispose() async {
    await _subscription.cancel();
  }
}
