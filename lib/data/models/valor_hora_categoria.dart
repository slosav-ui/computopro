/// Resultado de `calcular_valor_hora_mano_obra` (ver
/// supabase/migrations/0039_calcular_valor_hora_mano_obra.sql y
/// 0043_valor_hora_con_cargas.sql) — valor hora de una categoría UOCRA para una obra puntual.
///
/// `valorHora`/`multiplicador` dependen del tilde `aplica_cargas_sociales` de la obra (y de si
/// hay un `obra_valor_hora_override` para esta categoría, ver `origen`). `valorHoraSinCargas`/
/// `valorHoraConCargas`/`multiplicadorConCargas` son siempre los mismos, sin importar el modo ni
/// el override — son la referencia fija que usa el cartel de costo de mano de obra. Ver
/// docs/costo_mano_de_obra_decisiones.md §8 y §14 para el detalle de por qué son dos preguntas
/// distintas, no un valor derivado del otro.
class ValorHoraCategoria {
  final String categoriaUocra;
  final double valorHora;
  final double valorHoraSinCargas;
  final double valorHoraConCargas;
  final double costoMensual;
  final double remuneracionMensual;
  final double multiplicador;
  final double multiplicadorConCargas;
  final String origen;

  const ValorHoraCategoria({
    required this.categoriaUocra,
    required this.valorHora,
    required this.valorHoraSinCargas,
    required this.valorHoraConCargas,
    required this.costoMensual,
    required this.remuneracionMensual,
    required this.multiplicador,
    required this.multiplicadorConCargas,
    required this.origen,
  });

  bool get tieneOverride => origen == 'override';

  factory ValorHoraCategoria.fromMap(Map<String, dynamic> map) {
    return ValorHoraCategoria(
      categoriaUocra: map['categoria_uocra'] as String,
      valorHora: (map['valor_hora'] as num).toDouble(),
      valorHoraSinCargas: (map['valor_hora_sin_cargas'] as num).toDouble(),
      valorHoraConCargas: (map['valor_hora_con_cargas'] as num).toDouble(),
      costoMensual: (map['costo_mensual'] as num).toDouble(),
      remuneracionMensual: (map['remuneracion_mensual'] as num).toDouble(),
      multiplicador: (map['multiplicador'] as num).toDouble(),
      multiplicadorConCargas: (map['multiplicador_con_cargas'] as num).toDouble(),
      origen: map['origen'] as String,
    );
  }
}
