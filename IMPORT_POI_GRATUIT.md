# Import gratuit de POIs en France

## 🎯 Objectif
Peupler Firestore avec des POIs français sans payer Google Places API.

## ✅ Solutions gratuites

### 1. OpenStreetMap via Overpass API (Recommandé)

**Avantages:**

- 100% gratuit
- Données open source
- Qualité excellente en France
- Pas de clé API nécessaire

**Limites:**

- Rate limit: 2 requêtes/seconde
- Timeout: 180 secondes max par requête
- Photos limitées (liens Wikimedia Commons)

**Usage:**

```bash
# Installer les dépendances
pip3 install requests

# Paris - Culture
python scripts/import_osm_france.py --department 75 --category culture --radius 20000

# Marseille - Nature
python scripts/import_osm_france.py --department 13 --category nature --radius 15000

# Lyon - Restaurants
python scripts/import_osm_france.py --department 69 --category experienceGustative
```

### 2. Google Places API (Quota gratuit)

**Quota gratuit:** 200$/mois = ~2000 requêtes

**Stratégie:**

1. Utiliser le quota pour les grandes villes uniquement
2. Compléter avec OSM pour le reste
3. Faire des requêtes "Nearby Search" ciblées

**Code exemple:**

```dart
// lib/scripts/import_google_places.dart
import 'package:http/http.dart' as http;

Future<void> importGooglePlaces(double lat, double lng) async {
  const apiKey = 'VOTRE_CLE_API';
  const radius = 5000;
  const type = 'tourist_attraction';
  
  final url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
      '?location=$lat,$lng&radius=$radius&type=$type&key=$apiKey';
  
  final response = await http.get(Uri.parse(url));
  // Traiter et sauvegarder dans Firestore...
}
```

### 3. Datasets publics français

**Sources gratuites:**

1. **data.gouv.fr**
   - Base nationale des équipements
   - Monuments historiques
   - https://www.data.gouv.fr/fr/datasets/

2. **Datatourisme**
   - POIs touristiques français
   - https://www.datatourisme.gouv.fr/

3. **Base Mérimée (Monuments)**
   - [Accéder au dataset](https://data.culture.gouv.fr/explore/dataset/liste-des-immeubles-proteges-au-titre-des-monuments-historiques/)

**Import CSV:**

```python
import csv
import json

def import_csv_to_firestore(csv_file):
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            poi = {
                'name': row['nom'],
                'lat': float(row['latitude']),
                'lng': float(row['longitude']),
                'description': row['description'],
                # ...
            }
            print(json.dumps(poi))
```

## 📋 Plan d'import région par région

### Ordre recommandé (par population):

1. **Île-de-France:**
   ```bash
   python import_osm_france.py --department 75 --category culture --radius 25000
   python import_osm_france.py --department 92 --category experienceGustative
   python import_osm_france.py --department 93 --category nature
   ```

2. **Provence-Alpes-Côte d'Azur:**
   ```bash
   python import_osm_france.py --department 13 --category nature
   python import_osm_france.py --department 06 --category culture
   ```

3. **Auvergne-Rhône-Alpes:**
   ```bash
   python import_osm_france.py --department 69 --category experienceGustative
   python import_osm_france.py --department 38 --category nature
   ```

### Rythme d'import:

⏱️ **Respecter le rate limit OSM:**

- 1 requête par départment
- Attendre 60 secondes entre chaque
- Éviter les heures de pointe (12h-14h, 18h-20h UTC)

## 🚀 Import dans Firestore

### Option 1: Firebase CLI

```bash
# Installer Firebase tools
npm install -g firebase-tools

# Se connecter
firebase login

# Importer
firebase firestore:import pois_import.json --project allspots
```

### Option 2: Script Node.js

```javascript
const admin = require('firebase-admin');
const fs = require('fs');

admin.initializeApp();
const db = admin.firestore();

async function importPOIs(jsonFile) {
  const pois = fs.readFileSync(jsonFile, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map(line => JSON.parse(line));
  
  const batch = db.batch();
  
  for (const poi of pois) {
    const ref = db.collection('spots').doc();
    batch.set(ref, poi);
  }
  
  await batch.commit();
  console.log(`✅ ${pois.length} POIs importés`);
}

importPOIs('pois_import.json');
```

## 💰 Comparaison des coûts

| Source | Coût | POIs/mois | Qualité photos |
|--------|------|-----------|----------------|
| **OpenStreetMap** | Gratuit | Illimité* | Moyenne |
| **Google Places** | 200$/mois gratuit | ~2000 | Excellente |
| **Data.gouv.fr** | Gratuit | Illimité | Variable |

*Limité par le rate limit uniquement

## ⚖️ Aspects légaux

### ✅ Autorisé:

- Utiliser OpenStreetMap (licence ODbL)
- Utiliser data.gouv.fr (licence ouverte)
- Quota gratuit Google Places

### ❌ Interdit:

- Scraper Google Maps (violation TOS)
- Dépasser les quotas Google sans payer
- Revendre les données sans attribution

### 📜 Attribution requise:

Pour OpenStreetMap, ajoutez dans votre app:
```dart
// Déjà fait! Widget OsmAttribution supprimé mais légalement...
// Vous DEVEZ mentionner OSM quelque part (À propos, CGU, etc.)
```

## 🎯 Recommandation finale

**Stratégie hybride:**

1. **OSM pour** 80% des POIs (gratuit, illimité)
2. **Google Places pour** 20% des grandes villes (photos de qualité)
3. **Data.gouv.fr pour** monuments/équipements publics

Cette approche maximise la qualité tout en restant gratuite! 🚀

## 📞 Support

Questions? Regardez:

- Documentation OSM: [wiki.openstreetmap.org](https://wiki.openstreetmap.org/)
- Overpass API: [overpass-api.de](https://overpass-api.de/)
- Google Places API: [Google Documentation](https://developers.google.com/maps/documentation/places/)
