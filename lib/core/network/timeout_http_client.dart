import 'package:http/http.dart' as http;

/// http.Client compartido por todas las llamadas de Supabase (Postgrest,
/// Storage, Auth) -- ver `Supabase.initialize(httpClient: ...)` en
/// `main.dart`. Sin esto, ninguna llamada de la app tenía límite de tiempo:
/// si la red se trababa (cold start del proyecto en el plan free, corte de
/// señal en obra), el `await` podía quedar esperando sin fin -- nunca tira
/// excepción, así que el `catch` de la pantalla nunca corre, y el spinner
/// gira para siempre sin avisar nada. Diagnosticado con el alta de obra que
/// se colgó en el primer intento y no insertó nada.
///
/// 15 segundos, justificado con lo medido en la solapa de Cómputo: el peor
/// arranque en frío real fue 1934 ms para una sola consulta -- hay margen
/// de sobra incluso para una conexión de obra mala (la app está pensada
/// para usarse en el terreno), sin dejar a nadie mirando un spinner por más
/// de un rato razonable.
///
/// Ningún `catch` de la app interpola la excepción en el mensaje que
/// muestra (relevado antes de escribir esto) -- así que el `TimeoutException`
/// que tira esto nunca llega a pantalla como texto técnico, cae en el mismo
/// mensaje genérico y accionable que ya tenía cada pantalla para cualquier
/// otro error.
class TimeoutHttpClient extends http.BaseClient {
  TimeoutHttpClient(this._inner, {this.timeout = const Duration(seconds: 15)});

  final http.Client _inner;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(timeout);
  }
}
