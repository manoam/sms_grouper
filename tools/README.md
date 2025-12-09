# SMS Grouper - Outils de gestion des licences

## Configuration initiale

### 1. Installer Node.js
Telechargez et installez Node.js depuis https://nodejs.org/

### 2. Installer les dependances
```bash
cd tools
npm install firebase-admin
```

### 3. Telecharger la cle de service Firebase
1. Allez sur [Firebase Console](https://console.firebase.google.com/)
2. Selectionnez votre projet
3. Allez dans **Project Settings** (icone engrenage)
4. Cliquez sur l'onglet **Service Accounts**
5. Cliquez sur **Generate New Private Key**
6. Sauvegardez le fichier JSON telecharge sous le nom `serviceAccountKey.json` dans ce dossier

## Utilisation du generateur de licences

### Generer une nouvelle licence

```bash
# Licence Starter (a vie)
node license_generator.js generate starter

# Licence Pro (a vie)
node license_generator.js generate pro

# Licence Unlimited (a vie)
node license_generator.js generate unlimited

# Licence Trial (7 jours par defaut)
node license_generator.js generate trial

# Licence avec expiration personnalisee (ex: 365 jours)
node license_generator.js generate pro 365
```

### Lister toutes les licences

```bash
node license_generator.js list
```

### Voir les details d'une licence

```bash
node license_generator.js info XXXX-XXXX-XXXX-XXXX
```

### Revoquer une licence

```bash
node license_generator.js revoke XXXX-XXXX-XXXX-XXXX
```

## Plans disponibles

| Plan | SMS/jour | Utilisateurs | Campagnes | Expiration |
|------|----------|--------------|-----------|------------|
| trial | 50 | 1 | 3 | 7 jours |
| starter | 200 | 3 | 20 | A vie |
| pro | 1500 | 10 | 100 | A vie |
| unlimited | Illimite | Illimite | Illimite | A vie |

## Securite Firestore

Configurez les regles de securite dans Firebase Console > Firestore > Rules :

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Les licences ne peuvent etre lues/modifiees que par les clients authentifies
    // ou par les appareils avec l'ID correspondant
    match /licenses/{licenseKey} {
      // Permettre la lecture pour verification
      allow read: if true;

      // Permettre la mise a jour uniquement pour l'activation et la verification
      allow update: if request.resource.data.diff(resource.data).affectedKeys()
        .hasOnly(['deviceId', 'activatedAt', 'lastVerified', 'deactivatedAt']);

      // Interdire la creation et la suppression depuis l'app
      allow create, delete: if false;
    }
  }
}
```

Ces regles permettent:
- **Lecture**: Tout le monde peut verifier une licence
- **Mise a jour**: Uniquement les champs d'activation peuvent etre modifies
- **Creation/Suppression**: Uniquement via le script admin (avec serviceAccountKey)
