/**
 * Security-rules tests for arthemis-f2966 (the ruleset shared byte-for-byte by
 * the client app and the admin app). Run against the Firestore emulator:
 *
 *   cd firestore-tests && npm install            # first time only
 *   firebase emulators:exec --only firestore "npm --prefix firestore-tests test"
 *
 * Covers every collection in firestore.rules. The five hardening changes are
 * tagged [#1]..[#5] in the relevant describe blocks.
 */
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  collection,
  addDoc,
  getDocs,
  query,
  where,
  serverTimestamp,
  setLogLevel,
} = require("firebase/firestore");

// The emulator logs every assertFails() as a PERMISSION_DENIED error — that's
// expected noise, so quiet the client SDK to keep the report readable.
setLogLevel("silent");

const PROJECT_ID = "arthemis-f2966";

// UIDs straight from the ruleset's isAdmin()/isStockEditor() lists.
const ADMIN = "HnqE2Asz6HPvmM10OAIAsu1RaL62";
const STOCK = "MzmOCRtAwgU6NgkxzCfRuEnfRug1";
const ALICE = "alice-uid";
const BOB = "bob-uid";

let testEnv;

const adminDb = () => testEnv.authenticatedContext(ADMIN).firestore();
const stockDb = () => testEnv.authenticatedContext(STOCK).firestore();
const aliceDb = () => testEnv.authenticatedContext(ALICE).firestore();
const bobDb = () => testEnv.authenticatedContext(BOB).firestore();
const guestDb = () => testEnv.unauthenticatedContext().firestore();

// Seed documents bypassing the rules.
async function seed(pathStr, data) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), pathStr), data);
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "../../firestore.rules"),
        "utf8"
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

// ─────────────────────────────────────────────────────────────────────────
describe("master coupons [#3 read → admin-only]", () => {
  it("guest cannot read", async () => {
    await seed("coupons/SAVE10", { code: "SAVE10", remaining_uses: 5 });
    await assertFails(getDoc(doc(guestDb(), "coupons/SAVE10")));
  });
  it("authenticated non-admin cannot read", async () => {
    await seed("coupons/SAVE10", { code: "SAVE10", remaining_uses: 5 });
    await assertFails(getDoc(doc(aliceDb(), "coupons/SAVE10")));
  });
  it("admin can read", async () => {
    await seed("coupons/SAVE10", { code: "SAVE10", remaining_uses: 5 });
    await assertSucceeds(getDoc(doc(adminDb(), "coupons/SAVE10")));
  });
  it("admin can create, client cannot", async () => {
    await assertSucceeds(setDoc(doc(adminDb(), "coupons/NEW"), { code: "NEW" }));
    await assertFails(setDoc(doc(aliceDb(), "coupons/HACK"), { code: "HACK" }));
  });
});

// ─────────────────────────────────────────────────────────────────────────
describe("orders [#4 client read-only + cancel-only update]", () => {
  const order = (over = {}) => ({
    userId: ALICE,
    state: "En Revision",
    total: 100,
    appliedRewards: 50,
    appliedCoupon: { code: "SAVE10" },
    items: [],
    ...over,
  });

  it("owner reads own order, stranger cannot", async () => {
    await seed("orders/o1", order());
    await assertSucceeds(getDoc(doc(aliceDb(), "orders/o1")));
    await assertFails(getDoc(doc(bobDb(), "orders/o1")));
  });

  it("client cannot create or delete (placeOrder CF only)", async () => {
    await assertFails(setDoc(doc(aliceDb(), "orders/new"), order()));
    await seed("orders/o1", order());
    await assertFails(deleteDoc(doc(aliceDb(), "orders/o1")));
  });

  it("owner may cancel an En Revision order (state + timestamp only)", async () => {
    await seed("orders/o1", order());
    await assertSucceeds(
      updateDoc(doc(aliceDb(), "orders/o1"), {
        state: "Cancelado",
        cancellationTimestamp: serverTimestamp(),
      })
    );
  });

  it("owner cannot flip order to Entregado", async () => {
    await seed("orders/o1", order());
    await assertFails(
      updateDoc(doc(aliceDb(), "orders/o1"), { state: "Entregado" })
    );
  });

  it("owner cannot rewrite total/items while cancelling", async () => {
    await seed("orders/o1", order());
    await assertFails(
      updateDoc(doc(aliceDb(), "orders/o1"), {
        state: "Cancelado",
        total: 0,
      })
    );
  });

  it("owner cannot cancel an already-shipped order", async () => {
    await seed("orders/o1", order({ state: "Enviado" }));
    await assertFails(
      updateDoc(doc(aliceDb(), "orders/o1"), {
        state: "Cancelado",
        cancellationTimestamp: serverTimestamp(),
      })
    );
  });

  it("admin may update freely (catch-all)", async () => {
    await seed("orders/o1", order());
    await assertSucceeds(
      updateDoc(doc(adminDb(), "orders/o1"), { state: "Entregado" })
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────
describe("products (public read, admin write, stock-editor stock-only)", () => {
  const prod = (over = {}) => ({
    name: "Cosa",
    price: 50,
    cost: 30,
    stock: 10,
    ...over,
  });

  it("anyone reads, only admin creates/deletes", async () => {
    await seed("products/p1", prod());
    await assertSucceeds(getDoc(doc(guestDb(), "products/p1")));
    await assertSucceeds(setDoc(doc(adminDb(), "products/p2"), prod()));
    await assertFails(setDoc(doc(aliceDb(), "products/p3"), prod()));
    await assertFails(deleteDoc(doc(stockDb(), "products/p1")));
  });

  it("stock editor may change only stock", async () => {
    await seed("products/p1", prod());
    await assertSucceeds(
      updateDoc(doc(stockDb(), "products/p1"), { stock: 7 })
    );
  });

  it("stock editor cannot change price, or co-edit price+stock", async () => {
    await seed("products/p1", prod());
    await assertFails(updateDoc(doc(stockDb(), "products/p1"), { price: 1 }));
    await assertFails(
      updateDoc(doc(stockDb(), "products/p1"), { stock: 7, price: 1 })
    );
  });

  it("stock editor cannot set negative stock", async () => {
    await seed("products/p1", prod());
    await assertFails(updateDoc(doc(stockDb(), "products/p1"), { stock: -1 }));
  });

  it("non-editor authed user cannot update", async () => {
    await seed("products/p1", prod());
    await assertFails(updateDoc(doc(aliceDb(), "products/p1"), { stock: 7 }));
  });
});

// ─────────────────────────────────────────────────────────────────────────
describe("recipes [#5 read → public]", () => {
  it("guest can read", async () => {
    await seed("recipes/r1", { title: "Pay" });
    await assertSucceeds(getDoc(doc(guestDb(), "recipes/r1")));
  });
  it("only admin writes", async () => {
    await assertSucceeds(setDoc(doc(adminDb(), "recipes/r2"), { title: "X" }));
    await assertFails(setDoc(doc(aliceDb(), "recipes/r3"), { title: "Y" }));
  });
});

// ─────────────────────────────────────────────────────────────────────────
describe("promotions / home_sections / ads (public read, admin write)", () => {
  for (const col of ["promotions", "home_sections", "ads"]) {
    it(`${col}: guest reads, admin writes, client denied`, async () => {
      await seed(`${col}/x1`, { active: true });
      await assertSucceeds(getDoc(doc(guestDb(), `${col}/x1`)));
      await assertSucceeds(setDoc(doc(adminDb(), `${col}/x2`), { active: true }));
      await assertFails(setDoc(doc(aliceDb(), `${col}/x3`), { active: true }));
    });
  }
});

// ─────────────────────────────────────────────────────────────────────────
describe("rewards + rewardsLinkAttempts (admin/CF only)", () => {
  for (const col of ["rewards", "rewardsLinkAttempts"]) {
    it(`${col}: client gets nothing, admin gets all`, async () => {
      await seed(`${col}/w1`, { saldo: 100, pin: "1234" });
      await assertFails(getDoc(doc(aliceDb(), `${col}/w1`)));
      await assertFails(setDoc(doc(aliceDb(), `${col}/w2`), { saldo: 0 }));
      await assertSucceeds(getDoc(doc(adminDb(), `${col}/w1`)));
      await assertSucceeds(setDoc(doc(adminDb(), `${col}/w2`), { saldo: 0 }));
    });
  }
});

// ─────────────────────────────────────────────────────────────────────────
describe("user tree (owner-managed; coupons + workerActions carved out)", () => {
  it("owner reads/writes own root doc; stranger denied", async () => {
    await seed(`users/${ALICE}`, { userInfo: { name: "Alice" } });
    await assertSucceeds(getDoc(doc(aliceDb(), `users/${ALICE}`)));
    await assertSucceeds(
      setDoc(doc(aliceDb(), `users/${ALICE}`), { x: 1 }, { merge: true })
    );
    await assertFails(getDoc(doc(bobDb(), `users/${ALICE}`)));
  });

  it("owner writes generic subcollections (cart, addresses)", async () => {
    await assertSucceeds(
      setDoc(doc(aliceDb(), `users/${ALICE}/cart/item1`), { qty: 1 })
    );
    await assertSucceeds(
      setDoc(doc(aliceDb(), `users/${ALICE}/addresses/a1`), { colonia: "Centro" })
    );
  });

  describe("user coupons (read/delete only — no client create/update)", () => {
    it("owner reads and deletes own coupon", async () => {
      await seed(`users/${ALICE}/coupons/C1`, { used: false, percentage: 10 });
      await assertSucceeds(getDoc(doc(aliceDb(), `users/${ALICE}/coupons/C1`)));
      await assertSucceeds(deleteDoc(doc(aliceDb(), `users/${ALICE}/coupons/C1`)));
    });
    it("owner cannot create or update a coupon (anti-fabrication)", async () => {
      await assertFails(
        setDoc(doc(aliceDb(), `users/${ALICE}/coupons/C2`), {
          used: false,
          percentage: 99,
        })
      );
      await seed(`users/${ALICE}/coupons/C1`, { used: true });
      await assertFails(
        updateDoc(doc(aliceDb(), `users/${ALICE}/coupons/C1`), { used: false })
      );
    });
  });

  describe("workerActions [#2 broad write carved out; constrained create]", () => {
    const valid = {
      type: "clock_in",
      payload: {},
      status: "pending",
      createdAt: serverTimestamp(),
    };
    it("owner enqueues a valid pending action", async () => {
      await assertSucceeds(
        addDoc(collection(aliceDb(), `users/${ALICE}/workerActions`), valid)
      );
    });
    it("rejects unknown type", async () => {
      await assertFails(
        addDoc(collection(aliceDb(), `users/${ALICE}/workerActions`), {
          ...valid,
          type: "give_me_money",
        })
      );
    });
    it("rejects non-pending status", async () => {
      await assertFails(
        addDoc(collection(aliceDb(), `users/${ALICE}/workerActions`), {
          ...valid,
          status: "approved",
        })
      );
    });
    it("rejects missing required keys", async () => {
      await assertFails(
        addDoc(collection(aliceDb(), `users/${ALICE}/workerActions`), {
          type: "clock_in",
        })
      );
    });
    it("owner cannot update/delete an action; admin can", async () => {
      await seed(`users/${ALICE}/workerActions/wa1`, {
        type: "clock_in",
        payload: {},
        status: "pending",
      });
      await assertFails(
        updateDoc(doc(aliceDb(), `users/${ALICE}/workerActions/wa1`), {
          status: "approved",
        })
      );
      await assertSucceeds(
        updateDoc(doc(adminDb(), `users/${ALICE}/workerActions/wa1`), {
          status: "approved",
        })
      );
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────
describe("employee tree [#1 list → admin-only]", () => {
  beforeEach(async () => {
    await seed("employee/e1", { uuid: ALICE, name: "Alice" });
    await seed("employee/e2", { uuid: BOB, name: "Bob" });
  });

  it("admin reads any employee; self reads own; stranger denied", async () => {
    await assertSucceeds(getDoc(doc(adminDb(), "employee/e1")));
    await assertSucceeds(getDoc(doc(aliceDb(), "employee/e1")));
    await assertFails(getDoc(doc(bobDb(), "employee/e1")));
  });

  it("admin may list the whole collection", async () => {
    await assertSucceeds(getDocs(collection(adminDb(), "employee")));
  });

  it("non-admin cannot list the whole collection", async () => {
    await assertFails(getDocs(collection(aliceDb(), "employee")));
  });

  it("self-lookup query (where uuid == me) is allowed", async () => {
    await assertSucceeds(
      getDocs(
        query(collection(aliceDb(), "employee"), where("uuid", "==", ALICE))
      )
    );
  });

  it("query for someone else's employee doc is denied", async () => {
    await assertFails(
      getDocs(
        query(collection(aliceDb(), "employee"), where("uuid", "==", BOB))
      )
    );
  });

  it("employee write is admin-only", async () => {
    await assertFails(
      setDoc(doc(aliceDb(), "employee/e1"), { name: "x" }, { merge: true })
    );
    await assertSucceeds(
      setDoc(doc(adminDb(), "employee/e1"), { name: "x" }, { merge: true })
    );
  });
});

// ─────────────────────────────────────────────────────────────────────────
describe("stock_corrections + inventory_logs (stock-editor append)", () => {
  it("stock_corrections: editor appends with own uid; foreign uid denied", async () => {
    await assertSucceeds(
      setDoc(doc(stockDb(), "stock_corrections/sc1"), { uid: STOCK, delta: -2 })
    );
    await assertFails(
      setDoc(doc(stockDb(), "stock_corrections/sc2"), { uid: "someone", delta: -2 })
    );
    await assertFails(getDoc(doc(aliceDb(), "stock_corrections/sc1")));
  });

  it("stock_corrections: no edits/deletes once written (except admin)", async () => {
    await seed("stock_corrections/sc1", { uid: STOCK, delta: -2 });
    await assertFails(
      updateDoc(doc(stockDb(), "stock_corrections/sc1"), { delta: -5 })
    );
    await assertSucceeds(
      updateDoc(doc(adminDb(), "stock_corrections/sc1"), { delta: -5 })
    );
  });

  it("inventory_logs: editor reads + creates, cannot edit", async () => {
    await assertSucceeds(
      setDoc(doc(stockDb(), "inventory_logs/il1"), { qty: 10 })
    );
    await assertSucceeds(getDoc(doc(stockDb(), "inventory_logs/il1")));
    await assertFails(updateDoc(doc(stockDb(), "inventory_logs/il1"), { qty: 1 }));
    await assertFails(getDoc(doc(aliceDb(), "inventory_logs/il1")));
  });
});

// ─────────────────────────────────────────────────────────────────────────
describe("store config / settings / categories", () => {
  it("store/config: admin+editor read, admin-only write", async () => {
    await seed("store/config", { pricing: {} });
    await assertSucceeds(getDoc(doc(adminDb(), "store/config")));
    await assertSucceeds(getDoc(doc(stockDb(), "store/config")));
    await assertFails(getDoc(doc(aliceDb(), "store/config")));
    await assertSucceeds(setDoc(doc(adminDb(), "store/config"), { a: 1 }, { merge: true }));
    await assertFails(setDoc(doc(stockDb(), "store/config"), { a: 1 }, { merge: true }));
  });

  it("store/permissions + store/specifics: any authed user reads, guest denied", async () => {
    await seed("store/permissions", { roles: [] });
    await seed("store/specifics", { brands: [] });
    await assertSucceeds(getDoc(doc(aliceDb(), "store/permissions")));
    await assertSucceeds(getDoc(doc(aliceDb(), "store/specifics")));
    await assertFails(getDoc(doc(guestDb(), "store/permissions")));
  });

  it("settings/{doc}: authed read, admin write", async () => {
    await seed("settings/store", { pricing: { Centro: 15 } });
    await assertSucceeds(getDoc(doc(aliceDb(), "settings/store")));
    await assertFails(getDoc(doc(guestDb(), "settings/store")));
    await assertSucceeds(setDoc(doc(adminDb(), "settings/store"), { x: 1 }, { merge: true }));
    await assertFails(setDoc(doc(aliceDb(), "settings/store"), { x: 1 }, { merge: true }));
  });

  // NOTE: `match /private/categories/{docId}` in the ruleset is an odd-segment
  // path (private/categories/{docId} = 3 segments) that can never match a real
  // document, so there is nothing valid to assert against. Left untested on
  // purpose — see the pre-existing-rule note in the test README.
});

// ─────────────────────────────────────────────────────────────────────────
describe("coupon_broadcasts + catch-all (admin-only)", () => {
  it("coupon_broadcasts: admin only", async () => {
    await seed("coupon_broadcasts/b1", { sent: false });
    await assertFails(getDoc(doc(aliceDb(), "coupon_broadcasts/b1")));
    await assertSucceeds(getDoc(doc(adminDb(), "coupon_broadcasts/b1")));
    await assertSucceeds(setDoc(doc(adminDb(), "coupon_broadcasts/b2"), { sent: false }));
  });

  it("unmatched paths: admin full access, everyone else denied", async () => {
    await seed("random_collection/z1", { foo: "bar" });
    await assertSucceeds(getDoc(doc(adminDb(), "random_collection/z1")));
    await assertSucceeds(setDoc(doc(adminDb(), "random_collection/z2"), { foo: 1 }));
    await assertFails(getDoc(doc(aliceDb(), "random_collection/z1")));
    await assertFails(getDoc(doc(guestDb(), "random_collection/z1")));
  });
});
