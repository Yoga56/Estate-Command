# Estate Command on SAP

The SAP edition of Estate Command: tomorrow's crew assignment, the assumption register, the
decision log, the AI layer and the stores answer, running **inside** SAP S/4HANA Cloud Public
Edition or the SAP BTP ABAP environment as ABAP Cloud (RAP, CDS, OData V4, Fiori).

It follows the patterns of the CFO cockpit in `ZDEMO_FSCM_AI`: the same provider seam
(`ZIF_*_AI_PROVIDER`, factory with fallback order, Bedrock and Gemini over communication
arrangements), the same RAP shape (a managed BO created by a static action, the figures computed
in ABAP, the model only wording them), application jobs, and a freestyle UI5 app over the
service.

The rule from the Python app holds here too: **the server computes, the model writes**, and the
guardrail is checked, not trusted. Every number and block label in generated text is looked for in
the evidence it was written from (`ZCL_EST_AUDIT`), with one self-correction pass; the plan still
carries its figures when every provider fails (status `F`).

---

## What runs where

| Python (this repo) | SAP edition (`sap/src`, package `ZESTATE_CMD`) |
|---|---|
| `gis/ops.py` `_state()` - blocks, crews, attendance, ledger | `ZCL_EST_DATA` over tables `ZEST_BLOCK`, `ZEST_CREW`, `ZEST_ATTEND`, `ZEST_WORKORD`, `ZEST_UPKEEP` |
| `gis/ops.py` `demand()` (harvest, prune, weed, spray) | `ZCL_EST_DEMAND` |
| `gis/ops.py` `_expected_present()` | `ZCL_EST_DATA->EXPECTED_PRESENT` |
| `gis/models/scheduler.py` - greedy, swap pass, upper bound, contiguity cost | `ZCL_EST_SCHEDULER`, geometry in `ZCL_EST_GEO` |
| `gis/assumptions.py` + `decisions.db` | `ZCL_EST_ASSUMPTIONS`, table `ZEST_ASSUMP`, RAP BO `ZR_EST_ASSUMP` |
| `gis/decisions.py` decision log, drafted artifacts | RAP BO `ZR_EST_PLAN`: Accept / Reject / Defer, `DraftArtifact`, `Outcomes` |
| `gis/reasoning.py` `audit_figures` | `ZCL_EST_AUDIT` |
| `gis/briefings.py` handover, artifact instructions | `ZCL_EST_PLAN_BUILDER` (`HANDOVER`, `DRAFT_ARTIFACT`) |
| `/gis/ask` | action `Ask` on a plan, audited |
| `llm_client.py` (Groq / Bedrock) | `ZIF_EST_AI_PROVIDER`, `ZCL_EST_AI_FACTORY`, `ZCL_EST_AI_BEDROCK`, `ZCL_EST_AI_GEMINI` |
| Open-Meteo rainfall | `ZCL_EST_WEATHER` (communication scenario `ZEST_WEATHER`) |
| `gis/stores.py`, `models/leadtime.py`, `consumption.py`, `safety_stock.py`, `mm.py` | `ZCL_EST_STORES`, `ZCL_EST_MM_DATA` (released MM views, or `ZEST_MM_MOCK`), custom entity `ZI_EST_STORES` |
| `gis/data/synthetic/*.csv` | Data Import BO `ZR_EST_IMPORT` + `sap/tools/export_sap_seed.py` |
| `/command` MapLibre map | UI5 app `sap/app/estatecommand` (SVG block map, CSP-safe) |
| background warm-up / cron | application job `ZCL_EST_PLAN_JOB` |

What changes in SAP:

- **Stores reads SAP MM itself.** An estate with a plant reads `I_ProductSupplyPlanning`,
  `I_MaterialStock_2`, `I_PurchaseOrderAPI01` / `I_PurchaseOrderItemAPI01`,
  `I_MaterialDocumentItem_2`, `I_Supplier` and `I_ProductDescription` - the MB51, ME80FN, MM60
  and MB52 extracts the Python app asks the client for. Without a plant it reads the sample rows.
- **The decision log is a business object** with who, when and what was expected, and a
  feature control that closes a plan once accepted or rejected.
- **Nothing is posted.** As in the Python app, a plan drafts its work document and stops; no
  purchase requisition or maintenance order is created.

Not ported in this release (they stay in the Python app): pest and dispatch operations, fire
triage, the monthly FFB ensemble and conformal bands, the four learned operational models (rain,
headcount, slippage, crew speeds - the SAP edition uses their fallback methods: forecast or set
rain, trailing attendance, flat quota and register rates), Sentinel-2 NDRE, the 44-tool copilot
and the text-to-SQL surfaces.

---

## Objects

| Kind | Objects |
|---|---|
| Tables | `ZEST_AI_PROV`, `ZEST_ESTATE`, `ZEST_BLOCK`, `ZEST_CREW`, `ZEST_ATTEND`, `ZEST_WORKORD`, `ZEST_UPKEEP`, `ZEST_ASSUMP`, `ZEST_PLAN`, `ZEST_PLAN_L`, `ZEST_IMPORT`, `ZEST_MM_MOCK` |
| RAP BOs | `ZR_EST_PLAN` (+ `_L`), `ZR_EST_ASSUMP`, `ZR_EST_ESTATE`, `ZR_EST_IMPORT`; projections `ZC_*`; behavior pools `ZBP_R_EST_*` |
| Read-only | `ZI_EST_BLOCK`, custom entity `ZI_EST_STORES` (`ZCL_EST_STORES_QUERY`), value helps `ZI_EST_AI_PROV_VH`, `ZI_EST_ESTATE_VH` |
| Action parameters | `ZA_EST_GEN_PLAN`, `ZA_EST_REPLAN`, `ZA_EST_PROVIDER`, `ZA_EST_DECISION`, `ZA_EST_QUESTION`, `ZA_EST_ANSWER`, `ZA_EST_ESTATE_P`, `ZA_EST_HANDOVER`, `ZA_EST_OUTCOME` |
| Service | definition and OData V4 UI binding `ZUI_EST_CMD_O4` |
| Classes | see the table above; `ZCL_EST_SEED` and `ZCL_EST_AI_TEST` are run with F9 |

The XML beside each source is generated: `python sap/tools/abapgit_meta.py`.

---

## Deploy

### 1. Pull and activate (ADT)

1. Create package `ZESTATE_CMD` (software component of your choice).
2. *abapGit Repositories* view → link this repository to the package, branch of your choice →
   **Pull**. `.abapgit.xml` at the root points abapGit at `/sap/src/`; the Python app is ignored.
3. Activate all (Ctrl+Shift+F3). If mass activation complains, in this order: tables →
   the value helps `ZI_EST_AI_PROV_VH` and `ZI_EST_ESTATE_VH` (the action parameters `ZA_*`
   check their value-help entities at activation, so these must be active first) →
   `ZR_*`, `ZI_*`, `ZA_*` views and `ZI_EST_STORES` → `ZCX_EST_AI`, `ZIF_EST_AI_PROVIDER`,
   `ZCL_EST_AI_*` → `ZCL_EST_GEO`, `ZCL_EST_ASSUMPTIONS`, `ZCL_EST_DATA`, `ZCL_EST_WEATHER`,
   `ZCL_EST_DEMAND`, `ZCL_EST_SCHEDULER`, `ZCL_EST_AUDIT`, `ZCL_EST_PLAN_BUILDER`,
   `ZCL_EST_IMPORT`, `ZCL_EST_MM_DATA`, `ZCL_EST_STORES`, `ZCL_EST_STORES_QUERY` → `ZC_*` views →
   behavior definitions and `ZBP_*` → metadata extensions → `ZUI_EST_CMD_O4` → the remaining classes.
4. Create the service binding in ADT - it is not in the repository, because its binding content
   cannot be written by hand: right-click service definition `ZUI_EST_CMD_O4` → *New Service
   Binding* → name `ZUI_EST_CMD_O4`, type *OData V4 - UI* → activate → **Publish**.
   `.abapgit.xml` ignores the binding, so later pulls leave it alone.

### 2. Objects to create by hand in ADT

These have no hand-writable abapGit format.

| Object | Name | Settings |
|---|---|---|
| Outbound service (HTTP) | `ZEST_WEATHER_REST` | Default path prefix empty (optional) |
| Communication scenario | `ZEST_WEATHER` | Outbound `ZEST_WEATHER_REST`; auth None (optional) |
| Application job catalog entry | `ZEST_PLAN_JOB` | Class `ZCL_EST_PLAN_JOB` |
| Application job template | `ZEST_PLAN_JOB_T` | Catalog entry above |
| Application job catalog entry | `ZEST_SEED_JOB` | Class `ZCL_EST_SEED` (seed in client 100) |
| Application job template | `ZEST_SEED_JOB_T` | Catalog entry above |
| IAM app (external, UI5) | `ZEST_COMMAND_EXT` | Service `ZUI_EST_CMD_O4` (OData V4), UI5 app `ZEST_COMMAND` |
| Business catalog | `ZEST_COMMAND_BC` | App above; assign to a business role |

Publish the weather scenario locally if you create it.

The AI providers reuse the communication scenarios already in the system; `ZCL_EST_SEED` writes
these rows into `ZEST_AI_PROV`:

| Provider | Type | Scenario / outbound service | Model |
|---|---|---|---|
| `GEMINI_38F` (default) | Gemini | `ZCA_CCORE_OUT` / `ZCA_CCORE_REST` | `gemini-3.8-flash` |
| `GEMINI_35F` | Gemini | `ZCA_CCORE_OUT` / `ZCA_CCORE_REST` | `gemini-3.5-flash` |
| `NOVA_2_LITE` | Bedrock | `ZFSCM_AI_BEDROCK` / `ZFSCM_AI_BEDROCK_REST` | `us.amazon.nova-2-lite-v1:0` |
| `NOVA_PRO` | Bedrock | `ZFSCM_AI_BEDROCK` / `ZFSCM_AI_BEDROCK_REST` | `us.amazon.nova-pro-v1:0` |
| `BYTEPLUS_SEED` | BytePlus ModelArk (`ZCL_EST_AI_BYTEPLUS`, OpenAI-compatible chat completions) | `ZCA_BYTEPLUS_OUT` / `ZCA_BYTEPLUS_REST` | `seed-1-6-250615` |

The key is read from the row's `API_KEY` field, else from arrangement property `API_KEY`. If an
existing arrangement keeps no `API_KEY` property (the CFO cockpit keeps its Gemini key in
`ZFSCM_AI_PROV`), put the key into the `ZEST_AI_PROV` row instead. Model IDs are plain fields:
change `MODEL_ID` (for BytePlus, a model name or an `ep-...` endpoint ID) to what the account
has access to; a provider that fails is skipped for the next one by priority.

### 3. Communication arrangements (Fiori launchpad, administrator)

The AI arrangements of `ZCA_CCORE_OUT`, `ZFSCM_AI_BEDROCK` and `ZCA_BYTEPLUS_OUT` already exist.
For the rain forecast only: communication system host `api.open-meteo.com`, port 443, outbound
user authentication *None*, arrangement on scenario `ZEST_WEATHER`.

The weather arrangement is optional: without it the plan says the rain is unknown and decides
without it (set rain on a replan to override).

### 4. Configure and check

1. Run `ZCL_EST_SEED` (F9): provider rows, the assumption register, sample estate `SMPL`
   (40 blocks of 30 ha in Riau, 9 crews, 45 days of ledger, upkeep rounds, stores records). Rerunning keeps API keys
   and changed assumption values; it rebuilds `SMPL` only.
2. Run `ZCL_EST_AI_TEST` (F9): one call per provider, then a plan per operation for `SMPL`
   and the stores answer - the whole chain without the UI.
3. Preview `ZUI_EST_CMD_O4`:
   - *Plan* → **Plan Tomorrow** (estate `SMPL`, operation `harvest`) → object page: plan note,
     assignment, why, weather, decision log, work document, AI run and evidence. **Accept**,
     **Reject**, **Defer**, **Replan**, **Refresh AI Words**, **Draft Work Document**, **Ask**,
     **Did It Work?**; **Shift Handover** on the list.
   - *Assumption* → change a value, save: the next plan is priced with it. **Back to Default**.
   - *Stores* → filter on an estate: what to order, by when, and why.
   - *Estate* → set the plant (S/4 MM data), coordinates (rain forecast), default provider and
     the day the data ends.
4. *Application Jobs* app → schedule template `ZEST_PLAN_JOB_T` daily at 18:00: tomorrow's plans
   for every estate and operation are waiting in the morning.

### 4a. Client 100

ADT runs classes (F9) only in development client 80, but the communication arrangements and the
CFO cockpit's keys are maintained in client 100. Code is shared; table contents are per client.

1. In client 100, *Maintain Business Roles*: add business catalog `ZEST_COMMAND_BC` to a role of
   your user (the IAM app must list service `ZUI_EST_CMD_O4`).
2. *Application Jobs* → create a job from template `ZEST_SEED_JOB_T` (*Rebuild sample estate
   SMPL* ticked) → run once. Its application log shows the provider rows, any provider still
   without a key, the register and the sample estate. Keys are copied from `ZFSCM_AI_PROV` of
   client 100.
3. Keys or models to change: entity *AIProvider* of `ZUI_EST_CMD_O4` (create, change, delete
   provider rows; `ApiKey` blank means arrangement property `API_KEY`).
4. *Application Jobs* → template `ZEST_PLAN_JOB_T` → run once: a plan per operation for every
   estate; the Plan app shows them with the model's words, or status `F` and the reason.
5. UI5 app against client 100: `npm run start-100` (destination `my402225`). There is no deploy
   to client 100: the BSP application is a repository object, deployed once from client 80 and
   visible in both clients.

### 5. The estate's own data

```bash
python sap/tools/export_sap_seed.py --estate EC      # writes sap/seed/EC/*.csv (gitignored)
```

In *DataImport* create one row per file - Kind `BLOCKS`, `CREWS`, `ATTENDANCE`, `ORDERS`
(harvest and upkeep files separately), `UPKEEP`, `MM` - with estate `EC`, upload the file, then
**Load**. A file replaces the estate's earlier rows of that kind (`ORDERS` only for the operations
in the file). The `BLOCKS` load creates the estate; then set *Data Ends On* to `2025-05-23` so
tomorrow is 2025-05-24, as in the Python app. With the ArcGIS export present the blocks carry
their polygons; without it they are placed on their road segments and adjacency falls back to
centroids closer than 600 m.

### 6. UI5 app (SAP Business Application Studio)

```bash
git clone -b claude/zdemo-fscm-ai-sap-cloud-y6dued https://github.com/yoga56/estate-command.git
cd estate-command/sap/app/estatecommand
npm install
npm start          # preview against client 80 through destination my402244
npm run deploy     # BSP application ZEST_COMMAND in package ZESTATE_CMD (client 80)
```

`ui5-local.yaml` / `npm run start-local` run the same from a local machine without BAS
(reentrance ticket); `ui5-100.yaml` / `npm run start-100` preview against client 100. Deploy only
to client 80: clients 80 and 100 share the repository, so the app is in client 100 as well.

Then, to put it on the launchpad (ADT, client 80):

1. *New → Other → Launchpad App Descriptor Item* `ZEST_COMMAND_UI5R`: app ID `zestate.command`,
   semantic object `EstatePlan`, action `display`, tile title *Estate Command*.
2. *IAM App* `ZEST_COMMAND` of type *UI5 Application* (shown as `ZEST_COMMAND_EXT`): UI5 app
   `ZEST_COMMAND_UI5R`; on *Services* add OData V4 service binding `ZUI_EST_CMD_O4`. **Publish
   Locally**.
3. *Business Catalog* `ZEST_COMMAND_BC`: add the IAM app. **Publish Locally**.
4. Client 100, *Maintain Business Roles*: add `ZEST_COMMAND_BC` to a role, assign your user.

The map is Leaflet 1.9.4 (bundled in `webapp/thirdparty/leaflet`, BSD-2-Clause, so no script
comes from outside the system) over Esri World Imagery tiles. Sample estate `SMPL` lies over a
planted grid in Rokan Hulu, Riau: 40 blocks of 300 m by 1,000 m; zoom in and the palms show
inside the rectangles. If the launchpad blocks the tiles (blank background, blocks still drawn),
allow `https://server.arcgisonline.com` for images in client 100's *Maintain Protection
Allowlists* app (content security policy).

---

## Check on first activation

These names come from the released-API documentation and could not be activated against a system
from here:

- `ZCL_EST_MM_DATA->READ_PLANT`: `I_ProductSupplyPlanning` (`ReorderThresholdQuantity`,
  `SafetyStockQuantity`, `PlannedDeliveryDurationInDays`, `LotSizeRoundingQuantity`, `MRPType`),
  `I_MaterialStock_2` (`MatlWrhsStkQtyInMatlBaseUnit`, `InventoryStockType`),
  `I_PurchaseOrderItemAPI01` (`IsCompletelyDelivered`, `PurchasingDocumentDeletionCode`),
  `I_MaterialDocumentItem_2` (`GoodsMovementType`, `QuantityInBaseUnit`, `PurchaseOrder`,
  `PurchaseOrderItem`). Only stores on an estate **with a plant** read them.
- `ZCL_EST_AI_HTTP=>GET_API_KEY`: the shape of `IF_COM_ARRANGEMENT->GET_PROPERTIES( )` (as in
  `ZDEMO_FSCM_AI`).
- `cl_abap_random_float` in `ZCL_EST_STORES` (released for ABAP Cloud; seed fixed so the
  answer is repeatable).

`abaplint` (ABAP Cloud syntax, released API stubs of 2305) passes on every source except its known
parser gap on multi-entity `MODIFY ENTITIES`, which it reports for `ZDEMO_FSCM_AI` too.
