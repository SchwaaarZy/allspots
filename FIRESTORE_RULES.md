# Règles Firestore

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
