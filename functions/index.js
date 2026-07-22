const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentWritten, onDocumentDeleted } =
  require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const crypto = require("crypto");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ region: "us-central1", maxInstances: 10 });

const CARD_PREFIX = "T_STY-";

// ── VIP wallet QR token ──────────────────────────────────────────
// `TSTYV1.<24 random bytes, base64url>` — an opaque, server-minted loyalty
// token stored on the rewards doc as `qrToken`. The PDV (admin-authed,
// already reads `rewards` directly) resolves a scan by querying
// `rewards.where('qrToken','==',scanned)` — a match against an unguessable
// server value authenticates without shipping any secret into the APK.
// No HMAC/secret needed precisely because the PDV verifies by DB lookup, not
// stateless signature. isVip is read fresh from the doc (never baked into
// the token) so revocation just flips the flag.
const WALLET_TOKEN_PREFIX = "TSTYV1.";

function _mintWalletToken() {
  return `${WALLET_TOKEN_PREFIX}${crypto.randomBytes(24).toString("base64url")}`;
}

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

// Network-time anchor for the delivery-window picker: the client computes a
// clock-skew offset from this once per checkout so slot gating never trusts
// the device clock. Read-only and idempotent — safe to retry.
exports.getServerTime = onCall(async () => {
  return {epochMs: Date.now()};
});

// ── VIP enrollment ────────────────────────────────────────────────
// Opt-in only (owner decision): flips the persistent isVip flag on the
// rewards doc — the PDV reads it AT SCAN TIME, so the +50% accrual stops
// being inferable from a QR format — and mints the signed wallet token the
// gold card renders. Idempotent: re-enrolling refreshes the token, nothing
// else changes.
exports.enrollVip = onCall(async (request) => {
  const uid = requireAuth(request);
  const doc = await findRewardsForUser(uid);
  if (!doc) {
    throw new HttpsError(
      "failed-precondition",
      "Primero crea o vincula tu monedero para hacerte VIP."
    );
  }

  // Reuse an existing token if the doc already has one (re-enroll is
  // idempotent and keeps the printed/saved QR stable); otherwise mint.
  const existing = doc.data().qrToken;
  const token = (typeof existing === "string" &&
    existing.startsWith(WALLET_TOKEN_PREFIX)) ? existing : _mintWalletToken();

  await doc.ref.set(
    {
      isVip: true,
      vipSince: admin.firestore.FieldValue.serverTimestamp(),
      qrToken: token,
    },
    {merge: true}
  );
  // Mirror into the owner-readable card info so the client renders the gold
  // card + QR straight from its existing stream, no CF round-trip per view.
  await cardInfoRef(uid).set(
    {isVip: true, qrToken: token},
    {merge: true}
  );

  return {success: true, qrToken: token};
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

// Returns true if `uid` matches the coupon `eligibility` spec. Cheap single-
// user variant of `resolveAudienceUids` in the admin CF — never enumerates
// the whole audience, just queries the user's own orders.
//
//   { type: 'all' }                → everyone is eligible
//   { type: 'user', uid: 'x' }     → only that uid
//   { type: 'delivered' }          → uid must have ≥1 'Entregado' order
//   { type: 'recent', days: N }    → uid must have an order in the last N days
//   { type: 'none' }               → uid must have ZERO orders
async function isUserEligible(uid, eligibility) {
  const type = String((eligibility && eligibility.type) || "all");

  if (type === "all") return true;

  if (type === "user") {
    const target = String((eligibility && eligibility.uid) || "").trim();
    return !!target && target === uid;
  }

  if (type === "delivered") {
    const snap = await db
      .collection("orders")
      .where("userId", "==", uid)
      .where("state", "==", "Entregado")
      .limit(1)
      .get();
    return !snap.empty;
  }

  if (type === "recent") {
    const days =
      Number(eligibility && eligibility.days) > 0
        ? Number(eligibility.days)
        : 7;
    const cutoff = admin.firestore.Timestamp.fromMillis(
      Date.now() - days * 24 * 60 * 60 * 1000
    );
    const snap = await db
      .collection("orders")
      .where("userId", "==", uid)
      .where("timestamp", ">=", cutoff)
      .limit(1)
      .get();
    return !snap.empty;
  }

  if (type === "none") {
    const snap = await db
      .collection("orders")
      .where("userId", "==", uid)
      .limit(1)
      .get();
    return snap.empty;
  }

  // Unknown type → safest default is "nobody is eligible" rather than
  // accidentally allowing everyone. Admin would have to fix the doc.
  return false;
}

// Neutral rejection copy — we deliberately do NOT explain the specific
// audience reason (no purchases, too few purchases, wrong uid, etc.)
// because some of those phrasings read as accusatory or singling-out.
// A repeat customer rejected by an "only customers without orders"
// filter shouldn't feel like the system is judging their purchase
// history. Same generic message for every audience type.
//
// Kept as a function (rather than inlined) so the call site stays
// uniform if we ever want to vary the copy by language later on.
function eligibilityRejectionMessage(/* eligibility */) {
  return "Esta cuenta no cumple con los requisitos para reclamar este cupón.";
}

// Claim/grant a coupon to the signed-in user. Runs server-side (admin SDK) so
// clients can NEVER write their own coupon docs or tamper with the discount —
// percentage/max_discount are copied from the trusted master `coupons` doc and
// remaining_uses is decremented atomically.
//
// `coupons/{code}.eligibility` (optional, defaults to all) decides who can
// claim. If the requesting user fails the check, the CF rejects BEFORE writing
// anything to the user's subcollection. So sharing a code never works —
// receiving a notification doesn't grant the coupon, claiming does, and
// claiming is gated.
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

  // Eligibility check is OUTSIDE the transaction — it issues its own queries
  // against `orders`, which the runTransaction read-budget shouldn't have to
  // pay for. The cost is a small race window in which a user could become
  // newly eligible between this check and the claim write. That's fine: the
  // worst case is letting a barely-eligible claim through.
  const cSnapPreflight = await couponRef.get();
  if (!cSnapPreflight.exists) {
    throw new HttpsError("not-found", "Cupón no válido.");
  }
  const eligibility = cSnapPreflight.data().eligibility;
  if (eligibility && eligibility.type && eligibility.type !== "all") {
    const ok = await isUserEligible(uid, eligibility);
    if (!ok) {
      throw new HttpsError(
        "permission-denied",
        eligibilityRejectionMessage(eligibility)
      );
    }
  }

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

    // Snapshot productFilter onto the per-user doc at claim time. Same
    // pattern as percentage/max_discount — frozen-at-claim means a later
    // admin edit to the master coupon's filter doesn't retroactively shrink
    // what an already-claimed user can spend on. Field is OMITTED when the
    // master coupon has no filter (mode === 'all' or absent).
    const userCouponPayload = {
      code: c.code || code,
      percentage: c.percentage,
      max_discount: c.max_discount,
      expiry_date: c.expiry_date,
      used: false,
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    const filter = c.productFilter;
    if (filter && typeof filter === "object" &&
        (filter.mode === "include" || filter.mode === "exclude")) {
      userCouponPayload.productFilter = filter;
    }
    tx.set(userCouponRef, userCouponPayload);
    tx.update(couponRef, { remaining_uses: remaining - 1 });
  });

  return { success: true };
});

// ── Coupon product-eligibility helpers ─────────────────────────────────────
//
// `productFilter` (see lib/screens/marketing/product_filter.dart in
// t_sty_delivery) restricts which cart items a coupon's percentage applies
// against. We recompute the eligible portion of the subtotal here so the
// client cannot inflate the discount by lying about which items match.
//
// Strategy: when a filter is active we re-fetch each cart item's product
// doc and consult `category` + `distribuitor_name` (the typo'd field name
// is the real stored key — see project_product_field_typo memory). The
// items[] payload may also carry these fields client-stamped; we prefer
// the live product doc as the authoritative source.
function _isFilterActive(filter) {
  return filter && typeof filter === "object" &&
    (filter.mode === "include" || filter.mode === "exclude");
}

async function _fetchProductMetaForItems(items) {
  const ids = [];
  const seen = new Set();
  for (const it of items || []) {
    const pid = it && (it.productId || it.objectID);
    if (!pid) continue;
    const s = String(pid);
    if (seen.has(s)) continue;
    seen.add(s);
    ids.push(s);
  }
  if (ids.length === 0) return {};
  const refs = ids.map((id) => db.collection("products").doc(id));
  const snaps = await db.getAll(...refs);
  const meta = {};
  for (const snap of snaps) {
    if (!snap.exists) continue;
    const d = snap.data() || {};
    meta[snap.id] = {
      category: (d.category || "").toString(),
      distribuitor_name: (d.distribuitor_name || "").toString(),
    };
  }
  return meta;
}

function _computeEligibleSubtotal(items, filter, meta) {
  if (!_isFilterActive(filter)) return null;
  const subs = new Set(((filter.subcategories) || []).map(String));
  const provs = new Set(((filter.provedores) || []).map(String));
  const ids = new Set(((filter.productIds) || []).map(String));
  const mode = filter.mode;
  let eligible = 0;
  for (const it of items || []) {
    if (!it) continue;
    const pid = String(it.productId || it.objectID || "");
    const m = meta[pid] || {};
    // Authoritative product metadata only — NEVER trust client-stamped
    // category/distribuitor_name on items[]. A tampered client could
    // spoof those fields to slip into 'include' or out of 'exclude'
    // (or to match a category the live product doc reports as empty).
    // If the product doc was deleted/unreadable, meta is empty here and
    // the item simply fails category/provedor matching — still safe.
    const cat = String(m.category || "");
    const prov = String(m.distribuitor_name || "");
    const matchedCategory = cat && subs.has(cat);
    const matchedProvedor = prov && provs.has(prov);
    // productId IS authoritative (it's the cart line's identity).
    const matchedId = pid && ids.has(pid);
    const matched = matchedCategory || matchedProvedor || matchedId;
    const pass = mode === "include" ? !!matched : !matched;
    if (pass) {
      const qty = Number(it.quantity) || 0;
      const price = Number(it.price) || 0;
      eligible += qty * price;
    }
  }
  return eligible;
}

// Place an order: prices are recomputed server-side, saldo is validated and
// deducted atomically, and the order + history + coupon claim are written in
// one transaction.
// ──────────────────────────────────────────────────────────────────────────
// Order-window helpers
//
// Mirror of `lib/utils/order_window.dart` on the client. Both evaluate
// `settings/store` against the same rules so the server agrees with what
// the user saw in their app — and reject any order that slips through the
// client's gates (stale clock, modified APK, race past the cutoff).
// Times are evaluated in America/Mexico_City regardless of server clock.
// ──────────────────────────────────────────────────────────────────────────

const _ORDER_WINDOW_TIMEZONE = "America/Mexico_City";

function _nowInTz(tz) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    weekday: "short",
  }).formatToParts(new Date());
  const m = {};
  for (const p of parts) m[p.type] = p.value;
  // JS-style weekday short names → ISO 1..7 (Mon=1 … Sun=7) so the key
  // matches the `weeklySchedule` map written by the admin app.
  const weekdayMap = {Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7};
  return {
    weekday: weekdayMap[m.weekday] || 1,
    hour: parseInt(m.hour, 10) % 24,
    minute: parseInt(m.minute, 10),
  };
}

// Calendar date "YYYY-MM-DD" in the store timezone (en-CA locale formats
// exactly that shape). Used to pin delivery windows to "today".
function _todayDateInTz(tz) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: tz,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function _parseHhMm(s) {
  if (typeof s !== "string") return null;
  const m = s.trim().match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const h = parseInt(m[1], 10);
  const min = parseInt(m[2], 10);
  if (h < 0 || h > 24 || min < 0 || min > 59) return null;
  return {hour: h % 24, minute: min};
}

function _isInWindow(nowMin, startMin, endMin) {
  if (endMin === startMin) return false;
  if (endMin > startMin) return nowMin >= startMin && nowMin < endMin;
  // Wraps midnight (e.g. 22:00 → 08:00).
  return nowMin >= startMin || nowMin < endMin;
}

function _evaluateOrderWindow(storeData) {
  const now = _nowInTz(_ORDER_WINDOW_TIMEZONE);
  const nMin = now.hour * 60 + now.minute;

  // Quiet hours (default 22:00 → 08:00, admin-overridable).
  const qStart = (storeData && _parseHhMm(storeData.quietHours?.start)) ||
    {hour: 22, minute: 0};
  const qEnd = (storeData && _parseHhMm(storeData.quietHours?.end)) ||
    {hour: 8, minute: 0};
  const qStartMin = qStart.hour * 60 + qStart.minute;
  const qEndMin = qEnd.hour * 60 + qEnd.minute;
  if (_isInWindow(nMin, qStartMin, qEndMin)) {
    return {
      status: "closed",
      quietStart: qStart,
      quietEnd: qEnd,
    };
  }

  // Today's delivery entry.
  let open = {hour: 9, minute: 0};
  let close = {hour: 18, minute: 0};
  let restToday = false;

  const schedule = storeData ? storeData.weeklySchedule : null;
  if (schedule && typeof schedule === "object") {
    const entry = schedule[String(now.weekday)];
    if (entry && typeof entry === "object") {
      restToday = entry.closed === true;
      open = _parseHhMm(entry.open) || open;
      close = _parseHhMm(entry.close) || close;
    }
  } else {
    if (typeof storeData?.open_hour === "number") {
      open = {hour: storeData.open_hour, minute: 0};
    }
    if (typeof storeData?.close_hour === "number") {
      close = {hour: storeData.close_hour, minute: 0};
    }
  }
  const oMin = open.hour * 60 + open.minute;
  const cMin = close.hour * 60 + close.minute;
  const canDeliver = !restToday && _isInWindow(nMin, oMin, cMin);
  return {
    status: canDeliver ? "open" : "pickupOnly",
    todayOpen: open,
    todayClose: close,
    deliveryRestToday: restToday,
    quietStart: qStart,
    quietEnd: qEnd,
  };
}

function _fmtHm(t) {
  const h12 = t.hour === 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
  const sfx = t.hour < 12 ? "AM" : "PM";
  return t.minute === 0
    ? `${h12} ${sfx}`
    : `${h12}:${String(t.minute).padStart(2, "0")} ${sfx}`;
}

/**
 * Canonical form of a colonia name, for matching against `settings/store`
 * pricing keys. Case-folds, trims, collapses whitespace and strips accents.
 *
 * Addresses are written from two sources — the curated dropdown and free text
 * (including the geocoder's `subLocality`) — so "Centro", "centro" and
 * "Céntro" all refer to the same place. Must stay in sync with
 * normalizeColonia() in lib/app/payment/checkout_page.dart, or the fee shown
 * at checkout will differ from the fee actually charged.
 */
function normalizeColonia(s) {
  return String(s || "")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .trim()
    .replace(/\s+/g, " ");
}

exports.placeOrder = onCall(async (request) => {
  const uid = requireAuth(request);
  const payload = request.data || {};
  const items = Array.isArray(payload.items) ? payload.items : [];
  if (items.length === 0) {
    throw new HttpsError("invalid-argument", "El carrito está vacío.");
  }
  // Defense-in-depth: real carts are nowhere near 200 lines. Without this
  // cap, a malicious client could send thousands of unique fabricated
  // productIds and force the productFilter preflight (when a coupon is
  // applied) to issue an unbounded `db.getAll` for each one. Reject upfront.
  if (items.length > 200) {
    throw new HttpsError("invalid-argument", "Carrito demasiado grande.");
  }

  // Subtotal is trusted from the client. Combo & promotion pricing is computed
  // client-side (CartProvider) — combos are real product line-items at full
  // price with the saving folded into the discount, exactly like promotions —
  // so `totalPriceAfterDiscount` is sent here and not re-derived server-side
  // (re-summing raw item prices would ignore the combo/promo discount).
  const subtotal = Number(payload.subtotal) || 0;
  const isPickup = payload.isInstorePickup === true;
  const addressId = payload.addressId || null;
  // Normalize coupon code casing — admin/claimCoupon both upper-case it, so
  // the doc id is always uppercase. Without this normalization a client that
  // sends 'welcome10' silently misses the discount.
  const couponCode = payload.couponCode
    ? String(payload.couponCode).trim().toUpperCase()
    : null;
  const useRewards = payload.useRewardsBalance === true;
  // Optional free-text order note — trimmed and hard-capped so it can't be
  // used to bloat the doc. Empty string when absent.
  const notes = payload.notes
    ? String(payload.notes).trim().slice(0, 300)
    : "";
  // Cash "pago con": how much the customer will hand over so the driver
  // brings change. Only meaningful for efectivo; null otherwise.
  const cashPaidWithRaw = Number(payload.cashPaidWith);
  const cashPaidWith =
    payload.paymentMethod === "efectivo" &&
    Number.isFinite(cashPaidWithRaw) && cashPaidWithRaw > 0
      ? cashPaidWithRaw
      : null;

  // ── Coupon product-filter preflight ────────────────────────────────────
  // If the user's coupon has an active productFilter, we need to look up
  // each cart item's product metadata to recompute the eligible subtotal.
  // Read OUTSIDE the transaction (the tx's read budget is for the writes,
  // and product metadata can change without affecting redemption integrity).
  let productMetaById = {};
  let productFilterSpec = null;
  if (couponCode) {
    const preRef = db.collection("users").doc(uid)
      .collection("coupons").doc(couponCode);
    const preSnap = await preRef.get();
    if (preSnap.exists && preSnap.data().used !== true) {
      const filter = preSnap.data().productFilter;
      if (_isFilterActive(filter)) {
        productFilterSpec = filter;
        productMetaById = await _fetchProductMetaForItems(items);
      }
    }
  }

  // ── settings/store fetch ────────────────────────────────────────────
  // Fetched up front because both the order-window enforcement (below)
  // AND the delivery-fee math (further down) read from the same doc.
  // Single read, used twice.
  const settingsSnap = await db.collection("settings").doc("store").get();
  const storeData = settingsSnap.exists ? settingsSnap.data() : {};

  // ── Order-window enforcement ────────────────────────────────────────
  // Mirrors the client's `OrderWindow` (lib/utils/order_window.dart) so a
  // stale client or a tampered app can't sneak a delivery through outside
  // the configured window, or any order through during quiet hours.
  const win = _evaluateOrderWindow(storeData);
  if (win.status === "closed") {
    throw new HttpsError(
      "failed-precondition",
      `No estamos tomando pedidos entre ${_fmtHm(win.quietStart)} y ${_fmtHm(win.quietEnd)}. Vuelve más tarde.`
    );
  }
  if (!isPickup && win.status === "pickupOnly") {
    throw new HttpsError(
      "failed-precondition",
      win.deliveryRestToday
        ? "Hoy no estamos haciendo entregas a domicilio. Selecciona Pick-Up para recoger en tienda."
        : `Las entregas a domicilio se reanudan a las ${_fmtHm(win.todayOpen)}. Mientras tanto puedes recoger en tienda.`
    );
  }

  // ── Delivery-window validation (optional 30-min slot) ────────────────
  // {date:'YYYY-MM-DD', start:'HH:mm', end:'HH:mm'}. Absent = "lo antes
  // posible". SERVER time decides everything — a tampered device clock
  // can't buy a stale slot. Rules: 30-min aligned block, today (store tz),
  // starts >= now+30min, and inside delivery hours (or fully outside quiet
  // hours for pickup).
  let deliveryWindow = null;
  if (payload.deliveryWindow != null) {
    const dw = payload.deliveryWindow;
    const start = _parseHhMm(dw && dw.start);
    const end = _parseHhMm(dw && dw.end);
    const date = dw && typeof dw.date === "string" ? dw.date.trim() : null;
    if (!start || !end || !date) {
      throw new HttpsError("invalid-argument", "Ventana de entrega inválida.");
    }
    const startMin = start.hour * 60 + start.minute;
    const endMin = end.hour * 60 + end.minute;
    if (startMin % 30 !== 0 || endMin !== startMin + 30) {
      throw new HttpsError(
        "invalid-argument",
        "La ventana debe ser un bloque de 30 minutos."
      );
    }
    if (date !== _todayDateInTz(_ORDER_WINDOW_TIMEZONE)) {
      throw new HttpsError(
        "failed-precondition",
        "La ventana elegida ya no es de hoy. Elige otro horario."
      );
    }
    const nowTz = _nowInTz(_ORDER_WINDOW_TIMEZONE);
    const nowMin = nowTz.hour * 60 + nowTz.minute;
    if (startMin < nowMin + 30) {
      throw new HttpsError(
        "failed-precondition",
        "Ese horario ya no está disponible — elige uno al menos 30 minutos después de ahora."
      );
    }
    if (!isPickup) {
      const oMin = win.todayOpen.hour * 60 + win.todayOpen.minute;
      const cMin = win.todayClose.hour * 60 + win.todayClose.minute;
      if (startMin < oMin || endMin > cMin) {
        throw new HttpsError(
          "failed-precondition",
          `Las entregas de hoy son de ${_fmtHm(win.todayOpen)} a ${_fmtHm(win.todayClose)}.`
        );
      }
    } else {
      const qs = win.quietStart.hour * 60 + win.quietStart.minute;
      const qe = win.quietEnd.hour * 60 + win.quietEnd.minute;
      if (_isInWindow(startMin, qs, qe) || _isInWindow(endMin - 1, qs, qe)) {
        throw new HttpsError(
          "failed-precondition",
          "Ese horario está fuera del horario de la tienda."
        );
      }
    }
    deliveryWindow = {date, start: String(dw.start).trim(), end: String(dw.end).trim()};
  }

  // Delivery fee — recomputed server-side from settings/store pricing by colonia.
  let deliveryFee = 0;
  if (!isPickup && addressId) {
    const addrSnap = await db
      .collection("users")
      .doc(uid)
      .collection("addresses")
      .doc(String(addressId))
      .get();
    const pricing = storeData.pricing || {};
    const colonia = addrSnap.exists ? addrSnap.data().colonia : null;
    if (colonia) {
      // Match on a normalized colonia rather than the raw string. Addresses
      // are written from two sources — the curated dropdown and free text
      // (including the geocoder's `subLocality`) — so the same place shows up
      // as "Centro" / "centro" / "Céntro". Exact-key matching billed the same
      // colonia at different rates depending on how the address was created.
      // Must stay in sync with normalizeColonia() in checkout_page.dart, or
      // the price previewed at checkout won't match the price charged.
      const target = normalizeColonia(colonia);
      let best = null;
      for (const [key, value] of Object.entries(pricing)) {
        if (normalizeColonia(key) !== target) continue;
        const v = typeof value === "number" ? value : parseFloat(value);
        if (!Number.isFinite(v)) continue;
        // Lowest wins on a duplicate/typo'd key, so a data-entry slip can
        // never overcharge a customer.
        if (best === null || v < best) best = v;
      }
      deliveryFee = best === null ? 20 : best;
    }
  }

  const orderRef = db.collection("orders").doc();

  const result = await db.runTransaction(async (tx) => {
    // ---- reads (all gets before any writes) ----
    // Coupon discount — recomputed from the actual coupon doc, never trusted from
    // the client. Only applied if the coupon exists, is unused, and is unexpired
    // (expiry was previously checked only at claim time — re-checking here
    // catches users who claimed, sat on the code, then redeemed past expiry).
    let discount = 0;
    let appliedCoupon = null;
    let couponRef = null;
    if (couponCode) {
      const ref = db
        .collection("users")
        .doc(uid)
        .collection("coupons")
        .doc(couponCode);
      const cSnap = await tx.get(ref);
      if (cSnap.exists && cSnap.data().used !== true) {
        const c = cSnap.data();
        const exp = c.expiry_date;
        const expired = exp && typeof exp.toDate === "function" &&
          exp.toDate() < new Date();
        if (!expired) {
          const pct = Number(c.percentage) || 0;
          const maxDiscount = Number(c.max_discount) || 0;
          // Product-eligibility filter — the tx-read of the user-coupon doc
          // is the authoritative source. (`productFilterSpec` from the
          // preflight should always equal `c.productFilter` since user-
          // coupons are never updated post-claim, but we prefer the tx
          // value for consistency with how percentage/max_discount are
          // read.) Product metadata was already fetched outside the tx
          // when the preflight detected an active filter.
          const filter = _isFilterActive(c.productFilter)
            ? c.productFilter
            : null;
          let base = subtotal;
          const eligibleSubtotal = _computeEligibleSubtotal(
            items, filter, productMetaById,
          );
          if (eligibleSubtotal != null) {
            // Clamp to the trusted client subtotal — should never exceed it
            // but defends against an inflated items[] payload.
            base = Math.min(eligibleSubtotal, subtotal);
          }
          discount = Math.min((base * pct) / 100, maxDiscount);
          if (discount < 0) discount = 0;
          appliedCoupon = {
            code: couponCode,
            percentage: pct,
            max_discount: maxDiscount,
          };
          // Snapshot the filter on the order so order_detail + history can
          // explain WHY the coupon discount was what it was.
          if (filter) {
            appliedCoupon.productFilter = filter;
          }
          couponRef = ref;
        }
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
      // Server-validated 30-min slot, or null = "lo antes posible".
      deliveryWindow: deliveryWindow,
      // Free-text order note from the customer (may be empty).
      notes: notes,
      // Cash amount the customer will pay with, or null (non-cash/unspecified).
      cashPaidWith: cashPaidWith,
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

// ────────────── ORDER-HISTORY ARCHIVE ──────────────
//
// The client app used to hard-delete any `users/{uid}/orderHistory/{id}`
// doc older than 30 days every time the user opened their history screen.
// That destroyed the customer-visible record of older orders even if the
// admin or support needed to look them up later. The client no longer
// deletes (the page now hides older entries behind a "Ver pedidos
// anteriores" expander instead), but a stale app version, a manual admin
// cleanup, or any future migration could still trigger a delete.
//
// This trigger fires on EVERY orderHistory delete and mirrors the doc to
// `users/{uid}/order_archive/{id}` with a `deletedAt` server timestamp.
// The archive is admin-readable only (rules), so we can always recover
// the canonical order shape the customer originally saw. Cheap, idempotent
// (mirror with the same id; a duplicate delete just re-stamps the same
// archive doc), and impossible for the client to bypass.
exports.archiveDeletedOrderHistory = onDocumentDeleted(
  "users/{uid}/orderHistory/{orderId}",
  async (event) => {
    const uid = event.params.uid;
    const orderId = event.params.orderId;
    const data = event.data && event.data.data();
    if (!data) return;
    try {
      await db
        .collection("users")
        .doc(uid)
        .collection("order_archive")
        .doc(orderId)
        .set({
          ...data,
          archivedFrom: "orderHistory",
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    } catch (e) {
      console.error("archiveDeletedOrderHistory failed", uid, orderId, e);
    }
  }
);
