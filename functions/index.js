const admin = require('firebase-admin');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {logger} = require('firebase-functions');

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();
const DAY_MS = 24 * 60 * 60 * 1000;

exports.deleteUnverifiedAccountsAfter24h = onSchedule(
  {
    schedule: 'every 30 minutes',
    timeZone: 'Europe/Paris',
    memory: '256MiB',
    timeoutSeconds: 540,
    region: 'europe-west1',
  },
  async () => {
    const now = new Date();
    const fallbackCutoff = new Date(now.getTime() - DAY_MS);

    const [deadlineSnapshot, accountSnapshot] = await Promise.all([
      db
        .collection('profiles')
        .where('isPhoneVerified', '==', false)
        .where('phoneVerificationDeadlineAt', '<=', now)
        .limit(200)
        .get(),
      db
        .collection('profiles')
        .where('isPhoneVerified', '==', false)
        .where('accountCreatedAt', '<=', fallbackCutoff)
        .limit(200)
        .get(),
    ]);

    const uniqueUsers = new Map();
    for (const doc of deadlineSnapshot.docs) {
      uniqueUsers.set(doc.id, doc.data());
    }
    for (const doc of accountSnapshot.docs) {
      uniqueUsers.set(doc.id, doc.data());
    }

    if (uniqueUsers.size === 0) {
      logger.info('No unverified account to purge.');
      return;
    }

    for (const [uid, profileData] of uniqueUsers.entries()) {
      try {
        if (await isAdminAccount(uid, profileData)) {
          continue;
        }

        if (profileData.isPhoneVerified === true) {
          continue;
        }

        await purgeUserData(uid);

        try {
          await auth.deleteUser(uid);
        } catch (authError) {
          if (authError.code !== 'auth/user-not-found') {
            throw authError;
          }
        }

        logger.info('Deleted unverified account and related data', {uid});
      } catch (error) {
        logger.error('Failed to delete unverified account', {uid, error});
      }
    }
  }
);

async function purgeUserData(uid) {
  const spotIds = await deleteSpotsCreatedBy(uid);

  await Promise.all([
    deleteSubcollection(`profiles/${uid}/favoritePois`),
    deleteSubcollection(`profiles/${uid}/roadTrips`),
    deleteCollectionByField('poi_ratings', 'userId', uid),
    deleteCollectionByField('spot_reports', 'reporterId', uid),
    deleteCollectionByField('users', admin.firestore.FieldPath.documentId(), uid),
  ]);

  if (spotIds.length > 0) {
    await Promise.all([
      deleteByInChunks('poi_ratings', 'poiId', spotIds),
      deleteByInChunks('spot_reports', 'spotId', spotIds),
    ]);
  }

  await db.collection('profiles').doc(uid).delete().catch((error) => {
    if (error.code !== 5) {
      throw error;
    }
  });
}

async function deleteSpotsCreatedBy(uid) {
  const snap = await db.collection('spots').where('createdBy', '==', uid).limit(500).get();
  if (snap.empty) return [];

  const spotIds = [];
  const batch = db.batch();
  for (const doc of snap.docs) {
    spotIds.push(doc.id);
    batch.delete(doc.ref);
  }
  await batch.commit();

  if (snap.size === 500) {
    const nextIds = await deleteSpotsCreatedBy(uid);
    return [...spotIds, ...nextIds];
  }

  return spotIds;
}

async function deleteSubcollection(path) {
  while (true) {
    const snap = await db.collection(path).limit(500).get();
    if (snap.empty) return;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

async function isAdminAccount(uid, profileData = {}) {
  const profileRole = typeof profileData.role === 'string'
    ? profileData.role.toLowerCase()
    : null;
  if (profileData.isAdmin === true || profileRole === 'admin') {
    return true;
  }

  const userDoc = await db.collection('users').doc(uid).get();
  if (!userDoc.exists) {
    return false;
  }

  const userData = userDoc.data() || {};
  const userRole = typeof userData.role === 'string'
    ? userData.role.toLowerCase()
    : null;

  return userData.isAdmin === true || userRole === 'admin';
}

async function deleteCollectionByField(collectionName, field, value) {
  while (true) {
    const snap = await db
      .collection(collectionName)
      .where(field, '==', value)
      .limit(500)
      .get();

    if (snap.empty) return;

    const batch = db.batch();
    for (const doc of snap.docs) {
      batch.delete(doc.ref);
    }
    await batch.commit();
  }
}

async function deleteByInChunks(collectionName, field, values) {
  const chunkSize = 10;
  for (let i = 0; i < values.length; i += chunkSize) {
    const chunk = values.slice(i, i + chunkSize);
    while (true) {
      const snap = await db
        .collection(collectionName)
        .where(field, 'in', chunk)
        .limit(500)
        .get();

      if (snap.empty) break;

      const batch = db.batch();
      for (const doc of snap.docs) {
        batch.delete(doc.ref);
      }
      await batch.commit();
    }
  }
}
