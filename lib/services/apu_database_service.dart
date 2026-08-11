import '../models/obra_model.dart';

class ApuDatabaseService {
  final List<ObraModel> _obras = [
    ObraModel(
      id: 1,
      nombre: 'Obra Demo Residencial',
      propietario: 'Juan Pérez',
      ubicacion: 'Av. Corrientes 1234',
      tipoObra: 'Vivienda Unifamiliar',
    )
  ];

  Future<List<ObraModel>> getObras() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _obras;
  }

  Future<int> insertObra(ObraModel obra) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final id = _obras.length + 1;
    final nuevaObra = ObraModel(
      id: id,
      nombre: obra.nombre,
      propietario: obra.propietario,
      ubicacion: obra.ubicacion,
      tipoObra: obra.tipoObra,
    );
    _obras.add(nuevaObra);
    return id;
  }
}