class PoiCategoryGroup {
  const PoiCategoryGroup(this.title, this.items);

  final String title;
  final List<String> items;
}

const poiCategoryGroups = [
  PoiCategoryGroup(
    'Patrimoine et Histoire',
    [
      'Chateaux',
      'Ruines',
      'Monuments anciens',
      'Sites classes UNESCO',
      'Batiments religieux',
      'Routes et cols celebres',
      'Villages de caractere',
      'Plus Beaux Villages de France',
    ],
  ),
  PoiCategoryGroup(
    'Nature',
    [
      'Cascades',
      'Gorges',
      'Belvederes',
      'Sites naturels remarquables',
      'Lieux sous-cotes a valoriser',
    ],
  ),
  PoiCategoryGroup(
    'Culture',
    [
      'Musees',
      'Operas',
      'Lieux culturels',
      'Expositions',
      'Festivals',
      'Marches locaux',
    ],
  ),
  PoiCategoryGroup(
    'Experience gustative',
    [
      'Domaines viticoles',
      'Brasseries',
      'Fabriques artisanales',
      'Degustations locales',
      'Specialites regionales',
    ],
  ),
  PoiCategoryGroup(
    'Activites plein air',
    [
      'Randonnee',
      'Activites a sensation',
      'Activites familiales',
      'Activites culturelles',
    ],
  ),
];
