/**
 * Cloud Functions tests — run the REAL exported handlers (via
 * firebase-functions-test) against the live Firestore emulator, so every
 * assertion reflects real transaction behaviour.
 *
 *   cd functions && npm install          # first time (adds mocha + fft)
 *   npm --prefix functions run test:emulator
 *
 * Only the Firestore emulator is required: the handlers are invoked in-process
 * and their admin-SDK reads/writes hit the emulator (FIRESTORE_EMULATOR_HOST is
 * set by `firebase emulators:exec`). Auth is supplied via the wrapped request's
 * { auth: { uid } }, so the Auth emulator is unnecessary.
 */
const assert = require("assert");
const test = require("firebase-functions-test")(); // offline mode
const admin = require("firebase-admin");
const fns = require("../index.js"); // calls admin.initializeApp() → emulator
const db = admin.firestore();
const { Timestamp } = admin.firestore;

const UID = "alice-uid";
const CARD = "T_STY-3331112222";
const future = () => Timestamp.fromDate(new Date(Date.now() + 86400000));
const past = () => Timestamp.fromDate(new Date(Date.now() - 86400000));

async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST || "127.0.0.1:8080";
  const project = process.env.GCLOUD_PROJECT || "arthemis-f2966";
  await fetch(
    `http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,
    { method: "DELETE" }
  );
}

afterEach(clearFirestore);
after(() => test.cleanup());

// ───────────────────────────────────────────────────────────────────────
describe("claimCoupon", () => {
  const claim = () => test.wrap(fns.claimCoupon);

  it("grants a valid coupon and decrements master remaining_uses", async () => {
    await db.collection("coupons").doc("SAVE10").set({
      code: "SAVE10",
      percentage: 10,
      max_discount: 50,
      remaining_uses: 2,
      expiry_date: future(),
    });

    await claim()({ data: { code: "save10" }, auth: { uid: UID } });

    const userCoupon = await db.doc(`users/${UID}/coupons/SAVE10`).get();
    assert.ok(userCoupon.exists, "user coupon copy created");
    assert.strictEqual(userCoupon.data().percentage, 10);
    assert.strictEqual(userCoupon.data().max_discount, 50);
    assert.strictEqual(userCoupon.data().used, false);

    const master = await db.doc("coupons/SAVE10").get();
    assert.strictEqual(master.data().remaining_uses, 1);
  });

  it("rejects re-claiming a coupon the user already has", async () => {
    await db.collection("coupons").doc("SAVE10").set({
      code: "SAVE10", percentage: 10, max_discount: 50, remaining_uses: 5,
      expiry_date: future(),
    });
    await claim()({ data: { code: "SAVE10" }, auth: { uid: UID } });
    await assert.rejects(
      claim()({ data: { code: "SAVE10" }, auth: { uid: UID } }),
      /ya tienes/i
    );
  });

  it("rejects an unknown code", async () => {
    await assert.rejects(
      claim()({ data: { code: "NOPE" }, auth: { uid: UID } }),
      /no válido/i
    );
  });

  it("rejects an expired coupon", async () => {
    await db.collection("coupons").doc("OLD").set({
      code: "OLD", percentage: 5, max_discount: 10, remaining_uses: 5,
      expiry_date: past(),
    });
    await assert.rejects(
      claim()({ data: { code: "OLD" }, auth: { uid: UID } }),
      /expirado/i
    );
  });

  it("rejects an exhausted coupon (remaining_uses < 1)", async () => {
    await db.collection("coupons").doc("GONE").set({
      code: "GONE", percentage: 5, max_discount: 10, remaining_uses: 0,
      expiry_date: future(),
    });
    await assert.rejects(
      claim()({ data: { code: "GONE" }, auth: { uid: UID } }),
      /no está disponible/i
    );
  });

  it("rejects an unauthenticated call", async () => {
    await assert.rejects(
      claim()({ data: { code: "SAVE10" } }),
      /iniciar sesión/i
    );
  });

  it("snapshots productFilter onto the user-coupon when present", async () => {
    await db.collection("coupons").doc("DAIRY").set({
      code: "DAIRY",
      percentage: 15,
      max_discount: 100,
      remaining_uses: 5,
      expiry_date: future(),
      productFilter: {
        mode: "include",
        subcategories: ["Lácteos"],
        provedores: [],
        productIds: [],
      },
    });

    await claim()({ data: { code: "DAIRY" }, auth: { uid: UID } });

    const userCoupon = await db.doc(`users/${UID}/coupons/DAIRY`).get();
    assert.ok(userCoupon.exists);
    assert.deepStrictEqual(userCoupon.data().productFilter, {
      mode: "include",
      subcategories: ["Lácteos"],
      provedores: [],
      productIds: [],
    });
  });

  it("omits productFilter on user-coupon when master coupon has none", async () => {
    await db.collection("coupons").doc("FLAT").set({
      code: "FLAT", percentage: 10, max_discount: 50, remaining_uses: 5,
      expiry_date: future(),
    });

    await claim()({ data: { code: "FLAT" }, auth: { uid: UID } });
    const userCoupon = await db.doc(`users/${UID}/coupons/FLAT`).get();
    assert.strictEqual(userCoupon.data().productFilter, undefined);
  });
});

// ───────────────────────────────────────────────────────────────────────
describe("placeOrder", () => {
  const place = () => test.wrap(fns.placeOrder);

  async function seedWalletAndCoupon() {
    await db.doc(`users/${UID}/coupons/SAVE10`).set({
      code: "SAVE10", percentage: 10, max_discount: 50, used: false,
      expiry_date: future(),
    });
    await db.doc("settings/store").set({ pricing: { Centro: 15 } });
    await db.doc(`users/${UID}/addresses/a1`).set({ colonia: "Centro" });
    await db.doc(`users/${UID}/rewardsCard/cardInfo`).set({ cardNumber: CARD });
    await db.collection("rewards").doc("rw1").set({ cardNumber: CARD, saldo: 1000, cvvCode: "1234" });
  }

  it("recomputes discount/fee/saldo server-side and writes the order", async () => {
    await seedWalletAndCoupon();
    const res = await place()({
      data: {
        items: [{ productId: "p1", quantity: 1, price: 200 }],
        subtotal: 200,
        isInstorePickup: false,
        addressId: "a1",
        couponCode: "SAVE10",
        useRewardsBalance: true,
        paymentMethod: "efectivo",
      },
      auth: { uid: UID },
    });

    assert.strictEqual(res.success, true);
    const o = (await db.doc(`orders/${res.orderId}`).get()).data();
    // discount = min(200*10% = 20, max 50) = 20
    assert.strictEqual(o.discount, 20);
    assert.strictEqual(o.deliveryFee, 15);
    // total before rewards = 200 - 20 + 15 = 195; saldo covers all → final 0
    assert.strictEqual(o.appliedRewards, 195);
    assert.strictEqual(o.total, 0);
    assert.strictEqual(o.state, "En Revision");
    assert.strictEqual(o.userId, UID);

    // order mirrored into the user's history
    assert.ok((await db.doc(`users/${UID}/orderHistory/${res.orderId}`).get()).exists);
    // coupon spent
    assert.strictEqual((await db.doc(`users/${UID}/coupons/SAVE10`).get()).data().used, true);
    // saldo deducted
    assert.strictEqual((await db.doc("rewards/rw1").get()).data().saldo, 805);
  });

  it("falls back to a 20-peso fee for an unknown colonia", async () => {
    await seedWalletAndCoupon();
    await db.doc(`users/${UID}/addresses/a2`).set({ colonia: "Inexistente" });
    const res = await place()({
      data: {
        items: [{ productId: "p1", quantity: 1, price: 100 }],
        subtotal: 100,
        isInstorePickup: false,
        addressId: "a2",
      },
      auth: { uid: UID },
    });
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().deliveryFee, 20);
  });

  it("charges no delivery fee for in-store pickup", async () => {
    const res = await place()({
      data: {
        items: [{ productId: "p1", quantity: 1, price: 50 }],
        subtotal: 50,
        isInstorePickup: true,
      },
      auth: { uid: UID },
    });
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().deliveryFee, 0);
  });

  it("does not honour a coupon that is already used", async () => {
    await db.doc(`users/${UID}/coupons/SAVE10`).set({
      code: "SAVE10", percentage: 10, max_discount: 50, used: true,
      expiry_date: future(),
    });
    const res = await place()({
      data: {
        items: [{ productId: "p1", quantity: 1, price: 200 }],
        subtotal: 200,
        isInstorePickup: true,
        couponCode: "SAVE10",
      },
      auth: { uid: UID },
    });
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().discount, 0);
  });

  it("rejects an empty cart", async () => {
    await assert.rejects(
      place()({ data: { items: [] }, auth: { uid: UID } }),
      /carrito está vacío/i
    );
  });

  it("rejects an oversized cart (>200 lines) to prevent product-read amplification", async () => {
    const oversized = Array.from({ length: 201 }, (_, i) => ({
      productId: `p${i}`, quantity: 1, price: 1,
    }));
    await assert.rejects(
      place()({ data: { items: oversized, isInstorePickup: true }, auth: { uid: UID } }),
      /demasiado grande/i
    );
  });

  it("productFilter (include) narrows the discount to eligible subtotal", async () => {
    // p1 is dairy ($200), p2 is candy ($300). 10% coupon includes only dairy.
    // Eligible subtotal = 200, discount = min(200*10%=20, max 50) = 20.
    await db.collection("products").doc("p1").set({
      nombre: "Leche", category: "Lácteos", distribuitor_name: "Lala",
    });
    await db.collection("products").doc("p2").set({
      nombre: "Dulce", category: "Dulces", distribuitor_name: "Ricolino",
    });
    await db.doc(`users/${UID}/coupons/DAIRY`).set({
      code: "DAIRY", percentage: 10, max_discount: 50, used: false,
      expiry_date: future(),
      productFilter: { mode: "include", subcategories: ["Lácteos"], provedores: [], productIds: [] },
    });

    const res = await place()({
      data: {
        items: [
          { productId: "p1", quantity: 1, price: 200 },
          { productId: "p2", quantity: 1, price: 300 },
        ],
        subtotal: 500,
        isInstorePickup: true,
        couponCode: "DAIRY",
      },
      auth: { uid: UID },
    });
    const o = (await db.doc(`orders/${res.orderId}`).get()).data();
    assert.strictEqual(o.discount, 20);
    assert.deepStrictEqual(o.appliedCoupon.productFilter, {
      mode: "include", subcategories: ["Lácteos"], provedores: [], productIds: [],
    });
  });

  it("productFilter (exclude) skips matching items in the discount base", async () => {
    // Only candy is excluded. Eligible subtotal = 200 (the dairy).
    // discount = min(200*10% = 20, max 50) = 20.
    await db.collection("products").doc("p1").set({
      nombre: "Leche", category: "Lácteos", distribuitor_name: "Lala",
    });
    await db.collection("products").doc("p2").set({
      nombre: "Dulce", category: "Dulces", distribuitor_name: "Ricolino",
    });
    await db.doc(`users/${UID}/coupons/NOCANDY`).set({
      code: "NOCANDY", percentage: 10, max_discount: 50, used: false,
      expiry_date: future(),
      productFilter: { mode: "exclude", subcategories: ["Dulces"], provedores: [], productIds: [] },
    });

    const res = await place()({
      data: {
        items: [
          { productId: "p1", quantity: 1, price: 200 },
          { productId: "p2", quantity: 1, price: 300 },
        ],
        subtotal: 500,
        isInstorePickup: true,
        couponCode: "NOCANDY",
      },
      auth: { uid: UID },
    });
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().discount, 20);
  });

  it("productFilter (include) with zero eligible items yields no discount", async () => {
    await db.collection("products").doc("p2").set({
      nombre: "Dulce", category: "Dulces", distribuitor_name: "Ricolino",
    });
    await db.doc(`users/${UID}/coupons/DAIRY`).set({
      code: "DAIRY", percentage: 10, max_discount: 50, used: false,
      expiry_date: future(),
      productFilter: { mode: "include", subcategories: ["Lácteos"], provedores: [], productIds: [] },
    });

    const res = await place()({
      data: {
        items: [{ productId: "p2", quantity: 1, price: 300 }],
        subtotal: 300,
        isInstorePickup: true,
        couponCode: "DAIRY",
      },
      auth: { uid: UID },
    });
    // Coupon still marked used:true (defensible — UX shows "0 discount").
    // The point is the discount is correctly $0, not e.g. 30 (10% of 300).
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().discount, 0);
  });

  it("productFilter (include) IGNORES client-stamped category — only trusts product doc", async () => {
    // p1 is dairy per the product doc. Client tries to spoof p2 as dairy.
    await db.collection("products").doc("p1").set({
      nombre: "Leche", category: "Lácteos", distribuitor_name: "Lala",
    });
    await db.collection("products").doc("p2").set({
      nombre: "Dulce", category: "Dulces", distribuitor_name: "Ricolino",
    });
    await db.doc(`users/${UID}/coupons/DAIRY`).set({
      code: "DAIRY", percentage: 10, max_discount: 999, used: false,
      expiry_date: future(),
      productFilter: { mode: "include", subcategories: ["Lácteos"], provedores: [], productIds: [] },
    });

    const res = await place()({
      data: {
        items: [
          { productId: "p1", quantity: 1, price: 200 }, // genuinely Lácteos
          { productId: "p2", quantity: 1, price: 300, category: "Lácteos" }, // spoof
        ],
        subtotal: 500,
        isInstorePickup: true,
        couponCode: "DAIRY",
      },
      auth: { uid: UID },
    });
    // Eligible = 200 (only the genuine p1). discount = 10% of 200 = 20.
    // If the server trusted item.category, eligible would be 500 → discount = 50.
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().discount, 20);
  });

  it("productFilter (include) matches by provedor and by productId", async () => {
    await db.collection("products").doc("p1").set({
      nombre: "Leche", category: "Lácteos", distribuitor_name: "Lala",
    });
    await db.collection("products").doc("p2").set({
      nombre: "Dulce", category: "Dulces", distribuitor_name: "Ricolino",
    });
    await db.collection("products").doc("p3").set({
      nombre: "Otro", category: "Abarrotes", distribuitor_name: "ConAgra",
    });
    await db.doc(`users/${UID}/coupons/MIX`).set({
      code: "MIX", percentage: 10, max_discount: 999, used: false,
      expiry_date: future(),
      // Include items whose distribuitor_name is Lala OR whose id is p3.
      productFilter: {
        mode: "include",
        subcategories: [],
        provedores: ["Lala"],
        productIds: ["p3"],
      },
    });

    const res = await place()({
      data: {
        items: [
          { productId: "p1", quantity: 1, price: 200 }, // matches by provedor
          { productId: "p2", quantity: 1, price: 100 }, // no match
          { productId: "p3", quantity: 2, price: 50 },  // matches by productId
        ],
        subtotal: 400,
        isInstorePickup: true,
        couponCode: "MIX",
      },
      auth: { uid: UID },
    });
    // eligible = 200 + (50*2) = 300. discount = 10% of 300 = 30.
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().discount, 30);
  });

  it("expired coupon (failed-precondition at place time) yields no discount", async () => {
    // Pre-feature flow only checked expiry at claim. This test pins down the
    // newly added in-tx expiry guard inside placeOrder.
    await db.doc(`users/${UID}/coupons/STALE`).set({
      code: "STALE", percentage: 50, max_discount: 999, used: false,
      expiry_date: past(),
    });
    const res = await place()({
      data: {
        items: [{ productId: "p1", quantity: 1, price: 100 }],
        subtotal: 100,
        isInstorePickup: true,
        couponCode: "STALE",
      },
      auth: { uid: UID },
    });
    const o = (await db.doc(`orders/${res.orderId}`).get()).data();
    assert.strictEqual(o.discount, 0);
    assert.strictEqual(o.appliedCoupon, null);
    // Coupon NOT marked used (we never entered the discount branch).
    assert.strictEqual((await db.doc(`users/${UID}/coupons/STALE`).get()).data().used, false);
  });

  it("normalizes lower-case couponCode to upper-case before lookup", async () => {
    await db.doc(`users/${UID}/coupons/SAVE10`).set({
      code: "SAVE10", percentage: 10, max_discount: 50, used: false,
      expiry_date: future(),
    });
    const res = await place()({
      data: {
        items: [{ productId: "p1", quantity: 1, price: 100 }],
        subtotal: 100,
        isInstorePickup: true,
        couponCode: "save10", // lowercase — previously missed the doc
      },
      auth: { uid: UID },
    });
    assert.strictEqual((await db.doc(`orders/${res.orderId}`).get()).data().discount, 10);
  });
});

// ───────────────────────────────────────────────────────────────────────
describe("reinstateOnCancel", () => {
  const wrapped = () => test.wrap(fns.reinstateOnCancel);

  function change(beforeData, afterData) {
    const before = test.firestore.makeDocumentSnapshot(beforeData, "orders/o1");
    const after = test.firestore.makeDocumentSnapshot(afterData, "orders/o1");
    return test.makeChange(before, after);
  }

  async function seed() {
    await db.doc(`users/${UID}/rewardsCard/cardInfo`).set({ cardNumber: CARD });
    await db.collection("rewards").doc("rw1").set({ cardNumber: CARD, saldo: 100 });
    await db.doc(`users/${UID}/coupons/SAVE10`).set({ code: "SAVE10", used: true });
  }

  it("reinstates saldo AND the coupon on the transition into Cancelado", async () => {
    await seed();
    const base = { userId: UID, appliedRewards: 50, appliedCoupon: { code: "SAVE10" } };
    await wrapped()({
      data: change(
        { ...base, state: "En Revision" },
        { ...base, state: "Cancelado" }
      ),
      params: { orderId: "o1" },
    });

    assert.strictEqual((await db.doc("rewards/rw1").get()).data().saldo, 150);
    assert.strictEqual((await db.doc(`users/${UID}/coupons/SAVE10`).get()).data().used, false);
  });

  it("is a no-op if the order was already Cancelado (idempotent)", async () => {
    await seed();
    const base = { userId: UID, appliedRewards: 50, appliedCoupon: { code: "SAVE10" }, state: "Cancelado" };
    await wrapped()({ data: change({ ...base }, { ...base }), params: { orderId: "o1" } });

    // saldo untouched, coupon stays used
    assert.strictEqual((await db.doc("rewards/rw1").get()).data().saldo, 100);
    assert.strictEqual((await db.doc(`users/${UID}/coupons/SAVE10`).get()).data().used, true);
  });

  it("reinstates the coupon even when no saldo was applied", async () => {
    await seed();
    const base = { userId: UID, appliedRewards: 0, appliedCoupon: { code: "SAVE10" } };
    await wrapped()({
      data: change(
        { ...base, state: "En Revision" },
        { ...base, state: "Cancelado" }
      ),
      params: { orderId: "o1" },
    });
    assert.strictEqual((await db.doc("rewards/rw1").get()).data().saldo, 100);
    assert.strictEqual((await db.doc(`users/${UID}/coupons/SAVE10`).get()).data().used, false);
  });
});
