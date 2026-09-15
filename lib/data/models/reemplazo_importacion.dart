/// Lo que devuelven `previsualizar_reemplazo_importacion` y `diferencias_reemplazo_importacion`
/// (migración 0157): el diff entre lo que trae la planilla y lo que ya está cargado en la obra.
///
/// Existe porque el reemplazo **no decide por regla quién gana**. Seba, 2026-09-15:
///
/// > *"Tenemos que tirar una alerta de que los datos no se corresponden (...) para que no pise y
/// > digas: uy, mirá, me perdí todo el trabajo."*
///
/// El resumen abre el diálogo; el detalle se pide solo si el usuario quiere verlo.

/// Una diferencia concreta entre la planilla y la obra.
class DiferenciaReemplazo {
  /// Código de la partida en la carpeta. `null` en las nuevas: todavía no existe.
  final String? codigo;
  final String descripcion;

  /// `precio` | `cantidad` | `nueva` | `descartada` | `reactivada`.
  ///
  /// Una misma partida puede generar dos filas (precio y cantidad): son dos cambios distintos y el
  /// usuario tiene que poder verlos por separado.
  final String tipo;

  /// Lo que está cargado hoy. `null` en `nueva` y `reactivada`.
  final double? valorActual;

  /// Lo que trae la planilla. `null` en `descartada`.
  final double? valorPlanilla;

  /// **El dato que hace que el aviso no sea ruido.** `true` cuando el valor cargado NO lo puso la
  /// última importación confirmada: o sea, lo cambió una persona después.
  ///
  /// No es lo mismo "la planilla se corrigió" que "vas a pisar lo que cargaste a mano", y con
  /// cincuenta diferencias es la única forma de que el aviso señale algo.
  final bool editadaAMano;

  /// Cuánta plata se va con una `descartada`. `null` en el resto.
  final double? montoActual;

  const DiferenciaReemplazo({
    required this.codigo,
    required this.descripcion,
    required this.tipo,
    required this.valorActual,
    required this.valorPlanilla,
    required this.editadaAMano,
    required this.montoActual,
  });

  bool get esCambioDeValor => tipo == 'precio' || tipo == 'cantidad';

  factory DiferenciaReemplazo.fromMap(Map<String, dynamic> map) {
    return DiferenciaReemplazo(
      codigo: map['codigo']?.toString(),
      descripcion: map['descripcion']?.toString() ?? '',
      tipo: map['tipo']?.toString() ?? '',
      valorActual: (map['valor_actual'] as num?)?.toDouble(),
      valorPlanilla: (map['valor_planilla'] as num?)?.toDouble(),
      editadaAMano: map['editada_a_mano'] == true,
      montoActual: (map['monto_actual'] as num?)?.toDouble(),
    );
  }
}

/// El resumen: lo que se muestra primero, sin pedir el detalle.
class ResumenReemplazo {
  final int cambiosPrecio;
  final int cambiosCantidad;

  /// Partidas (no campos) cuyo valor cargado lo puso una persona y el reemplazo va a pisar.
  final int editadasAMano;

  final int nuevas;
  final int descartadas;

  /// Las que un reemplazo anterior había destildado y la planilla vuelve a traer.
  final int reactivadas;

  final int sinCambios;

  /// Cuánta plata se destilda.
  final double montoDescartado;

  /// Avances en certificados **borrador** que se descartan al destildar sus partidas.
  final int avancesBorrador;

  /// La obra ya tiene certificados emitidos: el reemplazo se rechaza.
  final bool bloqueado;
  final String? motivoBloqueo;

  /// La obra está congelada (sin emitir) y el reemplazo la va a descongelar.
  final bool descongela;

  const ResumenReemplazo({
    required this.cambiosPrecio,
    required this.cambiosCantidad,
    required this.editadasAMano,
    required this.nuevas,
    required this.descartadas,
    required this.reactivadas,
    required this.sinCambios,
    required this.montoDescartado,
    required this.avancesBorrador,
    required this.bloqueado,
    required this.motivoBloqueo,
    required this.descongela,
  });

  /// `true` cuando la planilla no cambia nada de lo que ya está cargado. Con esto el diálogo puede
  /// decir "no cambia nada" en vez de una lista vacía, que se lee como un error.
  bool get sinDiferencias =>
      cambiosPrecio == 0 &&
      cambiosCantidad == 0 &&
      nuevas == 0 &&
      descartadas == 0 &&
      reactivadas == 0;

  /// El titular, en la forma que pidió Seba: *"cambian 3 precios y 1 cantidad"*.
  ///
  /// Se arma con las partes que no están en cero -- enumerar "0 nuevas, 0 descartadas" es ruido.
  String get titular {
    final partes = <String>[
      if (cambiosPrecio > 0) '$cambiosPrecio ${cambiosPrecio == 1 ? "precio" : "precios"}',
      if (cambiosCantidad > 0) '$cambiosCantidad ${cambiosCantidad == 1 ? "cantidad" : "cantidades"}',
    ];
    final extras = <String>[
      if (nuevas > 0) '$nuevas ${nuevas == 1 ? "partida nueva" : "partidas nuevas"}',
      if (descartadas > 0)
        '$descartadas ${descartadas == 1 ? "partida que ya no viene" : "partidas que ya no vienen"}',
      if (reactivadas > 0) '$reactivadas que vuelve${reactivadas == 1 ? "" : "n"} a entrar',
    ];

    if (partes.isEmpty && extras.isEmpty) return 'La planilla no cambia nada de lo que ya está cargado.';
    if (partes.isEmpty) return 'Entra${extras.length == 1 ? "" : "n"} ${extras.join(", ")}.';
    return 'Cambian ${partes.join(" y ")}'
        '${extras.isEmpty ? "" : ", y ${extras.join(", ")}"}.';
  }

  factory ResumenReemplazo.fromMap(Map<String, dynamic> map) {
    return ResumenReemplazo(
      cambiosPrecio: (map['cambios_precio'] as num?)?.toInt() ?? 0,
      cambiosCantidad: (map['cambios_cantidad'] as num?)?.toInt() ?? 0,
      editadasAMano: (map['editadas_a_mano'] as num?)?.toInt() ?? 0,
      nuevas: (map['nuevas'] as num?)?.toInt() ?? 0,
      descartadas: (map['descartadas'] as num?)?.toInt() ?? 0,
      reactivadas: (map['reactivadas'] as num?)?.toInt() ?? 0,
      sinCambios: (map['sin_cambios'] as num?)?.toInt() ?? 0,
      montoDescartado: (map['monto_descartado'] as num?)?.toDouble() ?? 0,
      avancesBorrador: (map['avances_borrador'] as num?)?.toInt() ?? 0,
      bloqueado: map['bloqueado'] == true,
      motivoBloqueo: map['motivo_bloqueo']?.toString(),
      descongela: map['descongela'] == true,
    );
  }
}
