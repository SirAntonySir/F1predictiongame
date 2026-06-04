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
| `refunded_at` | timestamptz null | Set by the refund-notification handler (see below). Once set, the entitlement no longer counts when the backend re-derives `league.max_seats` from the purchase log. |

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

## Refund handling (store-initiated)

Apple and Google both refund without asking us. They notify our server
asynchronously; we must revoke the entitlement and mark the row
refunded. Without this the user keeps the seat upgrade after getting
their money back — bad faith on our side and an audit risk.

### `POST /api/purchases/webhook/apple`

Receives **App Store Server Notifications v2** (`REFUND` /
`REFUND_REVERSED` / `REFUND_DECLINED` notification types). The body is
a JWS-signed payload from Apple.

Flow:

1. Verify the JWS signature against Apple's published certificate
   chain. Reject if invalid. Use the official
   [`app-store-server-library`](https://github.com/apple/app-store-server-library-node)
   helper rather than rolling our own JWS parser.
2. Decode the inner transaction payload, pull the
   `originalTransactionId`.
3. Look up the matching `purchase` row by `(store='apple',
   store_transaction_id=originalTransactionId)`. If missing, log + 200
   (Apple retries hard; we mustn't 500 on a notification we don't
   recognise).
4. On `REFUND`: set `refunded_at = now()`, then recompute and write
   `league.max_seats` (see "Recomputing seat caps" below). For tips:
   just set `refunded_at`, no entitlement change.
5. On `REFUND_REVERSED` (refund was reversed back to charged): clear
   `refunded_at`, recompute seats again.
6. Always return `200 OK` so Apple stops retrying.

### `POST /api/purchases/webhook/google`

Receives **Real-time Developer Notifications** from Google via Pub/Sub
push subscription. Body shape differs — wraps a base64-encoded
`subscriptionNotification` / `oneTimeProductNotification`.

Flow:

1. Verify the request is from Google Cloud Pub/Sub (the push
   subscription includes an OIDC token in the `Authorization` header
   we can verify against Google's JWKS).
2. Decode the inner notification, pull `purchaseToken`.
3. Look up `purchase` by `(store='google',
   store_transaction_id=purchaseToken)`.
4. On `notificationType=VOIDED_PURCHASE` (revoked / refunded): same
   handling as Apple's `REFUND`.
5. Return `204 No Content` so Pub/Sub acks the message.

### Recomputing seat caps

A league's `max_seats` is **the maximum of all non-refunded purchases'
seat values** that point at it, floored at 3 (Free tier).

```
maxSeats(league) = max(
  3,                                  -- Free baseline
  max(productSeats(p)                 -- highest tier still active
      for p in league.purchases
      where p.refunded_at is null)
)
```

This single derivation handles every edge case: refund of the only
upgrade drops the cap back to 3; refund of an older tier when a newer
one is still active leaves the cap on the newer one; a downstream
`REFUND_REVERSED` restores it. Implemented as a function on the
purchase repo, called from both `POST /api/purchases/validate` and the
two webhook handlers.

### Operational notes

- Both webhooks need to be **idempotent**. Apple and Google both retry,
  sometimes deliver out of order, sometimes deliver the same
  notification twice.
- Configure the webhook URLs on the respective consoles
  (App Store Connect → App → App Information → App Store Server
  Notifications V2; Play Console → Monetization Setup → Real-time
  developer notifications). URLs land in env vars on Render so they
  can be rotated without a code change.

## Account deletion

Apple **requires** in-app account deletion for every app that supports
account creation (App Store Review Guideline 5.1.1(v), enforced since
mid-2022). Submitting the paid version without this guarantees
rejection. Google doesn't formally require it but already mandates a
**publicly accessible account-deletion URL** disclosed in the Play
Console listing, which we'll point at the same backend endpoint.

### `DELETE /api/users/me`

Authenticated. Hard-deletes the caller's user record, which cascades
to:

- All their predictions + picks
- All their preseason picks + standings
- All their score rows (session + preseason)
- All their projection snapshots
- League memberships
- Sessions (auth tokens)
- Purchase history — see "Purchase retention" below

For leagues the caller **owns**: the existing `league.ownerUserId →
user.id` FK uses `ON DELETE CASCADE`, so the league itself goes too,
which in turn cascades to every other member's data tied to that
league. That's the desired behaviour — an owner deleting their account
takes the league with them, and members are surfaced an empty
home-screen state with the existing onboarding flow on their next
launch.

### Purchase retention (legal requirement)

We **cannot delete** `purchase` rows when a user deletes their account.
German tax law (AO §147) requires us to retain payment records for
**10 years**. The compromise:

1. On `DELETE /api/users/me`, set `purchase.user_id` to a sentinel
   "deleted user" row (`00000000-0000-0000-0000-000000000000`) so the
   FK survives without revealing identity.
2. Null out the `store_receipt` blob (it contains PII like the user's
   App Store ID).
3. Keep `store`, `product_id`, `store_transaction_id`, `amount_*`,
   `validated_at`, `refunded_at` — the financial trail.
4. Document this exception clearly in the Privacy Policy.

### UI

New row in `Settings → ACCOUNT`, below "Change password":

> **Delete account**
> Removes your profile, picks, scores, and any leagues you own.
> *Required to keep payment records for 10 years (German tax law).
> Everything else is wiped.*

Tapping it opens a confirmation dialog with two stages:

1. **First stage**: "This deletes your account permanently. Continue?"
   with Cancel / Continue.
2. **Second stage**: free-text "Type DELETE to confirm" + final red
   Delete button. Guards against accidental taps and meets the
   "informed action" bar Apple looks for in review.

On success, the client clears its local auth, drops cached state,
routes to `/login` with a `?deleted=1` flag that surfaces a one-time
snackbar: "Account deleted. Sorry to see you go."

### Edge case: caller owns a league with paid upgrades

The account deletion still proceeds and cascades the league away.
Other members lose access to that league's predictions but keep their
own user account. The owner's purchases are anonymised per the
retention rules above; no refund is automatically issued (the user
chose to delete, not request a refund).

The confirmation dialog's second-stage text gets an extra line when
this applies:

> **Heads up:** You own *<League name>*. Deleting your account also
> deletes the league for everyone in it (N members). Any seat
> upgrades you bought for this league cannot be transferred.

## Testing

- Backend unit tests for:
  - Receipt-verification helper (mocked Apple/Google responses).
  - `recomputeMaxSeats(leagueId)` covering: no purchases → 3; one
    active upgrade → its tier; refund of only upgrade → 3; refund of
    older when a newer is active → still newer; reversal restores.
  - Webhook signature verification (Apple JWS, Google OIDC).
- Backend integration tests for:
  - `POST /api/purchases/validate` — happy path, idempotent re-submit,
    non-owner-for-seat-purchase, wrong-receipt rejection, full-league
    join refusal.
  - `POST /api/purchases/webhook/apple` — REFUND drops the cap,
    REFUND_REVERSED restores it, unknown transaction returns 200.
  - `POST /api/purchases/webhook/google` — VOIDED_PURCHASE drops the
    cap, OIDC failure returns 401, unknown token returns 204.
  - `DELETE /api/users/me` — cascades data, anonymises purchase rows
    (user_id sentinel, receipt nulled), 200s on the auth `/me` after
    deletion → 401.
- Flutter widget tests for the seat-tier picker, the tip jar, and the
  two-stage account-deletion confirmation.
- Manual: sandbox accounts on both stores walk through Mate / Crew /
  Paddock + each tip + Restore + a sandbox refund (Apple's TestFlight
  has a refund-request flow built in; Google requires the Play
  Console).

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
