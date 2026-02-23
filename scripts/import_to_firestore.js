#!/usr/bin/env node
/**
 * Script Node.js pour importer des POIs dans Firestore
 * Alternative à Firebase CLI pour import programmatique
 */

const admin = require('firebase-admin');
const fs = require('fs');

function normalizeText(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function extractCoordinates(poi) {
  if (typeof poi.lat === 'number' && typeof poi.lng === 'number') {
    return { lat: poi.lat, lng: poi.lng };
  }

  if (poi.location && typeof poi.location._latitude === 'number' && typeof poi.location._longitude === 'number') {
    return { lat: poi.location._latitude, lng: poi.location._longitude };
  }

  return null;
}

function buildDeterministicId(poi, lat, lng) {
  const roundedLat = Number(lat).toFixed(6);
  const roundedLng = Number(lng).toFixed(6);

  if (poi.source === 'openstreetmap' && poi.osmId) {
    return `osm_${String(poi.osmId)}`;
  }

  if (poi.place_id) {
    return `gplaces_${normalizeText(poi.place_id)}`;
  }

  const source = normalizeText(poi.source || 'unknown');
  const category = normalizeText(poi.category || poi.categoryGroup || 'other');
  const name = normalizeText(poi.name || 'spot');
  return `${source}_${category}_${name}_${roundedLat}_${roundedLng}`.substring(0, 140);
}

// Initialiser Firebase Admin (utilise les credentials par défaut)
admin.initializeApp();
const db = admin.firestore();

async function importPois(jsonFilePath) {
  console.log(`📥 Lecture du fichier: ${jsonFilePath}`);
  
  const data = fs.readFileSync(jsonFilePath, 'utf8');
  const pois = JSON.parse(data);
  
  console.log(`📊 ${pois.length} POIs à importer\n`);
  
  let batch = db.batch();
  let batchCount = 0;
  let totalImported = 0;
  let totalSkipped = 0;
  const seenIds = new Set();
  
  for (let i = 0; i < pois.length; i++) {
    const poi = pois[i];
    
    const coords = extractCoordinates(poi);
    if (!coords) {
      totalSkipped++;
      continue;
    }

    const { lat, lng } = coords;
    const docId = buildDeterministicId(poi, lat, lng);
    if (seenIds.has(docId)) {
      totalSkipped++;
      continue;
    }
    seenIds.add(docId);
    
    const docRef = db.collection('spots').doc(docId);
    
    // Convertir les timestamps
    if (poi.createdAt && poi.createdAt._seconds) {
      poi.createdAt = admin.firestore.Timestamp.fromMillis(poi.createdAt._seconds * 1000);
    } else {
      poi.createdAt = admin.firestore.Timestamp.now();
    }

    if (poi.updatedAt && poi.updatedAt._seconds) {
      poi.updatedAt = admin.firestore.Timestamp.fromMillis(poi.updatedAt._seconds * 1000);
    } else if (typeof poi.updatedAt === 'string') {
      const parsed = Date.parse(poi.updatedAt);
      poi.updatedAt = Number.isNaN(parsed)
        ? admin.firestore.Timestamp.now()
        : admin.firestore.Timestamp.fromMillis(parsed);
    } else {
      poi.updatedAt = admin.firestore.Timestamp.now();
    }
    
    // Convertir la GeoPoint
    poi.location = new admin.firestore.GeoPoint(lat, lng);
    poi.lat = lat;
    poi.lng = lng;
    
    batch.set(
      docRef,
      {
        ...poi,
        dedupeKey: docId,
        importedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    batchCount++;
    
    // Firestore limite: 500 opérations par batch
    if (batchCount === 500 || i === pois.length - 1) {
      console.log(`💾 Envoi du batch ${Math.floor(i / 500) + 1}...`);
      await batch.commit();
      totalImported += batchCount;
      console.log(`   ✅ ${totalImported}/${pois.length} POIs importés`);
      batchCount = 0;
      batch = db.batch();
    }
  }
  
  console.log(`\n✅ Import terminé: ${totalImported} POIs ajoutés à Firestore`);
  if (totalSkipped > 0) {
    console.log(`⚠️ ${totalSkipped} entrée(s) ignorée(s) (doublons/coordonnées invalides)`);
  }
}

// Vérifier les arguments
if (process.argv.length < 3) {
  console.error('Usage: node import_to_firestore.js <fichier.json>');
  process.exit(1);
}

const jsonFile = process.argv[2];

if (!fs.existsSync(jsonFile)) {
  console.error(`❌ Fichier introuvable: ${jsonFile}`);
  process.exit(1);
}

// Lancer l'import
importPois(jsonFile)
  .then(() => {
    console.log('\n🎉 Succès !');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n❌ Erreur:', error);
    process.exit(1);
  });
