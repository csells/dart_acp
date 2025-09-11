import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_acp/src/transport/stdin_transport.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

/// Mock IOSink for testing
class MockIOSink implements IOSink {
  final List<String> written = [];

  @override
  void writeln([Object? object = '']) {
    written.add(object.toString());
  }

  @override
  void write(Object? object) => written.add(object.toString());
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) => stream.drain();
  @override
  Future close() async {}
  @override
  Future get done => Future.value();
  @override
  Future flush() async {}
  @override
  Encoding encoding = utf8;
}

void main() {
  group('StdinTransport', () {
    late Logger logger;
    late StdinTransport transport;
    late List<String> protocolIn;
    late List<String> protocolOut;
    // ignore: close_sinks
    late StreamController<List<int>> mockInput;
    // ignore: close_sinks
    late MockIOSink mockOutput;

    setUp(() {
      logger = Logger('test');
      protocolIn = [];
      protocolOut = [];
      mockInput = StreamController<List<int>>.broadcast();
      mockOutput = MockIOSink();

      transport = StdinTransport(
        logger: logger,
        onProtocolIn: protocolIn.add,
        onProtocolOut: protocolOut.add,
        inputStream: mockInput.stream,
        outputSink: mockOutput,
      );
    });

    tearDown(() async {
      await transport.stop();
      await mockInput.close();
    });

    test('throws when accessing channel before start', () {
      expect(() => transport.channel, throwsStateError);
    });

    test('can start and stop transport', () async {
      await transport.start();
      expect(() => transport.channel, returnsNormally);

      await transport.stop();
      expect(() => transport.channel, throwsStateError);
    });

    test('sends messages to output', () async {
      await transport.start();

      const testMessage = '{"test": "message"}';
      transport.channel.sink.add(testMessage);

      // Give it time to process
      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockOutput.written, contains(testMessage));
      expect(protocolOut, contains(testMessage));
    });

    test('receives messages from input', () async {
      await transport.start();

      final messages = <String>[];
      final subscription = transport.channel.stream.listen(messages.add);

      // Simulate input
      const testMessage = '{"method": "test"}';
      mockInput.add(utf8.encode('$testMessage\n'));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(messages, contains(testMessage));
      expect(protocolIn, contains(testMessage));

      await subscription.cancel();
    });

    test('handles multiple start/stop cycles', () async {
      await transport.start();
      expect(() => transport.channel, returnsNormally);
      await transport.stop();

      await transport.start();
      expect(() => transport.channel, returnsNormally);
      await transport.stop();
    });

    test('protocol callbacks are invoked', () async {
      await transport.start();

      // Test outbound callback
      const outMessage = '{"method": "test_out"}';
      transport.channel.sink.add(outMessage);

      await Future.delayed(const Duration(milliseconds: 100));

      expect(protocolOut, contains(outMessage));

      // Test inbound callback
      const inMessage = '{"method": "test_in"}';
      mockInput.add(utf8.encode('$inMessage\n'));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(protocolIn, contains(inMessage));
    });

    test('handles bidirectional communication', () async {
      await transport.start();

      final received = <String>[];
      final subscription = transport.channel.stream.listen(received.add);

      // Send a message out
      transport.channel.sink.add('{"id": 1, "method": "request"}');

      // Receive a response
      mockInput.add(utf8.encode('{"id": 1, "result": "response"}\n'));

      await Future.delayed(const Duration(milliseconds: 100));

      expect(mockOutput.written, contains('{"id": 1, "method": "request"}'));
      expect(received, contains('{"id": 1, "result": "response"}'));

      await subscription.cancel();
    });
  });
}
