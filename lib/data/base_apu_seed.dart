import '../models/subitem_base.dart';

class BaseApuSeed {
  static List<SubitemBase> getSubitemsBase() {
    return [
      SubitemBase(
        codigo: '1.1',
        descripcion: 'Mampostería de ladrillo común de 15cm',
        unidad: 'm2',
        precioUnitarioBase: 18500.0,
      ),
      SubitemBase(
        codigo: '1.2',
        descripcion: 'Revoque grueso exterior',
        unidad: 'm2',
        precioUnitarioBase: 9200.0,
      ),
      SubitemBase(
        codigo: '1.3',
        descripcion: 'Contrapiso de hormigón pobre h=10cm',
        unidad: 'm2',
        precioUnitarioBase: 14000.0,
      ),
    ];
  }
}