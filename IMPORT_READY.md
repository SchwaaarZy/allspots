# Import OSM Var - État Complet ✅

## Résumé d'Exécution

L'import complet du département Var (83) depuis OpenStreetMap est **TERMINÉ**.

**Fichier prêt:**
- 📂 `scripts/out/pois_all_categories_20260223_093423.json` (3.6 MB)
- ✅ 4599 POIs extraits et dédupliqués
- ✅ URLs d'images normalisées (Wikimedia → direct)

### Répartition par Catégorie
| Catégorie | Nombre |
|-----------|--------|
| Experience gustative | 2820 |
| Nature | 692 |
| Patrimoine et Histoire | 550 |
| Culture | 407 |
| Activites plein air | 130 |
| **TOTAL** | **4599** |

---

## Comment Importer dans Firestore

### Option 1: Via Console Firebase (Recommandé)
1. Allez sur https://console.firebase.google.com
2. Sélectionnez **allspots-5872e**
3. Menu: **Firestore** → **Database**
4. Trois points → **Importer des données**
5. Sélectionnez: `scripts/out/pois_all_categories_20260223_093423.json`
6. Collection: `spots`
7. Cliquez **Import**

L'import prendra ~5-10 minutes pour 4599 documents.

### Option 2: Via gcloud CLI
```bash
brew install google-cloud-sdk
gcloud auth login
gcloud firestore import scripts/out/pois_all_categories_20260223_093423.json \
  --project=allspots-5872e \
  --async
```

---

## Vérifier l'Import

### Dans Firestore Console
- Collection `spots` doit contenir des docs avec:
  - **lat** & **lng**: 43.1xx, 5.9xx (région Var)
  - **imageUrls**: URLs Wikimedia Commons
  - **name**: nom du POI
  - **categoryGroup**: Culture, Nature, etc
  - **osmId**: OpenStreetMap ID

### Dans l'App Flutter
1. `flutter run`
2. Page Carte
3. Zoomez Var (Provence)
4. Vérifiez les épingles apparaissent
5. Tapez pour voir détails + images

---

## Détails Techniques

### Normalization des Images
- **Input**: `"wikimedia_commons:File:Example.jpg"`
- **Output**: `"https://commons.wikimedia.org/wiki/Special:FilePath/Example.jpg"`
- Jusqu'à 5 URLs par POI

### Scripts Utilisés
- `import_osm_france.py`: Extraction Overpass API + rate limiting
- `import_to_firestore.py`: Import Firebase Admin SDK
- Déduplication automatique par osmId

---

## Prochaines Étapes

1. Importer les données (voir ci-dessus)
2. Tester dans l'app
3. Optionnel: importer autres départements
   ```bash
   bash scripts/run_all_categories.sh --department 75  # Paris
   ```

**Fichier:** `scripts/out/pois_all_categories_20260223_093423.json`
