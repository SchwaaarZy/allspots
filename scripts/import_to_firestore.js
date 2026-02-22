#!/usr/bin/env node
/**
 * Script Node.js pour importer des POIs dans Firestore
 * Alternative à Firebase CLI pour import programmatique
 */

const admin = require('firebase-admin');
const fs = require('fs');

// Initialiser Firebase Admin (utilise les credentials par défaut)
admin.initializeApp();
const db = admin.firestore();

async function importPois(jsonFilePath) {
  console.log(`📥 Lecture du fichier: ${jsonFilePath}`);
  
  const data = fs.readFileSync(jsonFilePath, 'utf8');
  const pois = JSON.parse(data);
  
  console.log(`📊 ${pois.length} POIs à importer\n`);
  
  const batch = db.batch();
  let batchCount = 0;
  let totalImported = 0;
  
  for (let i = 0; i < pois.length; i++) {
    const poi = pois[i];
    
    // Générer un ID unique basé sur nom + position
    const lat = poi.location._latitude.toFixed(6);
    const lng = poi.location._longitude.toFixed(6);
    const docId = `${poi.name}_${lat}_${lng}`
      .toLowerCase()
      .replace(/[^a-z0-9]/g, '_')
      .substring(0, 100);
    
    const docRef = db.collection('spots').doc(docId);
    
    // Convertir les timestamps
    if (poi.createdAt && poi.createdAt._seconds) {
      poi.createdAt = admin.firestore.Timestamp.fromMillis(poi.createdAt._seconds * 1000);
    } else {
      poi.createdAt = admin.firestore.Timestamp.now();
    }
    
    // Convertir la GeoPoint
    poi.location = new admin.firestore.GeoPoint(
      poi.location._latitude,
      poi.location._longitude
    );
    
    batch.set(docRef, poi, { merge: true });
    batchCount++;
    
    // Firestore limite: 500 opérations par batch
    if (batchCount === 500 || i === pois.length - 1) {
      console.log(`💾 Envoi du batch ${Math.floor(i / 500) + 1}...`);
      await batch.commit();
      totalImported += batchCount;
      console.log(`   ✅ ${totalImported}/${pois.length} POIs importés`);
      batchCount = 0;
    }
  }
  
  console.log(`\n✅ Import terminé: ${totalImported} POIs ajoutés à Firestore`);
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
