# OntoMap‑MONDO

**LLM‑assisted, SQL‑native mapping from source vocabularies to MONDO** using BigQuery AI.
- ✅ *Approach 1 (AI Architect):* `AI.GENERATE_TABLE`, `AI.GENERATE`, `AI.GENERATE_BOOL`
- ✅ *Approach 2 (Semantic Detective):* `ML.GENERATE_EMBEDDING`, `VECTOR_SEARCH`, `CREATE VECTOR INDEX`

> Kaggle team name: **OntoMap‑MONDO**

## What it does
1. Builds embeddings for **MONDO** labels/synonyms and **source terms** (e.g., DOID, Orphanet disease strings).
2. Shortlists top‑K MONDO candidates for each source term via **VECTOR_SEARCH**.
3. Uses **`AI.GENERATE_TABLE`** to pick the single best MONDO ID with **confidence** and **rationale**.
4. Adds guardrails (`AI.GENERATE_BOOL`) and a **curation queue** sorted by low confidence / disagreements.
5. Evaluates against a tiny **gold set** (Top‑1 accuracy) and supports ablation (**LLM‑only vs LLM+vector**).

## Quickstart
1. Open BigQuery Console → create or select a project.
2. Run **`sql/ontomap_starter.sql`** (copy‑paste or upload) in a new dataset (the script creates `map` by default).
3. Replace seed rows in `map.mondo_terms` and `map.src_terms` with your real MONDO + source vocab.
4. Re‑run steps 3→10 inside the SQL to regenerate candidates, mappings, and evaluation.
5. (Optional) Save key queries as **Saved Queries** and wire a tiny UI if desired.

### Model names
The script uses placeholders:
- Embeddings model: ``bqml.text_embedding_model`` (e.g., `text-embedding-004` behind the scenes)
- Generative model: ``bqml.gemini_model`` (e.g., `gemini-1.5-pro`)

Adjust to your project defaults if needed.

## How this meets Kaggle approaches
- **Approach 1 (required):** `AI.GENERATE_TABLE` creates structured mapping rows (id, label, confidence, rationale).  
- **Approach 2 (optional but included):** `ML.GENERATE_EMBEDDING` + `VECTOR_SEARCH` shortlist candidates; `CREATE VECTOR INDEX` for scale.

## Evaluation
The starter includes a tiny gold table (`map.gold_mappings`) and metrics (`map.eval`).  
Report: **Top‑1 accuracy** overall and at `confidence ≥ 0.7`. Add your own gold xrefs for a real eval.

## Notes
- Keep provenance: store prompts/model versions as columns if you expand the pipeline.
- Curator UX: export the **curation queue** query into a simple web table for review/approval.
- Licensing: MONDO is open; ensure any source vocabularies you include are allowed for redistribution.