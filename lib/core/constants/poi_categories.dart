class PoiCategoryGroup {
  const PoiCategoryGroup(this.title, this.items);

  final String title;
  final List<String> items;
}

const poiCategoryGroups = [
  PoiCategoryGroup(
    'Patrimoine et Histoire',
    [
      'Villages de caractere (historiques et plus beaux villages)',
      'Chateaux',
      'Monuments anciens',
      'Sites classes UNESCO',
      'Sites historiques et archeologiques',
      'Sites religieux',
    ],
  ),
  PoiCategoryGroup(
    'Nature',
    [
      'Cascades',
      'Gorges',
      'Parcs naturels',
      'Lacs',
      'Rivieres (acces riviere ou parking)',
      'Points de vue (belvederes)',
      'Reserves naturelles',
    ],
  ),
  PoiCategoryGroup(
    'Culture',
    [
      'Musees',
      'Expositions',
      'Festivals',
      'Galeries d art',
      'Theatres',
    ],
  ),
  PoiCategoryGroup(
    'Activites plein air',
    [
      'Randonnee',
      'Activites familiales',
      'Escalade',
      'Velo',
      'Sports nautiques',
      'Campings',
    ],
  ),
];
