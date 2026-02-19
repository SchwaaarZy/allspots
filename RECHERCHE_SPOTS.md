# Système de Recherche Intelligente de Spots

## 🎯 Vue d'ensemble

AllSpots combine deux sources de données pour offrir une expérience de recherche complète:

1. **Spots créés par les utilisateurs** (Firestore)
2. **Lieux publics** (Google Places API)

Le système filtre automatiquement les résultats selon les **préférences de l'utilisateur** pour explorer des lieux alignés avec ses intérêts.

---

## 📍 Comment ça marche

### 1. Préférences utilisateur
Chaque utilisateur configure ses intérêts dans son profil:
- 🏛️ Patrimoine et Histoire
- 🌳 Nature
- 🎨 Culture
- 🍽️ Expérience gustative
- ⛰️ Activités plein air

### 2. Flux de recherche

```
Utilisateur configure ses préférences
         ↓
Recherche initiée (Carte ou Recherche)
         ↓
MapController récupère les préférences
         ↓
Critères appliqués aux deux répos (Firestore + Google Places)
         ↓
Résultats fusionnés et triés par distance
         ↓
Affichage: spots communautaires + Google Places
```

### 3. Filtrage par catégories

#### ✅ Les spots Firestore
- Quand l'utilisateur crée un spot, il choisit une catégorie
- La recherche filtre sur `categoryGroup` en Firestore
- Exemple: "Culture" → affiche musées, galeries, lieux culturels

#### ✅ Les lieux Google Places
- Google retourne les types de lieux: `restaurant`, `museum`, `park`, etc.
- Notre système mappe intelligemment ces types aux catégories AllSpots
- Exemple: 
  - `museum` → 🏛️ Culture
  - `restaurant`, `bar`, `cafe` → 🍽️ Expérience gustative
  - `park`, `camping` → 🌳 Nature
  - `church`, `castle` → 🏛️ Patrimoine et Histoire
  - `gym`, `amusement_park` → ⛰️ Activités plein air

---

## 🔍 Mapping Google Places → AllSpots

### Culture (🎨)
- `museum`, `art_gallery`, `tourist_attraction`
- `historical_museums`, `history_museums`

### Nature (🌳)
- `park`, `campground`, `natural_feature`
- `scenic_viewpoint`, `zoo`

### Patrimoine & Histoire (🏛️)
- `church`, `place_of_worship`
- `hindu_temple`, `mosque`, `synagogue`
- `cemetery`, `castle`

### Expérience Gustative (🍽️)
- `restaurant`, `bar`, `cafe`, `bakery`
- `brewery`, `wine_bar`, `meal_delivery`
- `liquor_store`, `food`

### Activités (⛰️)
- `amusement_park`, `gym`, `bowling_alley`
- `movie_theater`, `night_club`, `sports_complex`
- `stadium`, `swimming_pool`, `hiking_area`

---

## 💡 Fonctionnalités

### ✅ Auto-filtrage par préférences
Quand un utilisateur configure ses intérêts dans son profil, la carte se met à jour automatiquement pour afficher uniquement les spots pertinents.

### ✅ Spots créés par utilisateurs
Les utilisateurs peuvent créer des spots géolocalisés pour:
- Partager des découvertes
- Enrichir la base de données
- Ajouter des lieux non listés sur Google Places

### ✅ Recherche avancée
Page de recherche avec:
- Rayon de recherche ajustable
- Filtre "Ouvert maintenant"
- Sélection de catégories
- Affichage du nombre de résultats

### ✅ Intégration double source
- Les spots communautaires apparemment sous le label "🏘️ Spots communautaires"
- Les lieux Google Places sous "🗺️ Google Places"
- Tri automatique par distance

---

## 🔧 Architecture technique

### Fichiers clés

- **`places_poi_repository.dart`**: Logique de recherche Google Places + mapping
- **`firestore_poi_repository.dart`**: Requête à la base de données utilisateurs
- **`mixed_poi_repository.dart`**: Fusion des résultats Firestore + Google Places
- **`map_controller.dart`**: Orchestration des recherches et gestion des préférences
- **`poi_filters.dart`**: Définition des critères de filtrage

### Flux de données

```
MapController.init()
  ├─ _determinePosition() → Localisation utilisateur
  └─ refreshNearby() → Récupère les POIs
       ├─ FirestorePoiRepository.getNearbyPois()
       │   ├─ Query Firestore (spots publics)
       │   └─ Filtre par catégories
       ├─ PlacesPoiRepository.getNearbyPois()
       │   ├─ Google Places search nearby
       │   ├─ Map types → Catégories AllSpots
       │   └─ Filtre par catégories
       └─ MixedPoiRepository → Fusion & déduplication
            └─ Résultats triés par distance
```

---

## 🚀 Améliorations futures

- [ ] Intégration paiements (pass premium 1€)
- [ ] Système de favoris
- [ ] Modifications de spots
- [ ] Système de notation/avis
- [ ] Recherche par mots-clés personnalisés
- [ ] Filtres avancés (PMR, famille, gratuit)
- [ ] Historique de visites
- [ ] Partage de circuits touristiques

---

## 📚 Notes pour les développeurs

### Ajouter une nouvelle catégorie

1. Ajouter l'enum dans `poi_category.dart`
2. Ajouter le groupe dans `poi_categories.dart`
3. Mettre à jour le mapping dans `places_poi_repository.dart`
4. Mettre à jour `firestore_poi_repository.dart`

### Tester les résultats Google Places

```bash
flutter run -d <device> --dart-define=PLACES_API_KEY=<your_key>
```

Assurez-vous que la clé API a les APIs habilitées:
- Google Maps API
- Places API
