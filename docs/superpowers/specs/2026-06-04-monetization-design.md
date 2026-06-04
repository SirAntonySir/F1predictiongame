# Monetization design

## Goal

Cover the app's hosting costs and reward the developer's time without
extracting more than the friend-group context calls for. Paid mechanics
must comply with Apple App Store and Google Play in-app-purchase rules,
since the app ships to both stores.

## Constraints

- **IAP-only for in-app payments.** Both stores require their billing
  systems for digital goods. Stripe / PayPal / web checkout linked from
  inside the app is grounds for rejection.
- **Fixed predefined SKUs only.** "Pay-what-you-want" sliders and
  arbitrary donations are not allowed via IAP.
- **30% / 15% commission.** Standard 30% applies unless enrolled in
  Apple's Small Business Program or Google's first-$1M program, both of
  which drop the cut to 15%. We qualify (revenue ≪ $1M).
- **Receipts must be server-validated** so entitlements survive
  reinstalls and device changes.
- **Restore Purchases UI is mandatory** on Apple.

## Pricing

Whole-number EUR price points (Apple supports custom pricing since late
2022, so no need to default to .99 endings).

### Per-league seat tiers (one-time IAP, scoped to a single league)

| Tier | Price | Seats unlocked |
|---|---|---|
| Free | – | 3 |
| Mate | €3 | 10 |
| Crew | €7 | 25 |
| Paddock | €15 | unlimited |

Rules:

- Purchase is **per-league**, applied to the league that was active when
  the buyer initiated the upgrade.
- Tiers **stack up, not down**. Buying Crew after Mate sets the league's
  cap to 25; the Mate purchase is not refunded (App Store policy and
  also matches the user expectation that they paid to grow).
- A second league created by the same user starts on Free again.
- Only the league **owner** can purchase upgrades. Members never see the
  paywall flow.

### Tip jar (Settings → Support the developer)

Four one-tap SKUs, also one-time consumable IAPs.

| Amount |
|---|
| €1 |
| €3 |
| €5 |
| €10 |

No in-app perk attached to tipping in this iteration. Server records
each tip transaction for future use (lifetime tip total, "thanks" email,
etc.) but no UI reward is wired up.

## What happens when a league is full

Existing `POST /api/leagues/join` flow already validates membership.
Add a seat-cap check ahead of `members.add`:

1. Compare `members.count` against `league.maxSeats`.
2. If the league is at or above the cap, throw `FORBIDDEN` with the
   message `League is full — ask the owner to upgrade.`
3. Owner sees an "Upgrade seats" CTA in `Settings → League` whenever
   `members.count >= maxSeats - 1`. The CTA opens the seat-tier
   purchase sheet.

## Schema changes

### `league.max_seats integer NOT NULL DEFAULT 3`

Backfilled to 3 for every existing league (matches the Free tier they
were implicitly on). Future upgrade purchases bump this value.

### `purchase` table (new)

Records every successful IAP. The source of truth for entitlements;
joins to `league` (for seat upgrades) or stands alone (for tips).

| column | type | notes |
|---|---|---|
| `id` | uuid pk | |
| `user_id` | uuid not null fk → user.id | The buyer. |
| `product_id` | text not null | `seats_10`, `seats_25`, `seats_unlimited`, `tip_1`, `tip_3`, `tip_5`, `tip_10` |
| `store` | text not null | `'apple'` or `'google'` |
| `store_transaction_id` | text not null | Apple `originalTransactionId` / Google `purchaseToken` — used for idempotency. |
| `store_receipt` | text not null | Raw receipt body for re-verification + audit. |
| `validated_at` | timestamptz not null default now() | When the backend confirmed the receipt with Apple/Google. |
| `league_id` | uuid null fk → league.id | Set for seat-tier upgrades; null for tips. |
| `amount_minor_units` | integer not null | Price the user paid in the store's smallest currency unit (cents for EUR/USD, pence for GBP, etc.). Pulled from the receipt so price changes never rewrite history. |
| `currency_code` | text not null | ISO 4217, e.g. `EUR`, `USD`, `GBP`. |

Unique index on `(store, store_transaction_id)` to make `POST
/api/purchases/validate` idempotent — a duplicate submission is a no-op.

## API

### `POST /api/purchases/validate`

Body:

```json
{
  "store": "apple",
  "productId": "seats_25",
  "receipt": "<base64 receipt or JWS>",
  "leagueId": "<uuid, only for seat-tier products>"
}
```

Flow:

1. Authenticate caller normally.
2. Validate the receipt against Apple's or Google's verification API.
   - Apple: App Store Server API `/inApps/v1/transactions/{id}` (or the
     legacy `/verifyReceipt` endpoint as fallback).
   - Google: `androidpublisher.purchases.products.get`.
3. Confirm the `productId` returned by the store matches the request.
4. Idempotency: look up `(store, store_transaction_id)` in `purchase`.
   If present, return its current state without re-applying.
5. Insert the `purchase` row.
6. Apply the entitlement:
   - For seat-tier products: require `leagueId`, require the caller is
     the league owner, then `league.max_seats = max(current, productSeats)`
     where `productSeats` is the mapping `seats_10 → 10`, `seats_25 →
     25`, `seats_unlimited → 999_999` (sentinel — anything well above
     plausible league size).
   - For tips: no entitlement; just the row.
7. Return `{ ok: true, entitlement: { ... } }` where `entitlement`
   echoes the new `maxSeats` for seat purchases, `{}` for tips.

Errors:

- `BAD_REQUEST` — unknown productId, missing fields.
- `FORBIDDEN` — caller is not the league owner for a seat purchase.
- `VALIDATION` — receipt failed Apple/Google verification.
- `CONFLICT` — `leagueId` provided but already at a higher tier (rare;
  the idempotency check usually catches this first).

### `GET /api/purchases/mine`

Returns the caller's tip + seat-purchase history (for the Settings
"Restore Purchases" UI and an optional "Your contributions" view).

## App-side flow

### Product setup (App Store Connect + Google Play Console)

Three non-consumable seat-tier products + four consumable tip products
(seven SKUs total):

| productId | type | price |
|---|---|---|
| `seats_10` | non-consumable | €3 |
| `seats_25` | non-consumable | €7 |
| `seats_unlimited` | non-consumable | €15 |
| `tip_1` | consumable | €1 |
| `tip_3` | consumable | €3 |
| `tip_5` | consumable | €5 |
| `tip_10` | consumable | €10 |

Seat products are **non-consumable** — owning `seats_25` is permanent
for the buyer's account and surfaces in Restore Purchases. Tips are
consumable so the user can tip again.

### Flutter integration

Single plugin: [`in_app_purchase`](https://pub.dev/packages/in_app_purchase)
(official Flutter team plugin, no third-party dependency).

New screen: `lib/screens/seat_upgrade_screen.dart`. Three rows showing
Mate / Crew / Paddock with prices fetched from the store (not hard-coded
on the client so we can change pricing without an app update). Tapping
a row kicks off the IAP flow → on completion, ships the receipt to
`POST /api/purchases/validate` → on 200, pops the screen and refreshes
the league state.

Tip jar: a section in the existing `Settings` screen with four small
buttons in a row showing the prices.

Restore Purchases: a button at the bottom of Settings that calls
`InAppPurchase.instance.restorePurchases()`, then forwards any
returned transactions through `POST /api/purchases/validate`.

### Where the CTA shows up

- **Onboarding "Create your own"** card: a passive "Free up to 3
  members — upgrade later for larger leagues" caption below the
  Create button. No purchase pressure at create time.
- **Settings → League** (owner only): "Upgrade seats" button always
  visible if the league isn't on `seats_unlimited`. Shows the current
  cap and the next-tier price.
- **Join failure** on a full league: the joiner sees "League is full —
  ask the owner to upgrade." The owner, on next opening Settings, sees
  a one-off banner "Your league is at capacity. Upgrade to grow it."

## Testing

- Backend: unit tests for the receipt-verification helper (mocked
  Apple/Google responses), integration tests for `POST /purchases/validate`
  covering happy path, idempotency, non-owner-for-seat-purchase, and
  full-league join refusal.
- Flutter: widget tests for the seat-tier picker and the tip jar.
- Manual: sandbox accounts on both stores walk through Mate / Crew /
  Paddock + each tip + Restore.

## Economics, expected break-even

| Sale | Gross | After 15% SMB cut | After ~20% VAT | Net to you |
|---|---|---|---|---|
| Tip €1 | €1 | €0.85 | – | ~€0.68 |
| Mate €3 | €3 | €2.55 | – | ~€2.04 |
| Crew €7 | €7 | €5.95 | – | ~€4.76 |
| Paddock €15 | €15 | €12.75 | – | ~€10.20 |

Annual recurring infra cost: ~€155/yr Render + €91/yr Apple Developer
= **€246/yr**. One Crew purchase covers a year of infra at any scale
past ~50 active leagues.

## Out of scope (deliberately)

- **Subscriptions** — explored, rejected. Friend-group context doesn't
  fit a recurring bill; one-time tiered upgrades match the mental model
  better.
- **Per-member fees** — explored, rejected. Killing 90% of joiners to
  squeeze €1 out of each is not the goal.
- **Cosmetic IAP (themes, helmets, etc.)** — deferred; revisit only if
  seat-tier + tip jar prove insufficient.
- **Web-checkout fallback / EU DMA external links** — deferred. Net
  €4.76 on a €7 Crew sale is fine for now; the operational complexity
  of running a parallel web checkout isn't.
- **Supporter perk (name colour / star)** — explicitly declined for v1.
  Tip jar ships unrewarded; perks can be added later without schema
  change (just a `is_supporter` derivation off the `purchase` table).
- **Donation flow to a charity** — would require non-profit registration
  on Apple's side; ignore unless someone wants to do the paperwork.

## Decisions noted

- **League deletion forfeits upgrades.** If an owner deletes their
  league, the `seats_25` (or whichever) entitlement does not migrate to
  a future league they create. The `purchase` row is preserved for
  audit, but a new league always starts on Free. Documented in the UI
  so owners know before they delete.
- **Restore Purchases re-applies seat upgrades** only when the user can
  point them at a league they own. If they don't currently own a
  league, the restore call records the purchase as inactive and the
  next league they create can claim it once (one-time grace flow,
  guarded by `purchase.league_id IS NULL` at restore time).

## Open questions

One item to confirm during implementation:

1. **Receipt verification approach.** Apple deprecated `verifyReceipt`
   in favour of App Store Server API + JWS-signed transactions. Decide
   whether to call the new API directly (more work, future-proof) or
   ship the legacy endpoint first (works fine for years to come, less
   integration code).
