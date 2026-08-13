import '../data/models/obra_model.dart';

class ApuDatabaseService {
  final List<ObraModel> _obras = [
    ObraModel(
      id: 1,
      nombre: 'Obra Demo Residencial',
      propietario: 'Juan Pérez',
      ubicacion: 'Av. Corrientes 1234',
      tipoObra: 'Vivienda Unifamiliar',
      empresa: 'Constructora Demo',
      perfilCreador: 'admin',
    ),
  ];

  Future<List<ObraModel>> getObras() async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _obras;
  }
}