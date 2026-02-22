# 🗺️ Départements Français - Référence

Codes département pour les scripts d'import.

## 🏙️ Grandes Métropoles

| Ville | Département | Code | Coordonnées |
|-------|-------------|------|-------------|
| Paris | Paris | 75 | 48.8566,2.3522 |
| Marseille | Bouches-du-Rhône | 13 | 43.2965,5.3698 |
| Lyon | Rhône | 69 | 45.7640,4.8357 |
| Toulouse | Haute-Garonne | 31 | 43.6047,1.4442 |
| Nice | Alpes-Maritimes | 06 | 43.7102,7.2620 |
| Nantes | Loire-Atlantique | 44 | 47.2184,-1.5536 |
| Strasbourg | Bas-Rhin | 67 | 48.5734,7.7521 |
| Montpellier | Hérault | 34 | 43.6108,3.8767 |
| Bordeaux | Gironde | 33 | 44.8378,-0.5792 |
| Lille | Nord | 59 | 50.6292,3.0573 |

## 🇫🇷 Tous les Départements

### Île-de-France
- 75 - Paris
- 77 - Seine-et-Marne
- 78 - Yvelines
- 91 - Essonne
- 92 - Hauts-de-Seine
- 93 - Seine-Saint-Denis
- 94 - Val-de-Marne
- 95 - Val-d'Oise

### Auvergne-Rhône-Alpes
- 01 - Ain
- 03 - Allier
- 07 - Ardèche
- 15 - Cantal
- 26 - Drôme
- 38 - Isère
- 42 - Loire
- 43 - Haute-Loire
- 63 - Puy-de-Dôme
- 69 - Rhône
- 73 - Savoie
- 74 - Haute-Savoie

### Provence-Alpes-Côte d'Azur
- 04 - Alpes-de-Haute-Provence
- 05 - Hautes-Alpes
- 06 - Alpes-Maritimes
- 13 - Bouches-du-Rhône
- 83 - Var
- 84 - Vaucluse

### Occitanie
- 09 - Ariège
- 11 - Aude
- 12 - Aveyron
- 30 - Gard
- 31 - Haute-Garonne
- 32 - Gers
- 34 - Hérault
- 46 - Lot
- 48 - Lozère
- 65 - Hautes-Pyrénées
- 66 - Pyrénées-Orientales
- 81 - Tarn
- 82 - Tarn-et-Garonne

### Nouvelle-Aquitaine
- 16 - Charente
- 17 - Charente-Maritime
- 19 - Corrèze
- 23 - Creuse
- 24 - Dordogne
- 33 - Gironde
- 40 - Landes
- 47 - Lot-et-Garonne
- 64 - Pyrénées-Atlantiques
- 79 - Deux-Sèvres
- 86 - Vienne
- 87 - Haute-Vienne

### Bretagne
- 22 - Côtes-d'Armor
- 29 - Finistère
- 35 - Ille-et-Vilaine
- 56 - Morbihan

### Pays de la Loire
- 44 - Loire-Atlantique
- 49 - Maine-et-Loire
- 53 - Mayenne
- 72 - Sarthe
- 85 - Vendée

### Hauts-de-France
- 02 - Aisne
- 59 - Nord
- 60 - Oise
- 62 - Pas-de-Calais
- 80 - Somme

### Grand Est
- 08 - Ardennes
- 10 - Aube
- 51 - Marne
- 52 - Haute-Marne
- 54 - Meurthe-et-Moselle
- 55 - Meuse
- 57 - Moselle
- 67 - Bas-Rhin
- 68 - Haut-Rhin
- 88 - Vosges

### Normandie
- 14 - Calvados
- 27 - Eure
- 50 - Manche
- 61 - Orne
- 76 - Seine-Maritime

### Centre-Val de Loire
- 18 - Cher
- 28 - Eure-et-Loir
- 36 - Indre
- 37 - Indre-et-Loire
- 41 - Loir-et-Cher
- 45 - Loiret

### Bourgogne-Franche-Comté
- 21 - Côte-d'Or
- 25 - Doubs
- 39 - Jura
- 58 - Nièvre
- 70 - Haute-Saône
- 71 - Saône-et-Loire
- 89 - Yonne
- 90 - Territoire de Belfort

### Corse
- 2A - Corse-du-Sud
- 2B - Haute-Corse

### DOM-TOM
- 971 - Guadeloupe
- 972 - Martinique
- 973 - Guyane
- 974 - La Réunion
- 976 - Mayotte

## 📝 Exemples d'Utilisation

### Import d'une ville
```bash
# Paris (75)
python3 scripts/import_osm_france.py --department 75 --category culture

# Marseille (13)
python3 scripts/import_osm_france.py --department 13 --category nature
```

### Import d'une région complète
```bash
# Île-de-France (tous les départements)
for dept in 75 77 78 91 92 93 94 95; do
  python3 scripts/import_osm_france.py --department $dept --category culture
  sleep 60
done

# PACA (tous les départements)
for dept in 04 05 06 13 83 84; do
  python3 scripts/import_osm_france.py --department $dept --category nature
  sleep 60
done
```

### Import de plusieurs catégories
```bash
# Paris - Toutes les catégories
for category in culture nature experienceGustative histoire activites; do
  python3 scripts/import_osm_france.py \
    --department 75 \
    --category $category \
    --output "pois_paris_$category.json"
  sleep 60
done
```

## 🎯 Stratégie d'Import Recommandée

### Phase 1: Top 10 Villes (Google + OSM)
```bash
python3 scripts/import_hybride.py \
  --cities paris marseille lyon toulouse nice bordeaux nantes strasbourg montpellier lille
```

### Phase 2: Régions Touristiques (OSM uniquement)
```bash
# Côte d'Azur
for dept in 06 83 84; do
  python3 scripts/import_osm_france.py --department $dept --category all
  sleep 60
done

# Alpes
for dept in 73 74; do
  python3 scripts/import_osm_france.py --department $dept --category nature
  sleep 60
done

# Bretagne
for dept in 22 29 35 56; do
  python3 scripts/import_osm_france.py --department $dept --category nature
  sleep 60
done
```

### Phase 3: Couverture Nationale (96 départements)
```bash
# Script automatisé
for dept in {01..95} 971 972 973 974 976 2A 2B; do
  python3 scripts/import_osm_france.py --department $dept --category all
  sleep 60
done
```

## 📊 Estimations

| Région | Départements | POIs Estimés | Temps |
|--------|--------------|--------------|-------|
| Métropoles (10) | - | ~5 000 | 3h |
| Île-de-France | 8 | ~3 000 | 1h |
| PACA | 6 | ~2 000 | 45min |
| Occitanie | 13 | ~2 500 | 1h30 |
| Nouvelle-Aquitaine | 12 | ~2 000 | 1h30 |
| **TOUTE LA FRANCE** | **96** | **~20 000** | **~10h** |

**Note:** Temps incluent rate limiting OSM (60s entre requêtes)
