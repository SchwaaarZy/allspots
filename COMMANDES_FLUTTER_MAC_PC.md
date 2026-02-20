# Commandes Flutter utiles (macOS & Windows)

## 1) Vérifier l'installation

### macOS (Terminal)

```bash
flutter --version
flutter doctor
flutter doctor -v
```

### Windows (PowerShell ou CMD)

```powershell
flutter --version
flutter doctor
flutter doctor -v
```

---

## 2) Préparer le projet

### macOS (préparation)

```bash
flutter clean
flutter pub get
```

### Windows (préparation)

```powershell
flutter clean
flutter pub get
```

---

## 3) Lancer l'application

### Lister les appareils disponibles

```bash
flutter devices
```

### macOS (exécution)

```bash
flutter run
flutter run -d chrome
flutter run -d macos
flutter run -d ios
```

### Windows (exécution)

```powershell
flutter run
flutter run -d chrome
flutter run -d windows
flutter run -d android
```

### Lancer avec variables d'environnement

```bash
flutter run --dart-define=PLACES_API_KEY=ta_cle_api
```

---

## 4) Build (production)

### Android (macOS / Windows)

```bash
flutter build apk --release
flutter build appbundle --release
```

### iOS (macOS uniquement)

```bash
flutter build ios --release
```

### Web (macOS / Windows)

```bash
flutter build web --release
```

### Desktop

```bash
flutter build macos --release
flutter build windows --release
```

---

## 5) Qualité du code

### Analyse, format, tests

```bash
flutter analyze
dart format .
flutter test
```

### Corriger automatiquement (quand possible)

```bash
dart fix --apply
```

---

## 6) Gestion des dépendances

```bash
flutter pub get
flutter pub add nom_package
flutter pub remove nom_package
flutter pub upgrade
flutter pub outdated
```

---

## 7) Aides debug utiles

```bash
flutter logs
flutter run -v
flutter emulators
flutter emulators --launch <emulator_id>
```

---

## 8) Commandes Git + Flutter (workflow rapide)

```bash
git pull
flutter pub get
flutter analyze
flutter test
flutter run
```

---

## 9) Notes pratiques macOS vs Windows

- iOS build/signature fonctionne uniquement sur macOS (Xcode requis).
- Sous Windows, privilégie PowerShell pour un meilleur confort.
- Si une commande n'est pas reconnue, vérifie que Flutter est bien dans le `PATH`.
- Sur Android, vérifie aussi `adb devices` si aucun téléphone n'apparaît.
