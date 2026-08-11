import '../models/insumo.dart';

class BaseInsumosSeed {
  static List<Insumo> getInsumosIniciales() {
    return [
      Insumo(nombre: 'Cemento Portland', unidad: 'bolsa', precioUnitario: 8500.0, tipo: 'Material'),
      Insumo(nombre: 'Arena Fina', unidad: 'm3', precioUnitario: 12000.0, tipo: 'Material'),
      Insumo(nombre: 'Cal Hidratada', unidad: 'bolsa', precioUnitario: 4500.0, tipo: 'Material'),
      Insumo(nombre: 'Oficial Albañil', unidad: 'hs', precioUnitario: 3500.0, tipo: 'Mano de Obra'),
      Insumo(nombre: 'Peón', unidad: 'hs', precioUnitario: 2800.0, tipo: 'Mano de Obra'),
      Insumo(nombre: 'Hormigonera 130L', unidad: 'dia', precioUnitario: 15000.0, tipo: 'Equipo'),
    ];
  }
}