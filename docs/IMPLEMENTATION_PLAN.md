# B-easy — Grand implementation plan

> **Status:** Proposal / not started  
> **Date:** 19 Aug 2026  
> **Sources:** architecture review, voice/vision correction, per-shop product recognition, GST + bill OCR canvases  

This plan **replaces** the earlier draft that recommended dropping Whisper for Apple Speech. Voice uses the later decision: **keep Whisper for Hinglish**.

---

## How to read this

Phases are ordered so each one makes the next safer. Do not skip 0–2 to polish camera.

| Label | Meaning |
| --- | --- |
| **P0** | Can lose money, corrupt data, or create GST exposure. Ship-blocking. |
| **P1** | Materially wrong output or a scaling wall. |
| **P2** | Real improvement, not urgent. |

Every item: **Why** / **Where** / **Do** / **Done when**.

---

## Locked product decisions

- Keep **UIKit + local SQLite**. No SwiftUI/Core Data rewrite. No cloud replica of the books until phases 1–2 pass.
- **Voice:** Apple `SFSpeechRecognizer(en-IN)` is live captions + fallback when Whisper returns nil. **Whisper small + romanized kirana prompt** is the Hinglish ASR. Do **not** prefer Apple on recordings under 5s.
- **Products:** Teachable Machine per shop (video enroll → CLIP gallery). Not a world SKU model. Checkout is **per-box instance matching** into a **draft bill**.
- **Tax:** Integer paise, discount **before** GST, never guess intra-state. GSTR JSON is not filing-ready until identity tests pass.
- **Capture:** Voice, bill OCR, and product scan are **drafts**. Never silent-post to the ledger.

---

## Snapshot

| Metric | Value |
| --- | --- |
| Swift | ~33k lines, ~140 files, **0** test targets |
| DB transactions | **1** (`clearAllPersistedData` only) |
| Money | `Double` everywhere |
| Cloud | Auth + `user_profiles` only |
| Voice bundle | Whisper ~350 MB — **keep**; fix arbitration so it is actually used |

---

# Phase 0 — Make it measurable · P0/P1

### 0.1 Test target + in-memory DB · P0

**Why** — Refactoring money/FIFO with no tests replaces one class of bugs with another.

**Where** — `B-easy.xcodeproj`; `SQLiteDatabase.init()` hardcodes `Documents/ledgile.sqlite`.

**Do** — Construct DB at an arbitrary path / `:memory:`. Cover: FIFO decrement; crash mid-sale writes nothing; unique invoices; `total == taxable + cgst + sgst + igst + cess`; discounted sale **fails** that identity on today’s code.

**Done when** — `xcodebuild test` is green except the known discount identity failure (harness detects the real bug).

### 0.2 Correction telemetry · P1

**Why** — Best accuracy signal is how often the user edits AI output.

**Do** — Log locally: accepted / edited / deleted per field. Strip Release `print()` of transcripts, Gemini JSON, prices.

**Done when** — Debug screen shows silent-correction rate; Release has no spoken/bill PII in the console.

---

# Phase 1 — Ledger integrity · all P0 unless noted

### 1.1 One commit per sale/purchase · P0

**Why** — `addMultiItemSale` is ~15–20 autocommit statements. Crash can record a sale without stock decrement or reuse an invoice number. `reconcileAllStock()` on launch is a symptom.

**Where** — `DataModel.swift` (`addMultiItemSale`, `addPurchase`, `recordSaleWithoutStockCheck`); `SQLiteDatabase.swift:1404`.

**Do** — `func write<T>(_ body: (Tx) throws -> T) throws -> T` with `BEGIN IMMEDIATE`. Allocate invoice number **inside** the same transaction.

**Done when** — Injected throw mid-sale leaves the DB unchanged.

### 1.2 Writes throw · P0

**Why** — `guard let stmt = prepare else { return }` + unchecked `sqlite3_step` looks like success.

**Where** — `SQLiteDatabase` write helpers (`updateBatch`, `insertTransactionItems`, `insertSaleItemBatches`, payments).

**Do** — `DBError.prepareFailed` / `stepFailed`. Check `SQLITE_DONE`.

**Done when** — Forced write failure rolls back and surfaces to UI.

### 1.3 Atomic stock decrement · P0

**Why** — FIFO reads qty, subtracts in Swift, `SET quantity_remaining=?`. Two sales can drop a decrement.

**Do** — `UPDATE … SET quantity_remaining = quantity_remaining - ? WHERE id = ? AND quantity_remaining >= ?` + `sqlite3_changes()`.

**Done when** — Concurrent sales leave exact stock; no silent negatives.

### 1.4 Constraints · P0

**Why** — `PRAGMA foreign_keys=ON` but DDL has no `REFERENCES`. `invoice_number` is not UNIQUE. `deleteItem` orphans rows.

**Do** — `UNIQUE(invoice_number)`; real FKs; soft-delete financial rows. One schema rebuild (pair with phase 2 money types if possible).

**Done when** — Duplicate invoice rejected; item delete cannot destroy sale history.

### 1.5 Dates and credit · P1

**Why** — `readDate` ends in `?? Date()` (historical sales jump to today). Udhaar has no `transaction_id`.

**Do** — `Date?` / throw. `customer_payments.transaction_id`; void reverses credit in the same write.

**Done when** — Bad dates are not today’s revenue; every credit traces to an invoice.

---

# Phase 2 — GST / money · P0/P1

### 2.1 Paise + tax after discount · P0

**Why** — `grandTotal = revenue − discount + adjustment` but taxable/CGST/SGST/IGST are pre-discount. `round2` on every component; CGST/SGST halved before round. `addMultiItemSale` bypasses `generateBreakup`. GSTR copies stored numbers.

**Where** — `DataModel.swift ~856–940`; `GSTEngine.swift`; `GSTReturnExporter.swift`.

**Do** — `Int64` paise. Apportion discount onto lines **then** tax. One rounding pass; residual paisa on largest line. Adjustment is non-taxable. Both sale paths use `GSTEngine.generateBreakup`.

**Done when** — 10k random invoices satisfy `total == taxable + tax`; phase 0 discount test passes.

### 2.2 Place of supply · P0

**Why** — `isInterStateSupply` returns `false` when state is unknown. Sale copies shop state onto the buyer.

**Do** — Block or ask. GSTIN first two digits drive POS. Never default intra-state.

**Done when** — B2B without POS cannot save; inter-state books IGST.

### 2.3 Purchase ITC + GSTR-3B · P1

**Why** — Purchases use shop `pricesIncludeGST` on supplier cost. All ITC exported as `ty: IMPG`. GSTIN regex forces 14th char `Z`, no check digit. Nil `gstRate` lines skip tax but stay in `totalAmount`. PDF `round()`s grand total independently of DB.

**Do** — Exclusive or printed supplier breakup. Valid GSTIN check digit. Unrated inclusive items must prompt. 3B: not IMPG for domestic. One rounding rule for PDF/DB/JSON.

**Done when** — Domestic ITC is not IMPG; printed total equals `transactions.total_amount`.

---

# Phase 3 — Voice (corrected) · P0/P1

### 3.1 Keep Whisper; fix arbitration · P0

**Why** — Apple en-IN is weak on Hinglish; that is why Whisper exists. Current rule prefers Apple if `recordingDuration < 5` and SFSpeech has text — most kirana lines are short Hinglish, so they go to the worse engine. Whisper already skips silence (RMS / peak / under 0.3s) and filters “thanks for watching” hallucinations.

**Where** — `VoiceEntryViewController` / `VoicePurchaseEntryViewController` (~287–300); `WhisperService.makeWhisperParams` (`language = .english` + romanized prompt is intentional).

**Do** — Default to Whisper. Apple only if Whisper is nil. Keep garbage + silence guards. Do **not** delete the 350 MB model. Do **not** switch to SpeechAnalyzer as primary.

**Done when** — A 2s utterance “aadha kilo aloo” is Whisper, not Apple.

### 3.2 Auto-stop on silence · P1

**Why** — `silenceTimer` / `maxSilenceDuration = 2` are unused on sale; purchase `startSilenceTimer` only invalidates. Trailing hush feeds Whisper hallucinations.

**Do** — Schedule the 2s timer on both VCs. Then consider dropping `single_segment` for long multi-item dictation only.

**Done when** — Mic stops after 2s quiet; empty room does not emit captions spam.

### 3.3 Draft parse + MiniLM at launch · P1

**Why** — `GeminiService.parseSaleJSON` replaces spoken name with inventory name; confirm UI never fires (`matchConfidence` becomes 1.0). `indexInventory` is async; first `match()` skips semantic rerank.

**Do** — Carry `originalName` + confidence. Confirm when under 0.90 even if Gemini is on. Index MiniLM at launch / on catalog change.

**Done when** — Fuzzy match shows “Is this X?” while logged in.

---

# Phase 4 — Bill / document OCR · P0/P1

### 4.1 Rate vs amount + printed total · P0

**Why** — `BillParser.parseForSale` uses `rate ?? amount` (line total as unit price). `grandTotal` is extracted then discarded. No `qty×rate == amount` check.

**Where** — `BillParser.swift` ~84–87, ~173–241, `extractTotal`.

**Do** — If amount and no rate: `rate = amount/qty`. Flag mismatches. Require printed total vs sum within tolerance before save.

**Done when** — Amount-only bills do not 3× overcharge; mismatched total cannot auto-save.

### 4.2 Always review; fill purchase header · P1

**Why** — Gemini 768px JPEG is first pass (keep; tile later if handwriting fails). Purchase parse leaves supplier GSTIN / invoice nil. Same name-swap bug as voice.

**Do** — Gemini → on-device fallback → **edit table**. Never auto-post. Copy GSTIN/invoice when OCR/Gemini sees them.

**Done when** — Every scan opens entry with flagged rows.

---

# Phase 5 — Per-shop product recognition · P0/P1

### 5.1 Instance pipeline · P0

**Why** — Enrollment is one-SKU-many-views (correct Teachable Machine). Checkout still matches like one scene: 70% center-crop fallback, `maxDetections = 5` unused, qty always 1, OCR on **full frame**. A photo of 10 packs becomes nearest-neighbor clutter.

**Where** — `ProductFingerprintManager.matchWithCLIP` fallback crop; `SalesScanCameraViewController` live product scan / `handleProductDetected` / `processOCRLabels`.

**Do** — Detect N packet boxes. Per crop: barcode then CLIP. No full-scene embed. Duplicates → qty++. Cap detections.

**Done when** — Four enrolled packs in one photo draft four lines (or 3 + abstain), not one wrong SKU.

### 5.2 Abstain + draft bill · P0

**Why** — `isReliableMatch` accepts a solo candidate. OCR can confirm from one 3-letter word or price ±₹2.

**Do** — Require margin or solo bar ~0.85. Close top-2 → picker. OCR only as **crop** tie-break. Overlay + review bill. Never silent auto-sale.

**Done when** — Empty counter adds nothing; 20g vs 52g prompts.

### 5.3 Enroll quality + barcode · P1

**Why** — Failed quality filter falls back to 15 blurry 480px JPEGs. Barcode on pack unused unless saved on the item.

**Do** — Product-only crops. Reject under 8 sharp frames. Save barcode from enroll video. Keep farthest-point `selectDiverse`.

**Done when** — Weak videos are rejected; packed goods with a stored code sell by barcode.

---

# Phase 6 — Auth / UX · P1/P2

### 6.1 Complete profile for all incomplete sessions · P1

**Why** — Apple does not send shop/phone. Complete Profile exists; phone OTP sign-in can still enter as “User” / “My Shop”. Phones forced to 10 digits; shop names cannot include digits. OTP success alert. Profile edited via alerts. Face ID key unused. `updateUserProfile` fire-and-forget; `fetchUserProfile` off main unless wrapped.

**Do** — Same gate for any logged-in incomplete profile. Country-aware phone. Digits in shop names. Skip OTP alert. One form for profile. Hide Face ID until it locks. Surface profile sync errors.

**Done when** — Cannot reach tabs without name + shop + phone.

### 6.2 Hygiene · P2

**Do** — Enforce or delete `UsageTracker.canUseGemini`. Search tab in storyboard. Stop committing live `Secrets.xcconfig`.

---

# Phase 7 — Scale (after books are correct)

### 7.1 DB off main thread · P0

**Why** — Checkout blocks the run loop. `BackupService.restore` can `sqlite3_close` mid-`step`.

**Do** — `LedgerStore` actor / serial queue. Async checkout spinner. Restore serialized with writes. Drop launch `reconcileAllStock` once 1.1 holds.

**Done when** — Debug assert: no sqlite on main; restore-during-sale does not crash.

### 7.2 O(cart) writes · P1

**Why** — `updateSalesCountAndTiers` UPDATEs every catalog item per sale. Credit N+1.

**Do** — Touch sold items only. One `GROUP BY` for balances.

### 7.3 Sync last · P2

**Why** — Replicating a non-transactional ledger copies corruption.

**Do** — Outbox of transactions/items only after 1–2 pass.

**Done when** — New phone restores books without a file; conflict rules written down.

---

## Suggested build slices (sprints)

| Sprint | Ship |
| --- | --- |
| A | 0.1 tests + 1.1–1.3 transactions/throws/stock |
| B | 2.1–2.2 money + POS |
| C | 3.1–3.2 Whisper arbitration + silence |
| D | 4.1 bill total/rate + 5.1–5.2 multi-box draft bill |
| E | 5.3 enroll barcode, 6.1 auth, 7.1 off-main-thread |
| F | 2.3 GSTR buckets, 7.2 perf, 7.3 sync design |

---

## Explicitly not doing (for now)

- Replacing Whisper with Apple SpeechAnalyzer as primary ASR.
- Training a global product classifier.
- Auto-filing GSTR or e-invoice/IRN.
- SwiftUI rewrite, Core Data, or VIPER.
- Cloud inventory sync before transactional local commits.
