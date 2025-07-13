import 'dart:convert';
import 'package:http/http.dart' as http;

class NetworkService {
  final String _baseUrl;

  NetworkService(this._baseUrl);

  /// Sends a flat 600-length list and returns the prediction vector.
  Future<List<double>> fetchPrediction(List<double> flatData) async {
    final uri = Uri.parse("$_baseUrl/predict");
    final resp = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"data": flatData}),
    );

    if (resp.statusCode != 200) {
      throw Exception(
          "Server error (${resp.statusCode}): ${resp.body}");
    }

    final body = jsonDecode(resp.body);print("🗝️ Keys: ${body.keys.toList()}");

    final List<dynamic> predDyn = body["probabilities"];
    // cast dynamic → double
    return predDyn.map((e) => (e as num).toDouble()).toList();
  }
}
