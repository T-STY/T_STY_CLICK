/**
 * One-shot seed for the server-driven home screen: `home_sections` + `ads`.
 *
 * Run from the project root:
 *     node functions/seed_home.js
 *
 * Auth (Application Default Credentials) — use ONE of:
 *     gcloud auth application-default login
 *     export GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json
 *
 * Idempotent: uses fixed doc IDs + merge, so re-running just updates.
 * Replace the ad imageUrl/action values with your real banners afterward.
 */
const admin = require("firebase-admin");

admin.initializeApp({ projectId: "arthemis-f2966" });
const db = admin.firestore();

const homeSections = {
  recipes: {
    type: "recipe_carousel",
    title: "Rincón de Recetas 🌞",
    order: 1,
    enabled: true,
  },
  ads_top: {
    type: "ad_carousel",
    title: "",
    order: 2,
    enabled: true,
    placement: "home_carousel",
  },
  top_sales: {
    type: "product_grid",
    title: "¡Lo más top! 🔥",
    order: 3,
    enabled: true,
    source: {
      mode: "query",
      orderBy: { field: "sales_in_past", dir: "desc" },
      limit: 15,
    },
  },
  daily_deals: {
    type: "product_grid",
    title: "¡Descuentos del Día! ✨",
    order: 4,
    enabled: true,
    source: {
      mode: "query",
      filters: [{ field: "current_day", op: "==", value: true }],
      limit: 15,
    },
  },
  recommended: {
    type: "product_grid",
    title: "Nuestras Recomendaciones ✨",
    order: 5,
    enabled: true,
    source: {
      mode: "query",
      filters: [{ field: "recommended", op: "==", value: true }],
      limit: 15,
    },
  },
};

const ads = {
  ad_demo_none: {
    imageUrl: "https://placehold.co/800x340/orange/white.png?text=Ad+1",
    active: true,
    order: 1,
    placement: "home_carousel",
    action: { type: "none" }, // tapping does nothing
  },
  ad_demo_category: {
    imageUrl: "https://placehold.co/800x340/333/white.png?text=Abarrotes",
    active: true,
    order: 2,
    placement: "home_carousel",
    // tapping opens the filtered product screen for this category
    action: { type: "category", category: "Abarrotes", title: "Abarrotes" },
  },
};

async function run() {
  const batch = db.batch();
  for (const [id, data] of Object.entries(homeSections)) {
    batch.set(db.collection("home_sections").doc(id), data, { merge: true });
  }
  for (const [id, data] of Object.entries(ads)) {
    batch.set(db.collection("ads").doc(id), data, { merge: true });
  }
  await batch.commit();
  console.log(
    `Seeded ${Object.keys(homeSections).length} home_sections and ` +
      `${Object.keys(ads).length} ads into arthemis-f2966.`
  );
  process.exit(0);
}

run().catch((e) => {
  console.error("Seed failed:", e);
  process.exit(1);
});
