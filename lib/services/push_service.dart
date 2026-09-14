import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// El token de este teléfono, registrado en `dispositivos` (`0142`) para que algún día le llegue una
/// notificación. Tanda 1b de docs/notificaciones_push_diagnostico.md.
///
/// **Todavía no llega nada, y eso es a propósito**: esta tanda deja la plomería y se para a mirar.
/// Lo que manda —la outbox, la Edge Function y FCM— es la Tanda 2 y la 3, y puede no construirse
/// nunca si el aviso adentro de la app alcanza.
///
/// **Todo lo de acá es silencioso ante error.** Que no se pueda registrar un token no puede romper
/// el arranque de la app: el push es una comodidad, no una función de la que dependa nada. Si falla,
/// el usuario simplemente no recibe algo que hoy tampoco recibe.
class PushService {
  final SupabaseClient _client = Supabase.instance.client;

  static bool _inicializado = false;

  /// Solo Android por ahora: iOS necesita macOS para compilar y APNs para funcionar, y no hay
  /// ninguno de los dos. En cualquier otra plataforma (escritorio, web) esto no hace nada en vez de
  /// explotar -- el proyecto corre en Windows para desarrollar.
  static bool get soportado => !kIsWeb && Platform.isAndroid;

  /// Arranca Firebase. Se llama una sola vez, antes de `runApp`.
  ///
  /// Devuelve `false` si no se pudo -- y ahí la app sigue andando igual, sin push. Es el caso de un
  /// `google-services.json` que falta o de una plataforma sin soporte.
  static Future<bool> inicializar() async {
    if (!soportado) return false;
    try {
      await Firebase.initializeApp();
      _inicializado = true;
      return true;
    } catch (e, st) {
      debugPrint('PushService.inicializar falló (la app sigue sin push): $e\n$st');
      return false;
    }
  }

  /// Pide el permiso, consigue el token y lo registra.
  ///
  /// **Se llama en cada arranque con sesión abierta, no solo al iniciar sesión.** Un token de FCM
  /// cambia al reinstalar, al borrar los datos de la app y a veces solo porque FCM lo rota;
  /// registrarlo únicamente en el login deja el aparato mudo **sin que falle nada visible**.
  ///
  /// En Android 13+ `requestPermission` dispara el permiso de runtime `POST_NOTIFICATIONS`. En
  /// versiones anteriores no hay permiso que pedir y devuelve autorizado.
  Future<void> registrarEsteDispositivo() async {
    if (!_inicializado) return;
    try {
      final messaging = FirebaseMessaging.instance;

      final permiso = await messaging.requestPermission();
      if (permiso.authorizationStatus == AuthorizationStatus.denied) {
        // Sin permiso no tiene sentido guardar el token: FCM lo acepta pero el teléfono no muestra
        // nada. Y volver a pedirlo en cada arranque sería molestar -- Android no lo vuelve a
        // preguntar de todas formas.
        debugPrint('PushService: permiso de notificaciones denegado, no se registra el token.');
        return;
      }

      final token = await messaging.getToken();
      if (token == null) return;
      await _guardar(token);

      // El token puede rotar con la app abierta. Sin esto, ese aparato deja de recibir hasta el
      // próximo arranque.
      messaging.onTokenRefresh.listen(_guardar);
    } catch (e, st) {
      debugPrint('PushService.registrarEsteDispositivo falló: $e\n$st');
    }
  }

  Future<void> _guardar(String token) async {
    try {
      await _client.rpc('registrar_dispositivo', params: {
        'p_token': token,
        'p_plataforma': 'android',
      });
    } catch (e) {
      debugPrint('PushService: no se pudo registrar el token: $e');
    }
  }

  /// Borra este dispositivo de la lista del usuario que está cerrando sesión.
  ///
  /// **Tiene que llamarse ANTES del `signOut`**, no después: con la sesión ya cerrada `auth.uid()`
  /// es null del lado de la base y el borrado no matchea nada, y el teléfono se queda recibiendo los
  /// avisos de quien se acaba de ir. Es el punto más fácil de romper de toda la pieza.
  Future<void> olvidarEsteDispositivo() async {
    if (!_inicializado) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _client.rpc('borrar_dispositivo', params: {'p_token': token});
    } catch (e) {
      debugPrint('PushService.olvidarEsteDispositivo falló: $e');
    }
  }
}
