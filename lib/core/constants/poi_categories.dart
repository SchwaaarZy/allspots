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
      'Sites archeologiques',
      'Forts et citadelles',
      'Memoriaux',
      'Abbayes',
      'Sites historiques',
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
      'Parcs naturels',
      'Lacs et rivieres',
      'Forets',
      'Grottes',
      'Plages',
      'Points de vue',
      'Reserves naturelles',
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
      'Galeries d art',
      'Theatres',
      'Bibliotheques',
      'Cinemas',
      'Street art',
      'Patrimoine industriel',
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
      'Restaurants',
      'Cafes',
      'Bars et pubs',
      'Boulangeries',
      'Marches gastronomiques',
      'Distilleries',
    ],
  ),
  PoiCategoryGroup(
    'Activites plein air',
    [
      'Randonnee',
      'Activites a sensation',
      'Activites familiales',
      'Activites culturelles',
      'Escalade',
      'Velo',
      'Sports nautiques',
      'Ski et montagne',
      'Golf',
      'Parcs de loisirs',
      'Campings',
    ],
  ),
];
