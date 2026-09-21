# GxP Validation Strategy — Residency Requirements App

2026-09-21

## Purpose

This sets out how the residency requirements app could be validated for use in a GxP environment, and what must change before any strategy can work.

The app is a Dash + AG Grid interface over a Lakebase Postgres database, built as a prototype. It lets users view and edit the documents required for permanent residence, per country. It is not currently fit for regulated use.

This is an engineering assessment. The validation strategy decision, the risk classification and the GxP scope determination belong to QA, and depend on how the data is actually used in the regulated process.

## The system under consideration

The regulated object is the whole computerised system, not just the application code. Categorising the parts shows where effort actually lands.

| Component | GAMP 5 category | What validation requires |
| --- | --- | --- |
| Databricks platform, Lakebase Postgres 17 | 1 — infrastructure | Supplier assessment, qualification of the hosted service, shared-responsibility mapping |
| yoyo-migrations, Dash, dash-ag-grid, psycopg, gunicorn | 1 / 3 — used as supplied | Supplier assessment, pinned versions, no code modification |
| `migrations/V1`–`V11` (schema DDL) | 5 — custom | Review, test evidence, change control |
| `app/app.py`, `app/db.py` | 5 — custom | Full lifecycle: specification, code review, testing, traceability |
| Deployment path (Databricks CLI, `fw` wrapper) | 5 — custom tooling | Qualification if used to make GxP changes |

Only the custom rows carry heavy effort, and that is where all business logic sits. The dependency versions are pinned in `app/requirements.txt`, which is a precondition for any supplier assessment to mean anything.

One structural point in the system's favour: the schema is defined entirely by migrations in source control. A new database can be built from source using the baseline migration, 0001_baseline.sql, which holds the full schema and reference data. Building an empty database from it gives a schema identical to production, confirmed by comparing schema dumps. The project's earlier Flyway history could not do this, because two of its migrations depended on state that existed only in production. The baseline replaced that history.

## Regulatory frame

Four reference points govern an application like this one.

**21 CFR Part 11** applies where electronic records replace paper in FDA-regulated processes. The demanding clauses here are §11.10(e), requiring secure, computer-generated, time-stamped audit trails that record the operator, do not obscure previously recorded information, and are retained for the record retention period; §11.10(d), limiting system access to authorised individuals; and §11.10(g), authority checks so that only authorised individuals can alter records.

**EU GMP Annex 11** covers computerised systems in the EU. It requires risk management across the lifecycle, supplier assessment, audit trails for GMP-relevant changes, and periodic evaluation. Annex 11 has been under revision; confirm the current text before citing clause numbers in a validation plan.

**GAMP 5, 2nd edition (2022)** is the industry guide. Its emphasis on critical thinking and scalable effort is what makes a lighter approach defensible, and its category model is used above.

**FDA Computer Software Assurance (CSA)** shifts effort from documentation volume toward assurance activities proportionate to risk, and explicitly accepts unscripted and exploratory testing for lower-risk features. Confirm its current status and title before relying on it as a citation.

Underneath all of them sits **ALCOA+**: data must be Attributable, Legible, Contemporaneous, Original and Accurate, plus Complete, Consistent, Enduring and Available. The current build fails Attributable outright, which is the central finding of this document.

## Gaps in the current build

Two of these are blockers: no strategy succeeds without an audit trail and user attribution, and neither can be retrofitted onto history that was never captured.

| # | Gap | Severity | Why it matters |
| --- | --- | --- | --- |
| 1 | No audit trail. `UPDATE residency_requirement SET …` overwrites in place | Blocker | Part 11 §11.10(e); prior values are destroyed, unrecoverably |
| 2 | No user attribution. The app connects as service principal `30b6f312…`, so every write looks identical | Blocker | ALCOA+ Attributable fails at the data layer |
| 3 | Physical `DELETE` removes rows outright | High | No record that data existed, or why it went |
| 4 | No electronic signatures | High if the process needs approval | Part 11 subpart C |
| 5 | No access control past "can open the app" | High | Any workspace user can edit anything; no maker/checker |
| 6 | No automated tests | High | Nothing to offer as objective evidence |
| 7 | No input validation — `document_name` accepts an empty string | Medium | Accuracy; no constraint on what reaches the record |
| 8 | Free Edition: one project, no environment separation, app stops after 24h, no SLA | Blocker for production | No validated environment can exist here |
| 9 | Operational tokens handled via clipboard | Medium | Not a controlled, repeatable procedure |
| 10 | Seed data is fabricated | Medium | Must be replaced by a controlled data load |
| 11 | The migration tool, yoyo-migrations, does not detect edits to migrations that have already run. It identifies a migration by its file name, not its contents | Medium | An altered migration goes unnoticed; change control rests on git history and review instead of a technical check |

What is already sound: versioned migrations with forward-only retraction; `country_version` implementing proper temporal history with an `EXCLUDE` constraint preventing overlapping validity periods; least-privilege grants to the app's role; and referential integrity enforced in the schema rather than in application code.

The irony worth noting is that `country` has rigorous history tracking while `residency_requirement` — the table the app actually edits — has none.

## Validation strategies

Five approaches are viable. They are not mutually exclusive — the recommendation below combines two.

### 1. Traditional scripted CSV

The V-model: URS, then functional and design specifications, then IQ, OQ and PQ protocols executed against them, tied together by a traceability matrix.

- **Pros.** Familiar to QA and to inspectors in every region. Deliverables are unambiguous and the path is well trodden. Lowest risk of argument during an audit.
- **Cons.** Disproportionate for an application this small. Every change triggers re-validation paperwork regardless of risk. Documentation volume bears little relation to actual patient or product risk. It would make routine maintenance — a CSS fix, a dependency bump — expensive enough that it gets deferred, which degrades the system over time.
- **Choose it when** the organisation has no appetite for defending a newer approach, or an inspection history that makes conservatism wise.

### 2. Risk-based CSA

Scope effort by risk, following FDA's CSA thinking and GAMP 5's critical thinking. High-risk functions get scripted testing; low-risk ones are covered by unscripted or exploratory testing, recorded but not scripted in advance.

- **Pros.** Effort tracks actual risk. Explicitly endorsed by FDA for production and quality-system software. Keeps the team able to fix and improve the system.
- **Cons.** Requires a mature QMS and a QA function comfortable with the approach. Inspector familiarity still varies. The risk rationale must be documented rigorously — an undocumented judgement that something is low risk is weaker evidence than a scripted test would have been.
- **Choose it when** QA can own and defend a documented risk assessment.

### 3. Automated validation (tests as evidence)

Test execution in the deployment pipeline produces the validation records. Re-validation after a change is a pipeline run, not a paperwork exercise.

- **Pros.** Fits this system's existing shape. The baseline migration gives every new database the same verified starting schema, and Lakebase branching can give each test run a clean, realistic database. Cheap re-validation means it actually happens after every change, rather than being deferred.
- **Cons.** The pipeline and the test tooling themselves must be qualified. Higher upfront engineering cost. Requires disciplined configuration management. Meets cultural resistance where QA expects signed documents.
- **Choose it when** the system will change regularly and the team can invest in the pipeline first.

### 4. Buy instead of build

Replace the custom app with a commercial master-data or requirements-management product that ships with a supplier validation package.

- **Pros.** Drops custom (Category 5) scope to near zero. The supplier carries the core validation burden. Often faster to a validated state than building.
- **Cons.** Fit compromises against the actual process. Licence cost and lock-in. Supplier qualification and configuration validation remain yours. Discards the work already done.
- **Choose it when** the requirement is generic enough that a product genuinely fits.

### 5. Keep the app outside GxP scope

Declare the app a non-GxP convenience tool, with a separately validated system of record.

- **Pros.** By far the cheapest. Entirely legitimate where the data does not drive regulated decisions.
- **Cons.** Only honest if true, and scope decisions attract scrutiny. This app writes to the database, so "it is only a viewer" is not available as an argument. If the data later feeds a regulated process, the scope decision fails retrospectively and the records have no audit trail.
- **Choose it when** the data genuinely sits outside the regulated process — and document why.

## Recommendation

Combine strategies 2 and 3: risk-based scope, with automated tests as the primary evidence, and scripted PQ reserved for the genuinely high-risk paths — the edit-and-save path, the audit trail itself, and access control.

The reasoning is that this system will keep changing. Between the prototype and today it went through eleven schema migrations, two of which reversed earlier decisions. A strategy that makes change expensive will not be followed; it will be circumvented, and circumvention is worse than a lighter strategy properly applied.

The system also happens to be unusually well suited to automated evidence. The schema can be rebuilt from source through the baseline migration, the database supports cheap branching for test fixtures, and the deployment path is already scripted.

Strategy 4 deserves a genuine look before committing engineering effort. If a commercial product fits the process, it will reach a validated state sooner than building the missing controls here. That comparison is worth making explicitly rather than by default.

## Technical prerequisites

No validation strategy rescues a system that cannot attribute a change. This work comes first, in roughly this order.

1. **Audit trail.** A dedicated table recording row id, column, old value, new value, timestamp, user identity and reason for change, written in the same transaction as the update. A database trigger is more defensible than application code, because it cannot be bypassed by another client.
2. **End-user attribution.** Capture the identity Databricks Apps forwards for the signed-in user and write it into the audit record, instead of attributing every change to the service principal.
3. **Logical deletion.** Replace physical `DELETE` with a status column plus a reason, so removals leave a record.
4. **Access control and segregation of duties.** Distinguish who may read, who may edit, and who approves. Add electronic signature capture if the process requires approval.
5. **Input validation.** Constrain what can reach the record — non-empty document names, bounded lengths, controlled vocabularies where they apply.
6. **Automated test suite.** Unit tests for `db.py`, integration tests against a disposable Lakebase branch, and end-to-end tests of the edit path.
7. **Environment separation.** A paid workspace with distinct development, validation and production projects. This is not possible on Free Edition.
8. **Controlled data load.** Replace the fabricated seed data with a verified load from a controlled source.

Items 1 and 2 are architectural. Every day they are deferred is a day of changes that can never be reconstructed.

## Beyond the application

Validation covers the system and the procedures around it, not only the code. These are commonly underestimated and are frequently where inspection findings land.

**Supplier assessment.** Databricks must be assessed as a supplier, and the shared-responsibility boundary documented: what they qualify, what you qualify. Cloud platforms change under you without a change request on your side, which needs an explicit position.

**Change control.** Source control and migrations give technical change management, but a GxP change control procedure must sit on top — who approves a schema change, what testing is required, how emergency changes are handled retrospectively.

**Configuration management.** Pinned dependency versions, recorded platform versions, and a defined procedure for upgrades. A Databricks runtime upgrade is a change to a validated system.

**Backup, restore and disaster recovery.** Backups must exist, and restoration must be tested, not assumed. Lakebase's history retention is currently 7 days, which is a retention decision made by default rather than deliberately.

**Record retention and archival.** GxP records often need retention far beyond an application's life. Define where records live at the end, and confirm they remain readable. Audit trail records are themselves regulated records.

**Periodic review.** Annex 11 expects periodic evaluation confirming the system remains in a validated state.

**Incident and deviation management.** A defined route from application error to deviation record, including how data integrity impact is assessed.

**Business continuity.** What happens when the system is unavailable. On Free Edition it stops itself every 24 hours, which is disqualifying on its own.

**Training and user management.** Documented training before access, and a joiner/mover/leaver process for access rights.

**Decommissioning.** How data is migrated or archived when the system is retired, with readability preserved for the retention period.

## Open questions and next steps

These determine the strategy and cannot be answered from the engineering side.

- [ ] Is this data GxP-relevant at all, and which predicate rule applies? Everything else follows from this.
- [ ] Does the process require approval of changes, and therefore electronic signatures?
- [ ] What is the patient, product and data-integrity risk if a requirement record is wrong?
- [ ] What record retention period applies?
- [ ] Is QA prepared to support a risk-based CSA approach, or is scripted CSV expected?
- [ ] Has a commercial alternative been evaluated against the process?

Suggested sequence once those are answered: confirm GxP scope, then build the audit trail and user attribution, then move off Free Edition to separated environments, then write the validation plan against whichever strategy QA selects.

Two caveats on this document. Regulatory texts move, so confirm the current status and wording of the FDA CSA guidance and the Annex 11 revision before citing them. And the gap list describes the system as built on 21 September 2026; it should be re-checked against the code before use as a validation input.

Source: living doc at https://claude.ai/code/artifact/a7afd8ec-9704-44de-9155-90adf7efe246
