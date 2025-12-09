/**
 * License Key Generator for SMS Grouper
 *
 * This script generates license keys and adds them to Firebase Firestore.
 *
 * Prerequisites:
 * 1. Install Node.js
 * 2. Run: npm install firebase-admin
 * 3. Download your Firebase service account key from:
 *    Firebase Console > Project Settings > Service Accounts > Generate New Private Key
 * 4. Save the key as 'serviceAccountKey.json' in this folder
 *
 * Usage:
 *   node license_generator.js generate <plan> [expiresInDays]
 *   node license_generator.js list
 *   node license_generator.js revoke <licenseKey>
 *   node license_generator.js info <licenseKey>
 *
 * Examples:
 *   node license_generator.js generate starter
 *   node license_generator.js generate pro 365
 *   node license_generator.js generate unlimited
 *   node license_generator.js list
 *   node license_generator.js revoke ABCD-1234-EFGH-5678
 */

const admin = require('firebase-admin');
const crypto = require('crypto');
const path = require('path');

// Initialize Firebase Admin
const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');

try {
  const serviceAccount = require(serviceAccountPath);
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
} catch (error) {
  console.error('Error: Could not load serviceAccountKey.json');
  console.error('Please download your Firebase service account key and save it as serviceAccountKey.json');
  console.error('Firebase Console > Project Settings > Service Accounts > Generate New Private Key');
  process.exit(1);
}

const db = admin.firestore();

// License plans with their limits
const PLANS = {
  trial: {
    name: 'Essai',
    maxSmsPerDay: 50,
    maxUsers: 1,
    maxCampaigns: 3,
    defaultExpiryDays: 7
  },
  starter: {
    name: 'Starter',
    maxSmsPerDay: 200,
    maxUsers: 3,
    maxCampaigns: 20,
    defaultExpiryDays: null // lifetime
  },
  pro: {
    name: 'Pro',
    maxSmsPerDay: 1500,
    maxUsers: 10,
    maxCampaigns: 100,
    defaultExpiryDays: null // lifetime
  },
  unlimited: {
    name: 'Unlimited',
    maxSmsPerDay: 999999,
    maxUsers: 999999,
    maxCampaigns: 999999,
    defaultExpiryDays: null // lifetime
  }
};

/**
 * Generate a random license key in format XXXX-XXXX-XXXX-XXXX
 */
function generateLicenseKey() {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let key = '';

  for (let i = 0; i < 16; i++) {
    if (i > 0 && i % 4 === 0) {
      key += '-';
    }
    key += chars.charAt(crypto.randomInt(0, chars.length));
  }

  return key;
}

/**
 * Create a new license in Firestore
 */
async function createLicense(plan, expiresInDays = null) {
  if (!PLANS[plan]) {
    console.error(`Invalid plan: ${plan}`);
    console.error(`Available plans: ${Object.keys(PLANS).join(', ')}`);
    process.exit(1);
  }

  const planConfig = PLANS[plan];
  const licenseKey = generateLicenseKey();
  const now = new Date();

  // Calculate expiry date
  let expiresAt = null;
  if (expiresInDays !== null) {
    expiresAt = new Date(now.getTime() + expiresInDays * 24 * 60 * 60 * 1000);
  } else if (planConfig.defaultExpiryDays) {
    expiresAt = new Date(now.getTime() + planConfig.defaultExpiryDays * 24 * 60 * 60 * 1000);
  }

  const licenseData = {
    plan: plan,
    createdAt: now.toISOString(),
    expiresAt: expiresAt ? expiresAt.toISOString() : null,
    deviceId: null,
    activatedAt: null,
    lastVerified: null,
    revoked: false,
    maxSmsPerDay: planConfig.maxSmsPerDay,
    maxUsers: planConfig.maxUsers,
    maxCampaigns: planConfig.maxCampaigns
  };

  try {
    await db.collection('licenses').doc(licenseKey).set(licenseData);

    console.log('\n========================================');
    console.log('       LICENSE CREATED SUCCESSFULLY     ');
    console.log('========================================\n');
    console.log(`  License Key: ${licenseKey}`);
    console.log(`  Plan: ${planConfig.name} (${plan})`);
    console.log(`  Expires: ${expiresAt ? expiresAt.toLocaleDateString() : 'Never (Lifetime)'}`);
    console.log(`  Max SMS/Day: ${planConfig.maxSmsPerDay}`);
    console.log(`  Max Users: ${planConfig.maxUsers}`);
    console.log(`  Max Campaigns: ${planConfig.maxCampaigns}`);
    console.log('\n========================================\n');

    return licenseKey;
  } catch (error) {
    console.error('Error creating license:', error);
    process.exit(1);
  }
}

/**
 * List all licenses
 */
async function listLicenses() {
  try {
    const snapshot = await db.collection('licenses').get();

    if (snapshot.empty) {
      console.log('No licenses found.');
      return;
    }

    console.log('\n========================================');
    console.log('           LICENSE LIST                 ');
    console.log('========================================\n');

    const licenses = [];
    snapshot.forEach(doc => {
      licenses.push({ key: doc.id, ...doc.data() });
    });

    // Sort by creation date
    licenses.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    for (const license of licenses) {
      const status = license.revoked ? 'REVOKED' :
                     (license.deviceId ? 'ACTIVATED' : 'AVAILABLE');
      const statusColor = license.revoked ? '\x1b[31m' :
                          (license.deviceId ? '\x1b[32m' : '\x1b[33m');

      console.log(`${license.key}`);
      console.log(`  Plan: ${license.plan}`);
      console.log(`  Status: ${statusColor}${status}\x1b[0m`);
      if (license.deviceId) {
        console.log(`  Device: ${license.deviceId.substring(0, 20)}...`);
      }
      console.log(`  Expires: ${license.expiresAt ? new Date(license.expiresAt).toLocaleDateString() : 'Lifetime'}`);
      console.log('');
    }

    console.log(`Total: ${licenses.length} license(s)`);
    console.log('========================================\n');

  } catch (error) {
    console.error('Error listing licenses:', error);
    process.exit(1);
  }
}

/**
 * Revoke a license
 */
async function revokeLicense(licenseKey) {
  try {
    const docRef = db.collection('licenses').doc(licenseKey);
    const doc = await docRef.get();

    if (!doc.exists) {
      console.error(`License not found: ${licenseKey}`);
      process.exit(1);
    }

    await docRef.update({
      revoked: true,
      revokedAt: new Date().toISOString()
    });

    console.log(`\nLicense ${licenseKey} has been revoked.\n`);

  } catch (error) {
    console.error('Error revoking license:', error);
    process.exit(1);
  }
}

/**
 * Get license info
 */
async function getLicenseInfo(licenseKey) {
  try {
    const doc = await db.collection('licenses').doc(licenseKey).get();

    if (!doc.exists) {
      console.error(`License not found: ${licenseKey}`);
      process.exit(1);
    }

    const data = doc.data();

    console.log('\n========================================');
    console.log('         LICENSE INFORMATION            ');
    console.log('========================================\n');
    console.log(`  License Key: ${licenseKey}`);
    console.log(`  Plan: ${data.plan}`);
    console.log(`  Created: ${new Date(data.createdAt).toLocaleString()}`);
    console.log(`  Expires: ${data.expiresAt ? new Date(data.expiresAt).toLocaleString() : 'Never (Lifetime)'}`);
    console.log(`  Status: ${data.revoked ? 'REVOKED' : (data.deviceId ? 'ACTIVATED' : 'AVAILABLE')}`);

    if (data.deviceId) {
      console.log(`  Device ID: ${data.deviceId}`);
      console.log(`  Activated At: ${new Date(data.activatedAt).toLocaleString()}`);
      console.log(`  Last Verified: ${data.lastVerified ? new Date(data.lastVerified).toLocaleString() : 'Never'}`);
    }

    console.log(`\n  Limits:`);
    console.log(`    Max SMS/Day: ${data.maxSmsPerDay}`);
    console.log(`    Max Users: ${data.maxUsers}`);
    console.log(`    Max Campaigns: ${data.maxCampaigns}`);
    console.log('\n========================================\n');

  } catch (error) {
    console.error('Error getting license info:', error);
    process.exit(1);
  }
}

/**
 * Main
 */
async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.log(`
SMS Grouper License Generator

Usage:
  node license_generator.js generate <plan> [expiresInDays]
  node license_generator.js list
  node license_generator.js revoke <licenseKey>
  node license_generator.js info <licenseKey>

Plans: ${Object.keys(PLANS).join(', ')}

Examples:
  node license_generator.js generate starter
  node license_generator.js generate pro 365
  node license_generator.js generate unlimited
  node license_generator.js list
  node license_generator.js revoke ABCD-1234-EFGH-5678
    `);
    process.exit(0);
  }

  const command = args[0];

  switch (command) {
    case 'generate':
      if (args.length < 2) {
        console.error('Please specify a plan: trial, starter, pro, unlimited');
        process.exit(1);
      }
      const plan = args[1].toLowerCase();
      const expiresInDays = args[2] ? parseInt(args[2]) : null;
      await createLicense(plan, expiresInDays);
      break;

    case 'list':
      await listLicenses();
      break;

    case 'revoke':
      if (args.length < 2) {
        console.error('Please specify a license key');
        process.exit(1);
      }
      await revokeLicense(args[1].toUpperCase());
      break;

    case 'info':
      if (args.length < 2) {
        console.error('Please specify a license key');
        process.exit(1);
      }
      await getLicenseInfo(args[1].toUpperCase());
      break;

    default:
      console.error(`Unknown command: ${command}`);
      process.exit(1);
  }

  process.exit(0);
}

main();
