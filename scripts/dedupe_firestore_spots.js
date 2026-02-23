#!/usr/bin/env node
/**
 * Déduplication des spots déjà présents dans Firestore.
 *
 * Par défaut: DRY RUN (aucune suppression).
 * Pour appliquer: --apply
 *
 * Usage:
 *   node scripts/dedupe_firestore_spots.js
 *   node scripts/dedupe_firestore_spots.js --apply
 *   node scripts/dedupe_firestore_spots.js --apply --backup scripts/out/duplicates_backup.json
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const DOC_PAGE_SIZE = 500;
const WRITE_BATCH_SIZE = 450;

function normalizeText(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

function toNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  return null;
}

function extractCoords(data) {
  const lat = toNumber(data.lat);
  const lng = toNumber(data.lng);
  if (lat !== null && lng !== null) {
    return { lat, lng };
  }

  const location = data.location;
  if (location && typeof location.latitude === 'number' && typeof location.longitude === 'number') {
    return { lat: location.latitude, lng: location.longitude };
  }

  if (location && typeof location._latitude === 'number' && typeof location._longitude === 'number') {
    return { lat: location._latitude, lng: location._longitude };
  }

  return null;
}

function readDateMillis(value) {
  if (!value) return 0;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  }
  return 0;
}

function buildDedupeKey(docId, data) {
  if (data.dedupeKey && typeof data.dedupeKey === 'string' && data.dedupeKey.trim()) {
    return data.dedupeKey.trim();
  }

  if (data.source === 'openstreetmap' && data.osmId) {
    return `osm:${String(data.osmId)}`;
  }

  if (data.place_id) {
    return `gplaces:${normalizeText(data.place_id)}`;
  }

  const coords = extractCoords(data);
  if (!coords) {
    return `doc:${docId}`;
  }

  const source = normalizeText(data.source || 'unknown');
  const name = normalizeText(data.name || 'spot');
  const category = normalizeText(data.category || data.categoryGroup || 'other');
  return `${source}:${category}:${name}:${coords.lat.toFixed(6)}:${coords.lng.toFixed(6)}`;
}

function qualityScore(data) {
  let score = 0;

  const description = String(data.description || '').trim();
  if (description.length >= 40) score += 3;
  else if (description.length >= 15) score += 2;
  else if (description.length > 0) score += 1;

  const imageUrls = Array.isArray(data.imageUrls) ? data.imageUrls : [];
  const images = Array.isArray(data.images) ? data.images : [];
  const imageCount = Math.max(imageUrls.length, images.length);
  if (imageCount >= 3) score += 3;
  else if (imageCount >= 1) score += 2;

  if (String(data.websiteUrl || data.website || '').trim()) score += 1;
  if (String(data.categoryGroup || data.category || '').trim()) score += 1;
  if (data.isValidated === true) score += 1;

  return score;
}

function pickKeeper(records) {
  const sorted = [...records].sort((a, b) => {
    const scoreDiff = qualityScore(b.data) - qualityScore(a.data);
    if (scoreDiff !== 0) return scoreDiff;

    const updatedDiff = readDateMillis(b.data.updatedAt) - readDateMillis(a.data.updatedAt);
    if (updatedDiff !== 0) return updatedDiff;

    return a.id.localeCompare(b.id);
  });

  return sorted[0];
}

async function fetchAllSpots() {
  const all = [];
  let lastDoc = null;

  while (true) {
    let query = db
      .collection('spots')
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(DOC_PAGE_SIZE);

    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snap = await query.get();
    if (snap.empty) break;

    for (const doc of snap.docs) {
      all.push({ id: doc.id, data: doc.data(), ref: doc.ref });
    }

    lastDoc = snap.docs[snap.docs.length - 1];
    if (snap.docs.length < DOC_PAGE_SIZE) break;
  }

  return all;
}

function buildDuplicatePlan(records) {
  const byKey = new Map();

  for (const record of records) {
    const key = buildDedupeKey(record.id, record.data);
    if (!byKey.has(key)) byKey.set(key, []);
    byKey.get(key).push(record);
  }

  const groups = [];
  for (const [key, items] of byKey.entries()) {
    if (items.length <= 1) continue;
    const keeper = pickKeeper(items);
    const toDelete = items.filter((item) => item.id !== keeper.id);
    groups.push({ key, keeper, toDelete, all: items });
  }

  return groups;
}

async function applyPlan(groups, backupPath) {
  const toDelete = groups.flatMap((g) => g.toDelete);

  if (backupPath) {
    const backupDir = path.dirname(backupPath);
    fs.mkdirSync(backupDir, { recursive: true });
    const payload = groups.map((g) => ({
      dedupeKey: g.key,
      keeperId: g.keeper.id,
      duplicates: g.toDelete.map((d) => ({ id: d.id, data: d.data })),
    }));
    fs.writeFileSync(backupPath, JSON.stringify(payload, null, 2), 'utf8');
    console.log(`💾 Backup doublons: ${backupPath}`);
  }

  let deleted = 0;
  let updatedKeepers = 0;

  for (let index = 0; index < groups.length; index += WRITE_BATCH_SIZE) {
    const batch = db.batch();
    const sliceGroups = groups.slice(index, index + WRITE_BATCH_SIZE);

    for (const group of sliceGroups) {
      batch.set(group.keeper.ref, {
        dedupeKey: group.key,
        dedupedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      updatedKeepers += 1;
    }

    await batch.commit();
  }

  for (let index = 0; index < toDelete.length; index += WRITE_BATCH_SIZE) {
    const batch = db.batch();
    const slice = toDelete.slice(index, index + WRITE_BATCH_SIZE);

    for (const doc of slice) {
      batch.delete(doc.ref);
    }

    await batch.commit();
    deleted += slice.length;
    console.log(`🧹 Suppressions: ${deleted}/${toDelete.length}`);
  }

  return { deleted, updatedKeepers };
}

function parseArgs(argv) {
  const args = {
    apply: false,
    backup: '',
  };

  for (let i = 2; i < argv.length; i += 1) {
    const token = argv[i];
    if (token === '--apply') {
      args.apply = true;
    } else if (token === '--backup') {
      args.backup = argv[i + 1] || '';
      i += 1;
    }
  }

  return args;
}

async function main() {
  const args = parseArgs(process.argv);

  console.log('🔎 Scan Firestore spots...');
  const records = await fetchAllSpots();
  console.log(`📦 Documents lus: ${records.length}`);

  const groups = buildDuplicatePlan(records);
  const duplicateDocs = groups.reduce((acc, g) => acc + g.toDelete.length, 0);

  console.log(`🧭 Groupes doublons: ${groups.length}`);
  console.log(`🗑️ Documents en doublon: ${duplicateDocs}`);

  if (groups.length > 0) {
    console.log('Exemples (5 max):');
    for (const group of groups.slice(0, 5)) {
      const ids = group.all.map((r) => r.id).join(', ');
      console.log(`  - key=${group.key}`);
      console.log(`    keeper=${group.keeper.id}`);
      console.log(`    docs=[${ids}]`);
    }
  }

  if (!args.apply) {
    console.log('\nℹ️ Mode dry-run: aucune suppression.');
    console.log('   Pour appliquer: node scripts/dedupe_firestore_spots.js --apply');
    return;
  }

  if (duplicateDocs === 0) {
    console.log('✅ Aucun doublon à supprimer.');
    return;
  }

  const { deleted, updatedKeepers } = await applyPlan(groups, args.backup || '');
  console.log(`\n✅ Terminé: keepers mis à jour=${updatedKeepers}, doublons supprimés=${deleted}`);
}

main().catch((error) => {
  console.error('❌ Erreur:', error);
  process.exit(1);
});
