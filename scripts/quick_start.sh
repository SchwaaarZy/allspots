#!/bin/bash
# 🚀 Script de démarrage rapide pour import de POIs
# Usage: ./quick_start.sh [ville]

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🗺️  AllSpots - Import Rapide de POIs${NC}"
echo "========================================"
echo ""

# Vérifier Python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}❌ Python3 non trouvé. Installez-le avec: brew install python3${NC}"
    exit 1
fi

# Vérifier les dépendances Python
echo -e "${BLUE}📦 Vérification des dépendances...${NC}"
pip3 install -q requests 2>/dev/null || true

# Ville cible (par défaut: Paris)
CITY=${1:-paris}

case $CITY in
    paris)
        DEPT="75"
        LOCATION="48.8566,2.3522"
        RADIUS="25000"
        ;;
    marseille)
        DEPT="13"
        LOCATION="43.2965,5.3698"
        RADIUS="20000"
        ;;
    lyon)
        DEPT="69"
        LOCATION="45.7640,4.8357"
        RADIUS="20000"
        ;;
    toulouse)
        DEPT="31"
        LOCATION="43.6047,1.4442"
        RADIUS="18000"
        ;;
    nice)
        DEPT="06"
        LOCATION="43.7102,7.2620"
        RADIUS="15000"
        ;;
    bordeaux)
        DEPT="33"
        LOCATION="44.8378,-0.5792"
        RADIUS="18000"
        ;;
    *)
        echo -e "${RED}❌ Ville non supportée: $CITY${NC}"
        echo -e "${YELLOW}Villes disponibles: paris, marseille, lyon, toulouse, nice, bordeaux${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}✅ Ville sélectionnée: ${CITY^}${NC}"
echo -e "   📍 Département: $DEPT"
echo -e "   📏 Rayon: $RADIUS m"
echo ""

# Import OSM (base gratuite)
echo -e "${BLUE}🗺️  Import OpenStreetMap...${NC}"
echo "   Catégorie: culture"
python3 scripts/import_osm_france.py \
    --department $DEPT \
    --category culture \
    --radius $RADIUS \
    --output "pois_${CITY}_test.json"

# Vérifier le résultat
if [ -f "pois_${CITY}_test.json" ]; then
    COUNT=$(python3 -c "import json; print(len(json.load(open('pois_${CITY}_test.json'))))")
    echo ""
    echo -e "${GREEN}✅ Import réussi: $COUNT POIs${NC}"
    echo -e "📄 Fichier: pois_${CITY}_test.json"
    echo ""
    
    # Afficher un échantillon
    echo -e "${BLUE}📋 Échantillon (5 premiers POIs):${NC}"
    python3 -c "
import json
data = json.load(open('pois_${CITY}_test.json'))
for i, poi in enumerate(data[:5]):
    print(f\"   {i+1}. {poi['name']} - {poi['city']}\")
"
    echo ""
    
    # Instructions suivantes
    echo -e "${YELLOW}📚 Prochaines étapes:${NC}"
    echo ""
    echo -e "   ${GREEN}1. Import complet (toutes catégories):${NC}"
    echo -e "      python3 scripts/import_hybride.py --cities $CITY"
    echo ""
    echo -e "   ${GREEN}2. Import dans Firestore:${NC}"
    echo -e "      firebase firestore:import pois_${CITY}_test.json --project allspots"
    echo ""
    echo -e "   ${GREEN}3. Vérifier dans l'app:${NC}"
    echo -e "      flutter run"
    echo ""
    
else
    echo -e "${RED}❌ Erreur: Fichier non généré${NC}"
    exit 1
fi
