# 🗺️ Scripts d'Import de POIs

Solution complète pour importer des POIs en France avec stratégie publique **gratuite et illimitée**.

## 📊 Stratégie Recommandée (sans Google)

| Source | Part | Coût | Avantages |
|--------|------|------|-----------|
| **OpenStreetMap** | ~75% | 🆓 Gratuit | Illimité, excellente couverture France |
| **UNESCO** | ~15% | 🆓 Gratuit | Patrimoine mondial (France + DOM-TOM) |
| **Data.gouv.fr** | ~10% | 🆓 Gratuit | Monuments historiques, musées officiels |

**Total: 100% GRATUIT** 🎉

---

## 🚀 Démarrage Rapide

### Option 1: Import Automatique Tout-en-Un

```bash
# Import public rapide (OSM + UNESCO + Data.gouv, sans Google)
python3 scripts/import_hybride.py

# Import par régions (OSM all-departments filtré)
python3 scripts/import_hybride.py \
  --regions ile_de_france provence_alpes_cote_dazur occitanie

# Import France entière métropole uniquement (sans DOM-TOM)
python3 scripts/import_hybride.py \
  --regions all \
  --no-domtom

# Import plus rapide sur villes majeures (au lieu all-departments)
python3 scripts/import_hybride.py --osm-mode cities --cities paris marseille lyon

# Catégories spécifiques
python3 scripts/import_hybride.py --categories culture histoire

# OSM uniquement
python3 scripts/import_hybride.py --skip-datagouv --skip-unesco
```

**⚡ En 1 commande** → Génère `pois_france_public.json` prêt pour Firestore !

---

## 🛠️ Scripts Individuels

### 1️⃣ OpenStreetMap (Base 80%)

**✅ Recommandé pour:** Toute la France, illimité

```bash
# Paris - Culture
python3 scripts/import_osm_france.py \
  --department 75 \
  --category culture \
  --radius 25000

# Marseille - Nature
python3 scripts/import_osm_france.py \
  --department 13 \
  --category nature \
  --radius 20000

# France entière + DOM-TOM (centres départements)
python3 scripts/import_osm_france.py \
  --all-departments \
  --category culture \
  --radius 20000

# Régions / départements ciblés
python3 scripts/import_osm_france.py \
  --departments 75,77,78,91,92,93,94,95 \
  --category culture \
  --radius 20000

# Inventaire complet départements + villes/villages
python3 scripts/import_osm_france.py \
  --all-departments \
  --catalog-output scripts/france_domtom_catalog.json \
  --catalog-only

# (Optionnel) Regénérer le fallback local 101 départements
python3 scripts/generate_departments_fallback.py
```

**Catégories disponibles:**
- `culture` → Musées, galeries, bibliothèques
- `nature` → Parcs, jardins, sites naturels
- `experienceGustative` → Restaurants, cafés, bars
- `histoire` → Monuments, châteaux, sites historiques
- `activites` → Attractions, loisirs, sports

**⚠️ Rate Limiting:** utilisez `--sleep-seconds` (ex: `1.5`) selon votre volume

---

### 2️⃣ Google Places (Qualité 20%)

**✅ Recommandé pour:** Grandes villes, photos HD

```bash
# Paris - Culture (50 POIs max)
python3 scripts/import_google_places.py \
  --city Paris \
  --location 48.8566,2.3522 \
  --category culture \
  --radius 20000 \
  --limit 50
```

**📍 Coordonnées des villes principales:**
- Paris: `48.8566,2.3522`
- Marseille: `43.2965,5.3698`
- Lyon: `45.7640,4.8357`
- Toulouse: `43.6047,1.4442`
- Nice: `43.7102,7.2620`
- Bordeaux: `44.8378,-0.5792`

**⚙️ Configuration requise:**
1. Obtenir une clé API: https://console.cloud.google.com/apis/credentials
2. Activer: Places API, Maps JavaScript API
3. Éditer `scripts/import_google_places.py` ligne 14:
   ```python
   GOOGLE_PLACES_API_KEY = "VOTRE_CLE_ICI"
   ```

**💰 Quota gratuit:** 200$/mois = ~12 000 requêtes  
**Coût/requête:** 0.017$ (Nearby Search + Details)

---

### 3️⃣ Data.gouv.fr (Données Publiques)

**✅ Recommandé pour:** Monuments, musées officiels

```bash
# Monuments historiques de Paris
python3 scripts/import_datagouv.py \
  --dataset monuments \
  --department 75

# Tous les musées de France
python3 scripts/import_datagouv.py \
  --dataset musees

# Tout (monuments + musées + équipements)
python3 scripts/import_datagouv.py \
  --dataset all \
  --department 13
```

**Datasets disponibles:**
- `monuments` → Liste officielle des Monuments Historiques
- `musees` → Musées de France labellisés
- `equipements` → Équipements sportifs et culturels
- `all` → Tous les datasets combinés

**🏛️ Sources officielles:**
- data.culture.gouv.fr
- Base Mérimée (architecture)
- Base Palissy (objets mobiliers)

---

### 4️⃣ UNESCO (Patrimoine Mondial)

**✅ Recommandé pour:** Sites UNESCO France + DOM-TOM (patrimoine culturel/naturel)

```bash
# Tous les sites UNESCO France (incl. DOM-TOM)
python3 scripts/import_unesco.py \
  --category tous \
  --output pois_unesco_france.json

# Filtrer par categorie de l'app
python3 scripts/import_unesco.py \
  --category nature \
  --output pois_unesco_nature.json
```

**Mapping categories UNESCO -> app:**
- Cultural -> `histoire`
- Natural -> `nature`
- Mixed -> `histoire`

**Notes:**
- Par defaut, le script filtre sur le pays `France` (inclut les sites DOM-TOM)
- Les sites transfrontaliers sont inclus si `France` fait partie des pays
- Si l'API UNESCO bloque les requetes automatisées (403), le script bascule automatiquement sur un fallback Wikidata (sites UNESCO France)

---

### 5️⃣ Decathlon Outdoor (Itinéraires)

**✅ Recommandé pour:** Randonnée, vélo, trail, activités outdoor

```bash
# Méthode 1: Export manuel (recommandé)
# 1. Aller sur https://www.decathlon-outdoor.com
# 2. Explorer et exporter vos itinéraires favoris au format JSON
# 3. Importer:
python3 scripts/import_decathlon_outdoor.py \
  --method manual \
  --file itineraires_alpes.json

# Méthode 2: Par région (si API disponible)
python3 scripts/import_decathlon_outdoor.py \
  --method region \
  --region "Alpes" \
  --activity hiking

# Méthode 3: Par coordonnées
python3 scripts/import_decathlon_outdoor.py \
  --method api \
  --location 45.9237,6.8694 \
  --activity trail \
  --radius 50000
```

**Activités disponibles:**
- `hiking` → Randonnée (catégorie: nature)
- `trail` → Trail running (catégorie: activites)
- `cycling` → Vélo route (catégorie: activites)
- `mountain-bike` → VTT (catégorie: activites)
- `climbing` → Escalade (catégorie: activites)
- `via-ferrata` → Via ferrata (catégorie: activites)
- `skiing` → Ski (catégorie: activites)

**🏔️ Avantages:**
- Itinéraires vérifiés par la communauté
- Données riches: distance, dénivelé, durée
- Photos d'utilisateurs
- Difficulté et notes

**⚠️ Notes:**
- L'API publique peut être limitée
- Export manuel recommandé pour débuter
- Alternative: AllTrails, Visorando, Openrunner

---

## 🔥 Import dans Firestore

```bash
# Méthode recommandée: Firebase Admin SDK (Node.js)
node scripts/import_to_firestore.js pois_france_complet.json

# Nettoyage des doublons déjà présents (dry-run)
node scripts/dedupe_firestore_spots.js

# Nettoyage effectif + backup JSON
node scripts/dedupe_firestore_spots.js --apply --backup scripts/out/duplicates_backup.json

# Nettoyage des noms placeholders (dry-run)
python3 scripts/clean_poi_placeholder_names.py

# Nettoyage effectif des noms placeholders
python3 scripts/clean_poi_placeholder_names.py --apply

# Nettoyage effectif + backup JSON des changements
python3 scripts/clean_poi_placeholder_names.py \
  --apply \
  --backup scripts/out/poi_name_cleanup_backup.json

# Audit global (doublons + POI sans nom) en dry-run
python3 scripts/audit_cleanup_spots.py \
  --report scripts/out/spots_audit_report.json

# Nettoyage global effectif (avec backup des suppressions)
python3 scripts/audit_cleanup_spots.py \
  --apply \
  --backup scripts/out/spots_cleanup_backup.json \
  --report scripts/out/spots_cleanup_report.json

# Test sur un échantillon
python3 scripts/clean_poi_placeholder_names.py --limit 500
```

**Structure Firestore générée:**
```javascript
spots/{spotId} {
  name: "Musée du Louvre",
  description: "Musée d'art et d'antiquités",
  location: {
    _latitude: 48.8606,
    _longitude: 2.3376
  },
  category: "culture",
  city: "Paris",
  images: ["url1", "url2"],
  rating: 4.7,
  website: "https://...",
  isPublic: true,
  isValidated: true,
  source: "google_places",  // ou "osm" ou "datagouv_monuments"
  createdAt: Timestamp
}
```

---

## 📈 Plan d'Import Complet

### Phase 1: Grandes Métropoles (Semaine 1)

**Villes prioritaires avec Google Places:**
```bash
python3 scripts/import_hybride.py \
  --cities paris marseille lyon bordeaux nice toulouse
```

**Résultat attendu:**
- ~3 000 POIs (80% OSM + 20% Google)
- Coût: ~50$ sur quota gratuit
- Temps: ~2 heures (avec rate limiting)

---

### Phase 2: Villes Moyennes (Semaine 2)

**OSM uniquement (gratuit):**
```bash
python3 scripts/import_hybride.py \
  --cities nantes strasbourg montpellier lille \
  --skip-google
```

**Résultat attendu:**
- ~2 000 POIs (100% OSM)
- Coût: 0€
- Temps: ~1 heure

---

### Phase 3: Couverture Nationale (Semaines 3-4)

**Import national (métropole + outre-mer):**
```bash
# Passage par centre de département (rapide)
python3 scripts/import_osm_france.py \
  --all-departments \
  --category culture \
  --radius 20000 \
  --sleep-seconds 1.5

# Maillage fin: villes/villages (plus long, meilleure couverture)
python3 scripts/import_osm_france.py \
  --all-departments \
  --use-communes \
  --communes-limit 0 \
  --category nature \
  --radius 8000 \
  --sleep-seconds 1.5
```

**Résultat attendu:**
- couverture France + DOM-TOM
- Coût: 0€ (OSM seulement)
- Temps: variable selon maillage communes/villages

---

## ⚙️ Configuration Avancée

### Variables d'Environnement

```bash
# .env
GOOGLE_PLACES_API_KEY=votre_cle_api
FIREBASE_PROJECT=allspots
OSM_RATE_LIMIT=60  # secondes entre requêtes
```

### Personnalisation des Catégories

Éditer `import_osm_france.py` lignes 15-53 pour modifier les tags OSM:

```python
CATEGORY_QUERIES = {
    'culture': {
        'tourism': ['museum', 'gallery', 'artwork'],
        'amenity': ['library', 'theatre', 'arts_centre'],
        # ... ajouter vos tags
    }
}
```

---

## 📊 Statistiques & Limites

### OpenStreetMap
- ✅ Requêtes: Illimitées
- ✅ POIs: ~500 000 en France
- ⚠️ Rate limit: 1 requête/60s recommandé
- ⚠️ Photos: Qualité variable

### Google Places API
- ✅ Quota gratuit: 200$/mois
- ✅ Photos: Haute qualité
- ⚠️ Limite mensuelle: ~12 000 POIs
- 💰 Au-delà: 0.017$/POI

### Data.gouv.fr
- ✅ Données: Illimitées
- ✅ Qualité: Officielle (État)
- ⚠️ Types limités: Monuments, musées
- ⚠️ Pas de photos

---

## 🐛 Dépannage

### Erreur: "GOOGLE_PLACES_API_KEY non configurée"
```bash
# Éditer le script
nano scripts/import_google_places.py
# Ligne 14: GOOGLE_PLACES_API_KEY = "VOTRE_CLE"
```

### Erreur: "Rate limit exceeded" (OSM)
```bash
# Augmenter le délai entre requêtes
# Dans import_hybride.py, ligne 260:
time.sleep(120)  # 2 minutes au lieu de 60s
```

### Erreur: "No data found" (Data.gouv.fr)
```bash
# Vérifier la disponibilité des datasets:
curl "https://data.culture.gouv.fr/api/explore/v2.1/catalog/datasets"
```

### POIs dupliqués
```bash
# Le script déduplique automatiquement par nom + position
# Pour nettoyer manuellement:
python3 -c "
import json
data = json.load(open('pois_france_complet.json'))
seen = set()
unique = []
for poi in data:
    key = f\"{poi['name']}_{poi['location']['_latitude']:.4f}\"
    if key not in seen:
        seen.add(key)
        unique.append(poi)
json.dump(unique, open('pois_clean.json', 'w'), indent=2, ensure_ascii=False)
"
```

---

## 📝 Exemples Complets

### Exemple 1: Import Rapide Paris
```bash
# 1. OSM (base)
python3 scripts/import_osm_france.py \
  --department 75 \
  --category culture \
  --output pois_paris_culture.json

# 2. Google Places (photos HD)
python3 scripts/import_google_places.py \
  --city Paris \
  --location 48.8566,2.3522 \
  --category culture \
  --limit 30 \
  --output pois_paris_google.json

# 3. Fusion manuelle
python3 -c "
import json
osm = json.load(open('pois_paris_culture.json'))
google = json.load(open('pois_paris_google.json'))
merged = osm + google
json.dump(merged, open('pois_paris_final.json', 'w'), indent=2, ensure_ascii=False)
"

# 4. Import Firestore
firebase firestore:import pois_paris_final.json --project allspots
```

### Exemple 2: Import Automatique Multi-Villes
```bash
# Toutes les catégories pour Paris, Lyon, Marseille
python3 scripts/import_hybride.py \
  --cities paris lyon marseille \
  --categories all

# Résultat: pois_france_complet.json (prêt à importer)
```

### Exemple 3: Import Monuments Historiques France
```bash
# Tous les monuments de France
python3 scripts/import_datagouv.py \
  --dataset monuments \
  --output monuments_france.json

# Import dans Firestore
firebase firestore:import monuments_france.json --project allspots
```

---

## 📚 Ressources

- [OpenStreetMap Overpass API](https://overpass-api.de/)
- [Google Places API](https://developers.google.com/maps/documentation/places/web-service)
- [Data.gouv.fr Datasets](https://www.data.gouv.fr/fr/datasets/)
- [Firebase Firestore Import](https://firebase.google.com/docs/firestore/manage-data/import-export)

---

## 📄 Licence

- **OpenStreetMap**: ODbL (mention requise dans l'app)
- **Google Places**: Google Maps ToS (API key requise)
- **Data.gouv.fr**: Licence Ouverte 2.0 (gratuit, libre usage)

**⚖️ Attribution requise dans l'app:**
```
Données cartographiques © OpenStreetMap contributors
Lieu informations © Google Places API
Monuments historiques © Ministère de la Culture
```

---

## 🎯 Résumé Exécutif

**Pour importer rapidement toute la France:**

```bash
# 1. Configuration (une seule fois)
nano scripts/import_google_places.py  # Ajouter clé API Google (optionnel)

# 2. Import complet (automatic)
python3 scripts/import_hybride.py

# 3. Import dans Firestore
firebase firestore:import pois_france_complet.json --project allspots
```

**Résultat:**
- ✅ 10 000+ POIs en France
- ✅ 100% gratuit (dans quota)
- ✅ Photos HD (villes majeures)
- ✅ Données officielles (monuments)
- ✅ Prêt en 2-3 heures

**💡 Conseil:** Commencer avec `--cities paris --skip-google` pour tester rapidement (5 min).
