# Firestore security-rules tests

Emulator-backed tests for `../firestore.rules` — the ruleset shared
byte-for-byte by the client app (`click-main`) and the admin app
(`t_sty_delivery`). 46 assertions covering every collection, including the five
hardening changes tagged `[#1]`–`[#5]` in `test/rules.test.js`:

- `[#1]` employee collection `list` → admin-only (self-lookup still works)
- `[#2]` `workerActions` carved out of the broad user-tree write
- `[#3]` master `coupons` read → admin-only
- `[#4]` `orders` client read-only + cancel-only update
- `[#5]` `recipes` read → public

## Run

```bash
# one-time
npm --prefix firestore-tests install        # needs Node + Java (JRE) on PATH

# run the suite against the Firestore emulator
npm --prefix firestore-tests run test:emulator
```

`test:emulator` boots the Firestore emulator (config in `../firebase.json`),
runs mocha against it, and tears it down. Java is required because the
Firestore emulator runs on the JVM.

> The plain `npm test` script runs mocha directly and assumes an emulator is
> already listening on `127.0.0.1:8080`. Use `test:emulator` for one-shot runs.
> (Do **not** wrap `npm test` inside `firebase emulators:exec` — nested `npm`
> trips a `Cannot read properties of undefined (reading 'stdin')` bug, which is
> why `test:emulator` invokes the mocha binary directly.)

## Notes

- These tests run on a copy of `firestore.rules` from this repo. Since both
  repos keep that file identical, testing it here covers both apps.
- `match /private/categories/{docId}` is a pre-existing odd-segment path that
  can never match a real document, so it is intentionally untested. Worth
  cleaning up in the ruleset.
