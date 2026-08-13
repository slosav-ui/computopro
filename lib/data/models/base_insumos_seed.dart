import 'insumo.dart';

class BaseInsumosSeed {
  static List<Insumo> getInsumosIniciales() {
    return [
      Insumo(
        id: 'ins_01',
        nombre: 'Cemento Portland',
        unidad: 'bolsa',
        precio: 8500.0,
        tipo: 'Material',
      ),
      Insumo(
        id: 'ins_02',
        nombre: 'Arena Fina',
        unidad: 'm3',
        precio: 12000.0,
        tipo: 'Material',
      ),
      Insumo(
        id: 'ins_03',
        nombre: 'Cal Hidratada',
        unidad: 'bolsa',
        precio: 4500.0,
        tipo: 'Material',
      ),
      Insumo(
        id: 'ins_04',
        nombre: 'Oficial Albañil',
        unidad: 'hs',
        precio: 3500.0,
        tipo: 'Mano de Obra',
      ),
      Insumo(
        id: 'ins_05',
        nombre: 'Peón',
        unidad: 'hs',
        precio: 2800.0,
        tipo: 'Mano de Obra',
      ),
      Insumo(
        id: 'ins_06',
        nombre: 'Hormigonera 130L',
        unidad: 'dia',
        precio: 15000.0,
        tipo: 'Equipo',
      ),
    ];
  }
}