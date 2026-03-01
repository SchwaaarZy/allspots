# 🔄 Reprise Import des Spots - Mode d'emploi

## 📊 État Actuel (27 février 2026)

### ✅ Chunks Terminés
- **Chunk #1** (0-14 999) : ✅ 15 000 spots importés
- **Chunk #2** (15 000-29 999) : ✅ 15 000 spots importés

### ⏸️ Chunk en Cours
- **Chunk #3** (30 000-44 999) : **50/15 000** spots importés
  - Fichier checkpoint : `scripts/out/chunks_20260225_172834/import_progress/pois_france_chunk_003_30000_44999.offset`
  - La prochaine reprise redémarrera automatiquement à l'offset 50

### ⏳ Chunks Restants
- **Chunk #4** (45 000-59 999) : en attente
- **Chunk #5** (60 000-74 999) : en attente
- **Chunk #6** (75 000-89 999) : en attente

**Total importé :** 30 050 / ~90 000 spots (33%)  
**Restant :** ~59 950 spots

---

## 🚀 Commande de Reprise

La reprise se fait avec checkpoint automatique : le script reprendra exactement où il s'est arrêté (offset 50 du chunk #3).

```bash
# Depuis le répertoire allspots
cd /Users/matthieufabre/Documents/Applications/N2/allspots

# Activer l'environnement Python
source .venv/bin/activate

# Lancer la reprise (lente mais stable)
FIRESTORE_BATCH_SIZE=50 FIRESTORE_BATCH_SLEEP=2.0 bash scripts/import_firestore_chunks.sh \
  --chunks-dir scripts/out/chunks_20260225_172834 \
  --start-index 3 \
  --project-id allspots-5872e
```

### Paramètres expliqués
- `FIRESTORE_BATCH_SIZE=50` : Écrit 50 spots par batch (au lieu de 500) pour limiter la pression quota
- `FIRESTORE_BATCH_SLEEP=2.0` : Pause de 2 secondes entre chaque batch
- `--start-index 3` : Reprend au chunk #3 (automatiquement à l'offset 50 sauvegardé)

---

## 🕐 Meilleurs Moments pour Reprendre

Pour éviter les dépassements de quota Firestore 429, privilégiez :

1. **Nuit UTC** (entre 2h-8h heure de Paris) : quota généralement plus disponible
2. **Tôt le matin** (7h-9h) : avant le pic d'activité
3. **Week-end** : moins de charge globale sur Firebase

Si vous tombez encore sur des `429` malgré ces horaires, attendez 30-60 minutes et relancez la **même commande** (le checkpoint reprendra au bon endroit).

---

## 📈 Suivi de la Progression

### Voir les logs en temps réel
```bash
# Depuis un autre terminal
tail -f scripts/out/import_firestore_chunks_$(date +%Y%m%d)_*.log
```

### Voir la progression du chunk en cours
```bash
# Offset actuel
cat scripts/out/chunks_20260225_172834/import_progress/pois_france_chunk_003_30000_44999.offset

# Dernières lignes du log
LOG=$(ls -t scripts/out/import_firestore_chunks_*.log | head -n 1)
tail -n 50 "$LOG" | grep "Batch ok"
```

---

## ⚡ Si le Problème Persiste

Si après plusieurs tentatives le quota `429` bloque toujours, vous avez deux options :

### Option A : Import bulk Firebase CLI (rapide)
```bash
# Fusionner les chunks 3-6 restants
python3 -c "
import json
from pathlib import Path
chunks_dir = Path('scripts/out/chunks_20260225_172834')
files = sorted(chunks_dir.glob('pois_france_chunk_00[3-6]_*.json'))
all_data = []
for f in files:
    data = json.loads(f.read_text())
    all_data.extend(data)
Path('pois_remaining.json').write_text(json.dumps(all_data, ensure_ascii=False))
print(f'Fusionné: {len(all_data)} spots')
"

# Importer via Firebase CLI (bypass quota batch-write)
firebase firestore:import pois_remaining.json --project allspots-5872e
```

### Option B : Patcher Firestore pour augmenter les quotas
Aller sur la console Firebase → Firestore Database → Quotas et payer pour augmenter les limites d'écriture.

---

## 🎯 Une Fois l'Import Terminé

1. **Vérifier dans Firestore Console**
   - Aller sur https://console.firebase.google.com/project/allspots-5872e/firestore
   - Collection `spots` doit contenir ~90 000 documents

2. **Tester dans l'app Flutter**
   ```bash
   flutter run
   ```
   - Ouvrir la carte
   - Zoomer sur différentes régions de France
   - Vérifier que les spots apparaissent avec images et détails

3. **Nettoyer les fichiers temporaires**
   ```bash
   rm -rf scripts/out/chunks_20260225_172834/import_progress
   ```

---

## 📝 Notes Techniques

- **Retry automatique** : Le script retente jusqu'à 8 fois avec backoff exponentiel (2s, 4s, 8s, 16s, 32s, 64s, 90s, 90s)
- **Checkpoint intra-chunk** : Chaque batch validé sauvegarde l'offset pour reprise exacte
- **Mode idempotent** : Relancer plusieurs fois la même commande est sans risque (merge=True sur Firestore)

---

**Dernière mise à jour :** 27 février 2026, 19h30
**Prochaine action :** Relancer la commande ci-dessus demain matin ou en période creuse
