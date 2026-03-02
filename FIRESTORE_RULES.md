# Règles Firestore

## Nouveau: vérification SMS + suppression automatique à 24h

Le repo contient maintenant:

- `firestore.rules`: bloque les écritures quand un compte non vérifié dépasse le délai.
- `functions/index.js`: fonction planifiée `deleteUnverifiedAccountsAfter24h` (toutes les 30 min) qui supprime:
  - compte Firebase Auth,
  - profil,
  - spots créés,
  - favoris,
  - road trips,
  - notes (`poi_ratings`),
  - signalements (`spot_reports`),
  - document `users/{uid}`,
  - y compris si le compte est premium.

Exception: les comptes admin (`isAdmin=true` ou `role=admin`) sont exclus de la vérification SMS obligatoire et ne sont pas supprimés par cette tâche.

### Déploiement

Depuis la racine:

```bash
cd functions
npm install
cd ..
firebase deploy --only firestore:rules,functions
```

## Erreur: permission-denied

L'erreur "The caller does not have permission to execute the specified operation" signifie que les règles Firestore n'autorisent pas l'accès.

### Solution rapide pour TEST UNIQUEMENT

**ATTENTION: Ne pas utiliser en production!**

Allez dans la [Console Firebase](https://console.firebase.google.com/) → Firestore → Règles et remplacez par:

```firestore
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    // Test mode - allow all reads/writes for authenticated users
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

Puis cliquez sur "Publier".

### Règles de production recommandées

```firestore
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    // Profils - read/write own profile only
    match /profiles/{userId} {
      allow read: if request.auth.uid == userId;
      allow write: if request.auth.uid == userId;
    }

    // Spots publics - read all, write own
    match /spots/{spotId} {
      allow read: if resource.data.isPublic == true;
      allow create: if request.auth != null;
      allow update, delete: if request.auth.uid == resource.data.createdBy;
    }
  }
}
```

Puis cliquez sur "Publier".
