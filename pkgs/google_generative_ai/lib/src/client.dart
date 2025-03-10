// Copyright 2024 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'error.dart';
import 'version.dart';

const clientName = 'genai-dart/$packageVersion';

abstract interface class ApiClient {
  Future<Map<String, Object?>> makeRequest(Uri uri, Map<String, Object?> body);

  Stream<Map<String, Object?>> streamRequest(
      Uri uri, Map<String, Object?> body);
}

// Encodes first by `json.encode`, then `utf8.encode`.
// Decodes first by `utf8.decode`, then `json.decode`.
final _utf8Json = json.fuse(utf8);

final class HttpApiClient implements ApiClient {
  final String? _apiKey;
  final http.Client? _httpClient;

  final FutureOr<Map<String, String>> Function()? _requestHeaders;

  HttpApiClient(
      {String? apiKey,
      http.Client? httpClient,
      FutureOr<Map<String, String>> Function()? requestHeaders})
      : _apiKey = apiKey,
        _httpClient = httpClient,
        _requestHeaders = requestHeaders;

  Future<Map<String, String>> _headers() async => {
        if (_apiKey != null) 'x-goog-api-key': _apiKey!,
        if (_apiKey != null) 'x-goog-api-client': clientName,
        'Content-Type': 'application/json',
        if (_requestHeaders case final requestHeaders?)
          ...(await requestHeaders()),
      };

  @override
  Future<Map<String, Object?>> makeRequest(
      Uri uri, Map<String, Object?> body) async {
    final response = await (_httpClient?.post ?? http.post)(
      uri,
      headers: await _headers(),
      body: _utf8Json.encode(body),
    );
    if (response.statusCode >= 500) {
      throw GenerativeAIException(
          'Server Error [${response.statusCode}]: ${response.body}');
    }

    return _utf8Json.decode(response.bodyBytes) as Map<String, Object?>;
  }

  @override
  Stream<Map<String, Object?>> streamRequest(
      Uri uri, Map<String, Object?> body) async* {
    uri = uri.replace(queryParameters: {'alt': 'sse'});
    final request = http.Request('POST', uri)
      ..bodyBytes = _utf8Json.encode(body)
      ..headers.addAll(await _headers());
    final response = await (_httpClient?.send(request) ?? request.send());
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      // Yeild a potential error object like a normal result for consistency
      // with `makeRequest`.
      yield jsonDecode(body) as Map<String, Object?>;
      return;
    }
    final lines =
        response.stream.toStringStream().transform(const LineSplitter());
    await for (final line in lines) {
      const dataPrefix = 'data: ';
      if (line.startsWith(dataPrefix)) {
        final jsonText = line.substring(dataPrefix.length);
        yield jsonDecode(jsonText) as Map<String, Object?>;
      }
    }
  }
}
