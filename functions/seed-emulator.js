/**
 * Seed the Firestore emulator with a minimal but realistic catalog so the app
 * (and integration tests / manual QA) has something to render and buy.
 *
 *   firebase emulators:exec --only firestore,auth,functions \
 *     "node functions/seed-emulator.js"
 *
 * Or, against an already-running emulator:
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 GCLOUD_PROJECT=arthemis-f2966 \
 *     node functions/seed-emulator.js
 */
const admin = require("firebase-admin");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error("Refusing to run: FIRESTORE_EMULATOR_HOST is not set (this only seeds the emulator).");
  process.exit(1);
}

admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "arthemis-f2966" });
const db = admin.firestore();
const { Timestamp } = admin.firestore;

async function seed() {
  const batch = db.batch();

  // Products
  batch.set(db.doc("products/prod_agua"), {
    name: "Agua Natural 1L",
    price: 15,
    cost: 8,
    stock: 50,
    distribuitor_name: "Bebidas SA",
    hide_online: false,
  });
  batch.set(db.doc("products/prod_pan"), {
    name: "Pan Integral",
    price: 35,
    cost: 20,
    stock: 30,
    distribuitor_name: "Panadería Local",
    hide_online: false,
  });

  // Store pricing (delivery fee by colonia) + a master coupon.
  batch.set(db.doc("settings/store"), { pricing: { Centro: 15, "San Pablo": 25 } });
  batch.set(db.doc("coupons/WELCOME10"), {
    code: "WELCOME10",
    percentage: 10,
    max_discount: 50,
    remaining_uses: 100,
    expiry_date: Timestamp.fromDate(new Date(Date.now() + 30 * 86400000)),
  });

  // Storefront content
  batch.set(db.doc("home_sections/hs1"), {
    type: "product_grid",
    title: "Destacados",
    order: 0,
    active: true,
  });
  batch.set(db.doc("recipes/rec1"), {
    title: "Pan con Aguacate",
    description: "Receta rápida de desayuno.",
  });

  await batch.commit();
  console.log("Seeded: 2 products, settings/store, coupons/WELCOME10, 1 home_section, 1 recipe.");
}

seed().then(() => process.exit(0)).catch((e) => {
  console.error(e);
  process.exit(1);
});
