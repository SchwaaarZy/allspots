#!/bin/bash
# Script d'import des POIs dans Firestore
# Prérequis: gcloud CLI installé et authentifié

PROJECT_ID="allspots-5872e"
JSON_FILE="scripts/out/pois_all_categories_20260223_093423.json"

echo "📥 Préparation de l'import..."
echo "Project: $PROJECT_ID"
echo "Fichier: $JSON_FILE"
echo ""

# Vérifier que gcloud est installé
if ! command -v gcloud &> /dev/null; then
    echo "❌ gcloud CLI n'est pas installé."
    echo "Installez-le avec: brew install google-cloud-sdk"
    echo "Ou visitez: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Vérifier que le fichier existe
if [ ! -f "$JSON_FILE" ]; then
    echo "❌ Fichier non trouvé: $JSON_FILE"
    exit 1
fi

# Compter les POIs
POI_COUNT=$(python3 -c "import json; print(len(json.load(open('$JSON_FILE'))))")
echo "📊 Nombre de POIs: $POI_COUNT"
echo ""

# Importer dans Firestore
echo "⏳ Import en cours..."
gcloud firestore import "$JSON_FILE" \
  --project="$PROJECT_ID" \
  --async

echo ""
echo "✅ Import lancé!"
echo "Vous pouvez vérifier la progression dans la Console Firebase:"
echo "https://console.firebase.google.com/project/$PROJECT_ID/firestore/backups"
