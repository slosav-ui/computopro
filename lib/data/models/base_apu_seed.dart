import 'subitem_base.dart';

class BaseApuSeed {
  static List<SubitemBase> getSubitemsBase() {
    return [
      SubitemBase(
        id: 'apu_01',
        codigo: '1.1',
        descripcion: 'Mampostería de ladrillo común de 15cm',
        unidad: 'm2',
        precioSugerido: 18500.0,
      ),
      SubitemBase(
        id: 'apu_02',
        codigo: '1.2',
        descripcion: 'Revoque grueso exterior',
        unidad: 'm2',
        precioSugerido: 9200.0,
      ),
      SubitemBase(
        id: 'apu_03',
        codigo: '1.3',
        descripcion: 'Contrapiso de hormigón pobre h=10cm',
        unidad: 'm2',
        precioSugerido: 14000.0,
      ),
    ];
  }
}