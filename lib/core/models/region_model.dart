/// Modèle représentant un pays
class CountryModel {
  final String code; // Code pays (ex: "fr")
  final String name; // Nom (ex: "France")
  final List<RegionModel> regions;
  bool isSelected;

  CountryModel({
    required this.code,
    required this.name,
    required this.regions,
    this.isSelected = false,
  });

  /// Nombre de régions avec au moins un département sélectionné
  int get selectedRegionsCount => regions.where((r) => r.isSelected).length;

  /// Nombre total de départements sélectionnés
  int get totalSelectedDepartmentsCount => 
      regions.fold<int>(0, (sum, region) => sum + region.selectedDepartmentsCount);

  @override
  String toString() => 'CountryModel(code: $code, name: $name, selected: $isSelected)';
}

/// Modèle représentant une région avec ses départements
class RegionModel {
  final String code; // Code régional (ex: "paca")
  final String name; // Nom de la région (ex: "PACA / Provence-Alpes-Côte d'Azur")
  final List<DepartmentModel> departments;
  bool isSelected;

  RegionModel({
    required this.code,
    required this.name,
    required this.departments,
    this.isSelected = false,
  });

  /// Nombre de départements sélectionnés
  int get selectedDepartmentsCount => departments.where((d) => d.isSelected).length;

  /// Vrai si tous les départements sont sélectionnés
  bool get allDepartmentsSelected => selectedDepartmentsCount == departments.length;

  @override
  String toString() => 'RegionModel(code: $code, name: $name, selected: $isSelected)';
}

/// Modèle représentant un département
class DepartmentModel {
  final String code; // Code département (ex: "06", "13", "83")
  final String name; // Nom (ex: "Alpes-Maritimes")
  bool isSelected;

  DepartmentModel({
    required this.code,
    required this.name,
    this.isSelected = false,
  });

  @override
  String toString() => 'DepartmentModel(code: $code, name: $name, selected: $isSelected)';
}

/// Données définissant les pays, régions et départements supportés
final List<CountryModel> allCountries = [
  CountryModel(
    code: 'fr',
    name: '🇫🇷 France',
    regions: [
      RegionModel(
        code: 'paca',
        name: 'PACA (Provence-Alpes-Côte d\'Azur)',
        departments: [
          DepartmentModel(code: '04', name: 'Alpes-de-Haute-Provence'),
          DepartmentModel(code: '05', name: 'Hautes-Alpes'),
          DepartmentModel(code: '06', name: 'Alpes-Maritimes'),
          DepartmentModel(code: '13', name: 'Bouches-du-Rhône'),
          DepartmentModel(code: '83', name: 'Var'),
          DepartmentModel(code: '84', name: 'Vaucluse'),
        ],
      ),
      RegionModel(
        code: 'occitanie',
        name: 'Occitanie',
        departments: [
          DepartmentModel(code: '09', name: 'Ariège'),
          DepartmentModel(code: '12', name: 'Aveyron'),
          DepartmentModel(code: '30', name: 'Gard'),
          DepartmentModel(code: '32', name: 'Gers'),
          DepartmentModel(code: '34', name: 'Hérault'),
          DepartmentModel(code: '46', name: 'Lot'),
          DepartmentModel(code: '48', name: 'Lozère'),
          DepartmentModel(code: '65', name: 'Hautes-Pyrénées'),
          DepartmentModel(code: '66', name: 'Pyrénées-Orientales'),
          DepartmentModel(code: '81', name: 'Tarn'),
          DepartmentModel(code: '82', name: 'Tarn-et-Garonne'),
        ],
      ),
      RegionModel(
        code: 'auvergne_rhone_alpes',
        name: 'Auvergne-Rhône-Alpes',
        departments: [
          DepartmentModel(code: '01', name: 'Ain'),
          DepartmentModel(code: '03', name: 'Allier'),
          DepartmentModel(code: '07', name: 'Ardèche'),
          DepartmentModel(code: '15', name: 'Cantal'),
          DepartmentModel(code: '26', name: 'Drôme'),
          DepartmentModel(code: '38', name: 'Isère'),
          DepartmentModel(code: '42', name: 'Loire'),
          DepartmentModel(code: '43', name: 'Haute-Loire'),
          DepartmentModel(code: '63', name: 'Puy-de-Dôme'),
          DepartmentModel(code: '69', name: 'Rhône'),
          DepartmentModel(code: '70', name: 'Haute-Saône'),
          DepartmentModel(code: '71', name: 'Saône-et-Loire'),
          DepartmentModel(code: '73', name: 'Savoie'),
          DepartmentModel(code: '74', name: 'Haute-Savoie'),
        ],
      ),
      RegionModel(
        code: 'nouvelle_aquitaine',
        name: 'Nouvelle-Aquitaine',
        departments: [
          DepartmentModel(code: '16', name: 'Charente'),
          DepartmentModel(code: '17', name: 'Charente-Maritime'),
          DepartmentModel(code: '19', name: 'Corrèze'),
          DepartmentModel(code: '23', name: 'Creuse'),
          DepartmentModel(code: '24', name: 'Dordogne'),
          DepartmentModel(code: '33', name: 'Gironde'),
          DepartmentModel(code: '40', name: 'Landes'),
          DepartmentModel(code: '47', name: 'Lot-et-Garonne'),
          DepartmentModel(code: '64', name: 'Pyrénées-Atlantiques'),
          DepartmentModel(code: '79', name: 'Deux-Sèvres'),
          DepartmentModel(code: '85', name: 'Vendée'),
          DepartmentModel(code: '86', name: 'Vienne'),
          DepartmentModel(code: '87', name: 'Haute-Vienne'),
        ],
      ),
    ],
  ),
];

