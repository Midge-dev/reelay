import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// What a fake server says to one request.
class FakeReply {
  final int status;
  final List<int> body;
  final String contentType;

  FakeReply.json(Object? data, {this.status = 200})
    : body = utf8.encode(jsonEncode(data)),
      contentType = 'application/json; charset=utf-8';

  FakeReply.bytes(this.body, {this.status = 200, this.contentType = 'application/octet-stream'});

  FakeReply.empty({this.status = 204}) : body = const [], contentType = 'text/plain';

  /// How long the server takes to answer — on the test's clock.
  Duration delay = Duration.zero;
}

/// One request as a fake server sees it.
class FakeRequest {
  FakeRequest(this.method, this.uri, this.headers, this.body);
  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;

  @override
  String toString() => '$method ${uri.path}${uri.query.isEmpty ? '' : '?${uri.query}'}';
}

/// Answers a request, or returns null when it isn't this server's.
typedef FakeRoute = FakeReply? Function(FakeRequest request);

/// Every HttpClient the app creates (Dio's adapter, Image.network) talks to
/// [routes] instead of the network. Unanswered requests are refused like a
/// host that isn't there, and listed in [unrouted] so a test can show what
/// it forgot to serve.
///
/// Requests go to the newest FakeNetwork, whichever one created the client:
/// Flutter's NetworkImage keeps one HttpClient for the whole test run, made
/// under the first test's network, and would otherwise send every later
/// test's images there.
class FakeNetwork extends HttpOverrides {
  FakeNetwork(this.routes) {
    _current = this;
  }

  static FakeNetwork? _current;

  final List<FakeRoute> routes;
  final requests = <FakeRequest>[];
  final unrouted = <FakeRequest>[];

  @override
  HttpClient createHttpClient(SecurityContext? context) => _Client(this);

  FakeReply? _answer(FakeRequest request) {
    requests.add(request);
    for (final route in routes) {
      final reply = route(request);
      if (reply != null) return reply;
    }
    unrouted.add(request);
    return null;
  }
}

/// A 1×1 transparent PNG, for every image the app asks for.
const transparentPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

class _Client implements HttpClient {
  _Client(this._network);
  final FakeNetwork _network;

  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  bool autoUncompress = true;
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _Request(FakeNetwork._current ?? _network, method, url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  Future<HttpClientRequest> postUrl(Uri url) => openUrl('POST', url);
  @override
  Future<HttpClientRequest> putUrl(Uri url) => openUrl('PUT', url);
  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => openUrl('DELETE', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('fake HttpClient: ${invocation.memberName}');
}

class _Request implements HttpClientRequest {
  _Request(this._network, this.method, this.uri);
  final FakeNetwork _network;
  @override
  final String method;
  @override
  final Uri uri;
  @override
  final HttpHeaders headers = _Headers();
  final _body = <int>[];
  final _done = Completer<HttpClientResponse>();

  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = true;
  @override
  bool bufferOutput = true;
  @override
  int contentLength = -1;
  @override
  Encoding encoding = utf8;

  @override
  void add(List<int> data) => _body.addAll(data);
  @override
  void write(Object? object) => _body.addAll(utf8.encode('$object'));
  @override
  Future<void> addStream(Stream<List<int>> stream) => stream.forEach(_body.addAll);
  @override
  Future<void> flush() async {}

  @override
  Future<HttpClientResponse> close() async {
    final flat = <String, String>{};
    headers.forEach((k, v) => flat[k.toLowerCase()] = v.join(','));
    final reply = _network._answer(FakeRequest(method, uri, flat, List.of(_body)));
    if (reply == null) {
      throw SocketException('Connection refused (fake network: nothing serves $method $uri)');
    }
    if (reply.delay > Duration.zero) await Future<void>.delayed(reply.delay);
    final response = _Response(reply);
    if (!_done.isCompleted) _done.complete(response);
    return response;
  }

  @override
  Future<HttpClientResponse> get done => _done.future;
  @override
  void abort([Object? exception, StackTrace? stackTrace]) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('fake HttpClientRequest: ${invocation.memberName}');
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(this._reply) {
    headers.set(HttpHeaders.contentTypeHeader, _reply.contentType);
    headers.set(HttpHeaders.contentLengthHeader, '${_reply.body.length}');
  }
  final FakeReply _reply;

  @override
  final HttpHeaders headers = _Headers();
  @override
  int get statusCode => _reply.status;
  @override
  String get reasonPhrase => _reply.status < 400 ? 'OK' : 'Error';
  @override
  int get contentLength => _reply.body.length;
  @override
  HttpClientResponseCompressionState get compressionState => HttpClientResponseCompressionState.notCompressed;
  @override
  bool get isRedirect => false;
  @override
  List<RedirectInfo> get redirects => const [];
  @override
  bool get persistentConnection => true;
  @override
  X509Certificate? get certificate => null;
  @override
  HttpConnectionInfo? get connectionInfo => null;
  @override
  List<Cookie> get cookies => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  // Uint8List chunks, as dart:io's own responses are: Dio's byte responses
  // cast to it.
  }) => Stream<List<int>>.fromIterable([if (_reply.body.isNotEmpty) Uint8List.fromList(_reply.body)])
      .listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('fake HttpClientResponse: ${invocation.memberName}');
}

class _Headers implements HttpHeaders {
  final _values = <String, List<String>>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) => _values[name.toLowerCase()] = ['$value'];
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _values.putIfAbsent(name.toLowerCase(), () => []).add('$value');
  @override
  String? value(String name) => _values[name.toLowerCase()]?.join(',');
  @override
  List<String>? operator [](String name) => _values[name.toLowerCase()];
  @override
  void forEach(void Function(String name, List<String> values) action) => _values.forEach(action);
  @override
  void remove(String name, Object value) => _values[name.toLowerCase()]?.remove('$value');
  @override
  void removeAll(String name) => _values.remove(name.toLowerCase());
  @override
  void clear() => _values.clear();

  @override
  ContentType? get contentType {
    final v = value(HttpHeaders.contentTypeHeader);
    return v == null ? null : ContentType.parse(v);
  }

  @override
  set contentType(ContentType? type) => type == null ? removeAll(HttpHeaders.contentTypeHeader) : set(HttpHeaders.contentTypeHeader, type);

  @override
  int contentLength = -1;
  @override
  bool chunkedTransferEncoding = false;
  @override
  bool persistentConnection = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
