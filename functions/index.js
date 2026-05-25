const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

const CARD_PREFIX = "T_STY-";

function requireAuth(request) {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Debes iniciar sesión.");
  }
  return request.auth.uid;
}

function normalizePhone(phone) {
  return String(phone || "").replace(/\D/g, "");
}

function cardInfoRef(uid) {
  return db.collection("users").doc(uid).collection("rewardsCard").doc("cardInfo");
}

// Find the canonical rewards doc for the card the user is linked to.
async function findRewardsForUser(uid) {
  const snap = await cardInfoRef(uid).get();
  if (!snap.exists || !snap.data().cardNumber) return null;
  const q = await db
    .collection("rewards")
    .where("cardNumber", "==", snap.data().cardNumber)
    .limit(1)
    .get();
  return q.empty ? null : q.docs[0];
}

// ── Rate limiting for wallet linking (anti brute-force) ──────────
const MAX_ATTEMPTS = 5;
const WINDOW_MS = 15 * 60 * 1000;

async function recordLinkAttempt(uid) {
  const ref = db.collection("rewardsLinkAttempts").doc(uid);
  const now = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    let count = 0;
    let windowStart = now;
    if (snap.exists) {
      const d = snap.data();
      windowStart = d.windowStart || now;
      count = d.count || 0;
      if (now - windowStart > WINDOW_MS) {
        windowStart = now;
        count = 0;
      }
    }
    if (count >= MAX_ATTEMPTS) {
      throw new HttpsError(
        "resource-exhausted",
        "Demasiados intentos. Intenta de nuevo más tarde."
      );
    }
    tx.set(ref, { count: count + 1, windowStart }, { merge: true });
  });
}

async function clearLinkAttempts(uid) {
  await db.collection("rewardsLinkAttempts").doc(uid).delete().catch(() => {});
}

exports.createRewardsWallet = onCall(async (request) => {
  const uid = requireAuth(request);
  const phone = normalizePhone(request.data.phone);
  const pin = String(request.data.pin || "").trim();
  const holderName = String(request.data.holderName || "").trim().toUpperCase();

  if (phone.length !== 10) {
    throw new HttpsError("invalid-argument", "Teléfono inválido.");
  }
  if (!/^\d{4}$/.test(pin)) {
    throw new HttpsError("invalid-argument", "El NIP debe ser de 4 dígitos.");
  }

  const cardNumber = CARD_PREFIX + phone;
  const d = new Date();
  const customerSince = `${String(d.getMonth() + 1).padStart(2, "0")}/${d.getFullYear()}`;

  const dup = await db
    .collection("rewards")
    .where("cardNumber", "==", cardNumber)
    .limit(1)
    .get();
  if (!dup.empty) {
    throw new HttpsError("already-exists", "Ya existe un monedero con ese teléfono.");
  }

  await db.collection("rewards").doc(uid).set({
    cardNumber,
    customerSince,
    cardHolderName: holderName,
    cvvCode: pin,
    saldo: 0,
  });

  // Public card info under the user's own (owner-only) space — no PIN here;
  // the PIN lives only in the rewards doc (single source of truth).
  await cardInfoRef(uid).set({
    cardNumber,
    customerSince,
    cardHolderName: holderName,
  });

  return { success: true, cardNumber, customerSince };
});

exports.linkRewardsWallet = onCall(async (request) => {
  const uid = requireAuth(request);
  const phone = normalizePhone(request.data.phone);
  const pin = String(request.data.pin || "").trim();

  if (phone.length !== 10 || !/^\d{4}$/.test(pin)) {
    throw new HttpsError("invalid-argument", "Datos inválidos.");
  }

  await recordLinkAttempt(uid);

  const cardNumber = CARD_PREFIX + phone;
  const q = await db
    .collection("rewards")
    .where("cardNumber", "==", cardNumber)
    .limit(1)
    .get();

  // Same error for "no wallet" and "wrong PIN" so neither can be enumerated.
  if (q.empty || q.docs[0].data().cvvCode !== pin) {
    throw new HttpsError("not-found", "No se encontró un monedero con esos datos.");
  }

  await clearLinkAttempts(uid);

  const data = q.docs[0].data();
  await cardInfoRef(uid).set({
    cardNumber: data.cardNumber,
    customerSince: data.customerSince || "",
    cardHolderName: data.cardHolderName || "",
  });

  return { success: true };
});

exports.getRewardsBalance = onCall(async (request) => {
  const uid = requireAuth(request);
  const doc = await findRewardsForUser(uid);
  if (!doc) return { hasWallet: false, saldo: 0 };
  const d = doc.data();
  return {
    hasWallet: true,
    saldo: Number(d.saldo) || 0,
    cvvCode: d.cvvCode || "",
    cardNumber: d.cardNumber || "",
    cardHolderName: d.cardHolderName || "",
    customerSince: d.customerSince || "",
  };
});

exports.updateRewardsCard = onCall(async (request) => {
  const uid = requireAuth(request);
  const newPin = request.data.pin != null ? String(request.data.pin).trim() : null;
  const newPhone = request.data.phone != null ? normalizePhone(request.data.phone) : null;

  const doc = await findRewardsForUser(uid);
  if (!doc) throw new HttpsError("not-found", "No se encontró ningún monedero.");

  const updates = {};
  const cardInfoUpdates = {};
  if (newPin != null) {
    if (!/^\d{4}$/.test(newPin)) {
      throw new HttpsError("invalid-argument", "El NIP debe ser de 4 dígitos.");
    }
    updates.cvvCode = newPin;
  }
  if (newPhone != null) {
    if (newPhone.length !== 10) {
      throw new HttpsError("invalid-argument", "Teléfono inválido.");
    }
    updates.cardNumber = CARD_PREFIX + newPhone;
    cardInfoUpdates.cardNumber = CARD_PREFIX + newPhone;
  }

  if (Object.keys(updates).length > 0) await doc.ref.update(updates);
  if (Object.keys(cardInfoUpdates).length > 0) {
    await cardInfoRef(uid).update(cardInfoUpdates);
  }
  return { success: true };
});

// Claim/grant a coupon to the signed-in user. Runs server-side (admin SDK) so
// clients can NEVER write their own coupon docs or tamper with the discount —
// percentage/max_discount are copied from the trusted master `coupons` doc and
// remaining_uses is decremented atomically.
exports.claimCoupon = onCall(async (request) => {
  const uid = requireAuth(request);
  const code = String((request.data && request.data.code) || "")
    .trim()
    .toUpperCase();
  if (!code) {
    throw new HttpsError("invalid-argument", "Escribe un código de cupón.");
  }

  const couponRef = db.collection("coupons").doc(code);
  const userCouponRef = db
    .collection("users")
    .doc(uid)
    .collection("coupons")
    .doc(code);

  await db.runTransaction(async (tx) => {
    const cSnap = await tx.get(couponRef);
    if (!cSnap.exists) {
      throw new HttpsError("not-found", "Cupón no válido.");
    }
    const c = cSnap.data();
    const remaining = Number(c.remaining_uses) || 0;
    if (remaining < 1) {
      throw new HttpsError(
        "failed-precondition",
        "Este cupón ya no está disponible."
      );
    }
    const expiry = c.expiry_date;
    if (expiry && typeof expiry.toDate === "function" &&
        expiry.toDate() < new Date()) {
      throw new HttpsError("failed-precondition", "Este cupón ha expirado.");
    }

    const uSnap = await tx.get(userCouponRef);
    if (uSnap.exists) {
      throw new HttpsError(
        "already-exists",
        uSnap.data().used === true
          ? "Este cupón ya ha sido utilizado."
          : "Ya tienes este cupón."
      );
    }

    tx.set(userCouponRef, {
      code: c.code || code,
      percentage: c.percentage,
      max_discount: c.max_discount,
      expiry_date: c.expiry_date,
      used: false,
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    tx.update(couponRef, { remaining_uses: remaining - 1 });
  });

  return { success: true };
});

// Place an order: prices are recomputed server-side, saldo is validated and
// deducted atomically, and the order + history + coupon claim are written in
// one transaction.
exports.placeOrder = onCall(async (request) => {
  const uid = requireAuth(request);
  const payload = request.data || {};
  const items = Array.isArray(payload.items) ? payload.items : [];
  if (items.length === 0) {
    throw new HttpsError("invalid-argument", "El carrito está vacío.");
  }

  // Subtotal is trusted from the client. Combo & promotion pricing is computed
  // client-side (CartProvider) — combos are real product line-items at full
  // price with the saving folded into the discount, exactly like promotions —
  // so `totalPriceAfterDiscount` is sent here and not re-derived server-side
  // (re-summing raw item prices would ignore the combo/promo discount).
  const subtotal = Number(payload.subtotal) || 0;
  const isPickup = payload.isInstorePickup === true;
  const addressId = payload.addressId || null;
  const couponCode = payload.couponCode || null;
  const useRewards = payload.useRewardsBalance === true;

  // Delivery fee — recomputed server-side from settings/store pricing by colonia.
  let deliveryFee = 0;
  if (!isPickup && addressId) {
    const [settingsSnap, addrSnap] = await Promise.all([
      db.collection("settings").doc("store").get(),
      db
        .collection("users")
        .doc(uid)
        .collection("addresses")
        .doc(String(addressId))
        .get(),
    ]);
    const pricing = settingsSnap.exists ? settingsSnap.data().pricing || {} : {};
    const colonia = addrSnap.exists ? addrSnap.data().colonia : null;
    if (colonia) {
      if (pricing[colonia] != null) {
        const v = pricing[colonia];
        deliveryFee = typeof v === "number" ? v : parseFloat(v) || 0;
      } else {
        deliveryFee = 20;
      }
    }
  }

  const orderRef = db.collection("orders").doc();

  const result = await db.runTransaction(async (tx) => {
    // ---- reads (all gets before any writes) ----
    // Coupon discount — recomputed from the actual coupon doc, never trusted from
    // the client. Only applied if the coupon exists and is unused.
    let discount = 0;
    let appliedCoupon = null;
    let couponRef = null;
    if (couponCode) {
      const ref = db
        .collection("users")
        .doc(uid)
        .collection("coupons")
        .doc(String(couponCode));
      const cSnap = await tx.get(ref);
      if (cSnap.exists && cSnap.data().used !== true) {
        const c = cSnap.data();
        const pct = Number(c.percentage) || 0;
        const maxDiscount = Number(c.max_discount) || 0;
        discount = Math.min((subtotal * pct) / 100, maxDiscount);
        if (discount < 0) discount = 0;
        appliedCoupon = { code: couponCode, percentage: pct, max_discount: maxDiscount };
        couponRef = ref;
      }
    }

    let rewardsRef = null;
    let currentSaldo = 0;
    if (useRewards) {
      const info = await tx.get(cardInfoRef(uid));
      if (info.exists && info.data().cardNumber) {
        const rq = await tx.get(
          db.collection("rewards").where("cardNumber", "==", info.data().cardNumber).limit(1)
        );
        if (!rq.empty) {
          rewardsRef = rq.docs[0].ref;
          currentSaldo = Number(rq.docs[0].data().saldo) || 0;
        }
      }
    }

    // ---- compute ----
    let total = subtotal - discount + deliveryFee;
    if (total < 0) total = 0;
    const appliedRewards = rewardsRef ? Math.min(currentSaldo, total) : 0;
    const finalTotal = total - appliedRewards;

    // ---- writes ----
    const orderData = {
      userId: uid,
      addressId: isPickup ? null : addressId,
      paymentMethod: payload.paymentMethod || null,
      items: items,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      discount: discount,
      total: finalTotal,
      appliedRewards: appliedRewards,
      useRewardsBalance: useRewards,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      appliedCoupon: appliedCoupon,
      state: "En Revision",
      isInstorePickup: isPickup,
    };

    tx.set(orderRef, orderData);
    tx.set(db.collection("users").doc(uid).collection("orderHistory").doc(orderRef.id), orderData);
    if (rewardsRef && appliedRewards > 0) {
      tx.update(rewardsRef, { saldo: currentSaldo - appliedRewards });
    }
    if (couponRef) {
      tx.update(couponRef, { used: true });
    }

    return { orderId: orderRef.id, total: finalTotal, appliedRewards };
  });

  return { success: true, ...result };
});

/**
 * Reinstate spent monedero saldo when an order is cancelled.
 *
 * Fires on the transition INTO "Cancelado" (from any prior state), so it
 * covers BOTH admin cancellations and customer self-cancellations — the
 * client can't write the locked `rewards` doc itself, so this has to run with
 * admin credentials. Atomic `increment(appliedRewards)` is the exact inverse
 * of placeOrder's deduction; it never reads the live balance (which can drift
 * between placement and cancellation). Idempotent: only the state transition
 * triggers it, so re-saving a cancelled order won't double-credit.
 *
 * Coupon reversal also runs here: clients can no longer write their own coupon
 * docs (locked by rules), so the spent coupon is flipped back to `used: false`
 * server-side. This covers BOTH customer self-cancellations and admin
 * cancellations from a single place, and `used: false` is idempotent.
 */
exports.reinstateOnCancel = onDocumentWritten("orders/{orderId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return;
  if (before.state === "Cancelado" || after.state !== "Cancelado") return;

  const uid = after.userId;
  if (!uid) return;

  // Reinstate spent monedero saldo — exact inverse of placeOrder's deduction.
  const appliedRewards = Number(after.appliedRewards || 0);
  if (appliedRewards > 0) {
    try {
      const rewardsDoc = await findRewardsForUser(uid);
      if (rewardsDoc) {
        await rewardsDoc.ref.update({
          saldo: admin.firestore.FieldValue.increment(appliedRewards),
        });
      }
    } catch (e) {
      console.error("reinstateOnCancel saldo failed", uid, e);
    }
  }

  // Reinstate the spent coupon so the customer can reuse it.
  const couponCode = after.appliedCoupon && after.appliedCoupon.code
    ? String(after.appliedCoupon.code).trim().toUpperCase()
    : "";
  if (couponCode && couponCode !== "N/A") {
    try {
      await db
        .collection("users")
        .doc(uid)
        .collection("coupons")
        .doc(couponCode)
        .set({ used: false }, { merge: true });
    } catch (e) {
      console.error("reinstateOnCancel coupon failed", uid, e);
    }
  }
});
