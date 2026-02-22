# 🏔️ Sources d'Itinéraires Outdoor

Guide complet pour importer des itinéraires de randonnée, vélo, trail et autres activités outdoor.

---

## 📊 Comparaison des Sources

| Source | POIs France | API | Coût | Qualité | Recommandation |
|--------|-------------|-----|------|---------|----------------|
| **Decathlon Outdoor** | 50 000+ | ❓ Limitée | 🆓 Gratuit | ⭐⭐⭐⭐ | Export manuel |
| **AllTrails** | 30 000+ | ❌ Non | 💰 Premium | ⭐⭐⭐⭐⭐ | Scraping autorisé ? |
| **Visorando** | 20 000+ | ❌ Non | 🆓 Gratuit | ⭐⭐⭐⭐ | Export manuel |
| **Openrunner** | 100 000+ | ❌ Non | 🆓 Gratuit | ⭐⭐⭐ | Export GPX |
| **Komoot** | 50 000+ | ✅ Oui | 💰 API | ⭐⭐⭐⭐ | API payante |
| **Outdooractive** | 40 000+ | ✅ Oui | 💰 API | ⭐⭐⭐⭐ | API payante |
| **OpenStreetMap** | ∞ | ✅ Oui | 🆓 Gratuit | ⭐⭐⭐ | Déjà implémenté |

**✅ Recommandation:** Decathlon Outdoor + Visorando + OpenStreetMap

---

## 1️⃣ Decathlon Outdoor

### 🌐 Site Web
https://www.decathlon-outdoor.com

### 📱 Application
- iOS: https://apps.apple.com/fr/app/decathlon-outdoor/id1447067403
- Android: https://play.google.com/store/apps/details?id=com.geonaute.decathlonoutdoor

### 📊 Statistiques
- **50 000+ itinéraires** en France
- Activités: Randonnée, Trail, VTT, Vélo route, Ski, Raquettes
- Données communautaires vérifiées
- Photos, avis, difficulté, dénivelé

### 🔧 Méthodes d'Import

#### Méthode A: Export Manuel (Recommandé)

1. **Accéder au site**
   ```bash
   open https://www.decathlon-outdoor.com/fr-fr/explore
   ```

2. **Sélectionner une région** (ex: Alpes, Pyrénées, Bretagne)

3. **Filtrer par activité** (randonnée, VTT, etc.)

4. **Exporter les données**
   - Option 1: Si export JSON disponible dans l'interface
   - Option 2: Via DevTools du navigateur (F12):
     ```javascript
     // Dans la console du navigateur
     copy(JSON.stringify(routes))
     ```

5. **Importer avec le script**
   ```bash
   python3 scripts/import_decathlon_outdoor.py \
     --method manual \
     --file decathlon_export.json \
     --output pois_decathlon.json
   ```

#### Méthode B: API (Si Disponible)

```bash
python3 scripts/import_decathlon_outdoor.py \
  --method api \
  --location 45.9237,6.8694 \
  --activity hiking \
  --radius 50000
```

#### Méthode C: Export GPX

1. Télécharger les itinéraires au format GPX depuis l'app
2. Convertir GPX → JSON:
   ```bash
   pip3 install gpxpy
   python3 scripts/convert_gpx_to_json.py decathlon.gpx
   ```

### 📂 Régions Prioritaires

```bash
# Alpes (Haute-Savoie, Savoie, Isère)
# → Catégories: nature, activites
# → ~10 000 itinéraires

# Pyrénées (Pyrénées-Atlantiques, Hautes-Pyrénées)
# → Catégories: nature, activites
# → ~5 000 itinéraires

# Corse
# → Catégories: nature
# → ~3 000 itinéraires

# Bretagne (Côtes-d'Armor, Finistère)
# → Catégories: nature
# → ~4 000 itinéraires
```

---

## 2️⃣ Visorando

### 🌐 Site Web
https://www.visorando.com

### 📊 Statistiques
- **20 000+ randonnées** en France
- Communauté active française
- Cartes IGN intégrées
- Descriptions détaillées

### 🔧 Import

#### Export Manuel

1. **Rechercher par département**
   ```
   https://www.visorando.com/randonnee-{departement}.html
   ```
   Exemple: https://www.visorando.com/randonnee-haute-savoie.html

2. **Exporter les traces GPX**
   - Chaque fiche dispose d'un lien de téléchargement GPX
   - Télécharger en masse avec script:
   ```bash
   # Extraire les URLs GPX de la page
   curl "https://www.visorando.com/randonnee-haute-savoie.html" | \
     grep -o 'href="[^"]*\.gpx"' | \
     sed 's/href="//;s/"$//' > gpx_urls.txt
   
   # Télécharger tous les GPX
   while read url; do
     wget "https://www.visorando.com$url"
     sleep 1
   done < gpx_urls.txt
   ```

3. **Convertir en POIs**
   ```bash
   python3 scripts/import_visorando.py \
     --gpx-folder ./gpx_visorando/ \
     --output pois_visorando.json
   ```

### ⚖️ Conditions d'Utilisation
- ✅ Usage personnel autorisé
- ⚠️ Vérifier les CGU pour usage commercial
- ✅ Attribution requise: "Itinéraire Visorando"

---

## 3️⃣ Openrunner

### 🌐 Site Web
https://www.openrunner.com

### 📊 Statistiques
- **100 000+ parcours** (France et Europe)
- Tous types d'activités outdoor
- Données communautaires ouvertes
- Export GPX facile

### 🔧 Import

```bash
# Recherche par zone et export GPX
# Puis conversion avec script générique
python3 scripts/convert_gpx_batch.py \
  --folder ./openrunner_gpx/ \
  --output pois_openrunner.json
```

---

## 4️⃣ AllTrails

### 🌐 Site Web
https://www.alltrails.com/fr

### 📊 Statistiques
- **30 000+ sentiers** en France
- Meilleure qualité photos et avis
- Application très populaire

### ⚠️ Limitations
- API non publique
- Scraping potentiellement interdit
- Version Premium requise pour certaines fonctionnalités

### 🔧 Alternative
Utiliser comme référence pour enrichir les données OSM/Decathlon avec photos et avis.

---

## 🛠️ Script de Conversion GPX Universel

J'ai créé un convertisseur GPX universel pour toutes ces sources:

```bash
# Convertir un dossier de fichiers GPX
python3 scripts/convert_gpx_to_json.py \
  --input-folder ./mes_gpx/ \
  --output pois_outdoor.json \
  --category nature \
  --source visorando
```

### Features
- ✅ Parse tous les formats GPX standards
- ✅ Extrait: nom, description, distance, dénivelé
- ✅ Calcule les statistiques si manquantes
- ✅ Détecte automatiquement les waypoints d'intérêt
- ✅ Export Firestore-ready

---

## 📋 Plan d'Import Complet

### Phase 1: Massifs Montagneux (Nature + Activités)

```bash
# Alpes
python3 scripts/import_decathlon_outdoor.py --region "Alpes" --activity hiking
python3 scripts/import_decathlon_outdoor.py --region "Alpes" --activity mountain-bike

# Pyrénées
python3 scripts/import_decathlon_outdoor.py --region "Pyrénées" --activity hiking

# Vosges, Jura, Massif Central
# (via export manuel ou Visorando)
```

**Résultat attendu:** ~15 000 POIs nature/activités

---

### Phase 2: Littoral (Nature)

```bash
# Bretagne
python3 scripts/import_visorando.py --region "Bretagne" --type "coastal"

# Côte d'Azur
python3 scripts/import_decathlon_outdoor.py --region "PACA" --activity walking

# Normandie, Vendée
# (via Visorando)
```

**Résultat attendu:** ~5 000 POIs nature

---

### Phase 3: Tourisme Urbain (VTT, Trail)

```bash
# Forêts péri-urbaines (Fontainebleau, etc.)
python3 scripts/import_openrunner.py --type "trail" --near-city "Paris"

# Parcs nationaux
# (via Data.gouv.fr + Decathlon Outdoor)
```

**Résultat attendu:** ~3 000 POIs activités

---

## 🔗 Ressources Complémentaires

### APIs Payantes (Pour Production)

| Service | Prix | POIs | Qualité |
|---------|------|------|---------|
| Outdooractive API | €500/mois | 100K+ | ⭐⭐⭐⭐⭐ |
| Komoot API | €300/mois | 50K+ | ⭐⭐⭐⭐ |
| Mapbox Terrain | €0.50/1K | Custom | ⭐⭐⭐⭐ |

### Datasets Ouverts

- **Refuges.info**: https://www.refuges.info/api/
  - Refuges, cabanes, sources en montagne
  - API gratuite et ouverte
  
- **PNR (Parcs Naturels Régionaux)**
  - Chaque parc a ses propres données
  - Exemple: https://geoportail.pnr-oise-paysdefrance.fr/

- **IGN Rando**
  - https://ignrando.fr
  - Itinéraires officiels

---

## 🎯 Stratégie Recommandée (100% Gratuit)

### Mix Optimal

```
60% - OpenStreetMap (sentiers, chemins)
15% - Decathlon Outdoor (itinéraires vérifiés)
10% - Visorando (randos populaires)
10% - Data.gouv.fr (patrimoine naturel)
5%  - Refuges.info (refuges montagne)
```

### Commandes Complètes

```bash
# 1. Base OSM (déjà fait)
python3 scripts/import_osm_france.py --all-france

# 2. Decathlon Outdoor (export manuel)
# → Exporter depuis le site web
python3 scripts/import_decathlon_outdoor.py --file export.json

# 3. Visorando (top départements)
for dept in 74 73 05 06 64 65 2A 2B; do
  python3 scripts/import_visorando.py --department $dept
done

# 4. Refuges.info
python3 scripts/import_refuges.py --all-france

# 5. Fusion
python3 scripts/merge_all_sources.py --output pois_outdoor_complet.json
```

**Résultat:** ~25 000 POIs outdoor pour toute la France, 100% gratuit

---

## 📄 Licence et Attribution

### Obligations Légales

**Dans l'app AllSpots, section "À propos":**

```
🗺️ Données cartographiques
• OpenStreetMap © Contributeurs OSM
• Decathlon Outdoor © Communauté Decathlon
• Visorando © Visorando
• Data.gouv.fr © État français (Licence Ouverte 2.0)
• Refuges.info © WRI
```

**CGU à respecter:**
- ✅ OpenStreetMap: ODbL (attribution requise)
- ✅ Visorando: Usage personnel OK, vérifier pour commercial
- ✅ Decathlon: Données communautaires, vérifier CGU
- ✅ Data.gouv.fr: Licence Ouverte 2.0 (libre)

---

## 🆘 Support

**Problème d'import ?**

1. Vérifier le format du fichier source
2. Tester avec un petit échantillon
3. Consulter les logs d'erreur
4. Issue GitHub: https://github.com/SchwaaarZy/allspots/issues

**Questions fréquentes:**

**Q: Puis-je scraper AllTrails ?**
R: Non recommandé, vérifier leurs CGU. Utiliser plutôt les sources ouvertes.

**Q: API Decathlon Outdoor disponible ?**
R: Pas d'API publique documentée pour l'instant. Utiliser l'export manuel.

**Q: Combien de POIs outdoor pour la France ?**
R: Estimation réaliste: 20-25K avec toutes les sources gratuites.

**Q: Quel est le meilleur compromis qualité/temps ?**
R: Decathlon Outdoor (export manuel) + OSM = 80% de la valeur en 2h de travail.
