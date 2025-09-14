-- =========================================================
-- OntoMap‑MONDO — BigQuery AI Starter (Approach 1 + 2)
-- =========================================================

-- 0) Dataset
CREATE SCHEMA IF NOT EXISTS map;

-- 1) Canonical MONDO dictionary (id, label, synonyms)
CREATE OR REPLACE TABLE map.mondo_terms (
  mondo_id STRING,
  label STRING,
  synonyms ARRAY<STRING>,
  emb ARRAY<FLOAT64>
);

INSERT INTO map.mondo_terms (mondo_id, label, synonyms)
VALUES
  ('MONDO:0004975','Alzheimer disease', ['Alzheimer''s disease','AD','Alzheimer dementia']),
  ('MONDO:0005180','Parkinson disease', ['Parkinson''s disease','PD']),
  ('MONDO:0004979','Amyotrophic lateral sclerosis', ['ALS','Lou Gehrig disease','Motor neuron disease']);

-- 2) Source vocabulary to map (e.g., MeSH-like labels)
CREATE OR REPLACE TABLE map.src_terms (
  src_id STRING,
  src_label STRING,
  context STRING,
  emb ARRAY<FLOAT64>
);

INSERT INTO map.src_terms (src_id, src_label, context)
VALUES
  ('SRC:001','Alzheimer''s dementia','neurodegenerative cognitive decline'),
  ('SRC:002','Parkinsonism','movement disorder with tremor and rigidity'),
  ('SRC:003','Lou Gehrig''s disease','progressive motor neuron degeneration');

-- (Optional) Gold mappings for evaluation
CREATE OR REPLACE TABLE map.gold_mappings (
  src_id STRING,
  mondo_id STRING
);
INSERT INTO map.gold_mappings VALUES
  ('SRC:001','MONDO:0004975'),
  ('SRC:002','MONDO:0005180'),
  ('SRC:003','MONDO:0004979');

-- 3) Build text embeddings (labels + synonyms/context)
UPDATE map.mondo_terms
SET emb = ML.GENERATE_EMBEDDING(
  MODEL `bqml.text_embedding_model`,
  STRUCT(CONCAT_WS(' ', label, ARRAY_TO_STRING(synonyms, ' ')) AS content)
)
WHERE emb IS NULL;

UPDATE map.src_terms
SET emb = ML.GENERATE_EMBEDDING(
  MODEL `bqml.text_embedding_model`,
  STRUCT(CONCAT_WS(' ', src_label, COALESCE(context,'')) AS content)
)
WHERE emb IS NULL;

-- 4) Create a vector index (recommended if ≥~1M rows)
CREATE VECTOR INDEX IF NOT EXISTS map.mondo_idx
ON map.mondo_terms(emb)
OPTIONS (distance_type = "COSINE");

-- 5) Top-K MONDO candidates per source term using VECTOR_SEARCH
CREATE OR REPLACE TABLE map.src_topk AS
WITH c AS (
  SELECT s.src_id, s.src_label, vs.id AS mondo_row_id, vs.distance
  FROM map.src_terms AS s,
       VECTOR_SEARCH(TABLE map.mondo_terms, 'emb', s.emb, 10) AS vs
)
SELECT
  c.src_id,
  c.src_label,
  m.mondo_id,
  m.label AS mondo_label,
  c.distance
FROM c
JOIN map.mondo_terms m
  ON m.mondo_id = mondo_row_id
ORDER BY src_id, distance;

-- 6) Aggregate candidates per src into JSON (one row per src_id)
CREATE OR REPLACE TABLE map.src_candidates_json AS
SELECT
  src_id,
  ANY_VALUE(src_label) AS src_label,
  TO_JSON_STRING(ARRAY_AGG(STRUCT(mondo_id, mondo_label, distance) ORDER BY distance)) AS candidates_json
FROM map.src_topk
GROUP BY src_id;

-- 7) LLM pick-one with rationale (Approach 1)
CREATE OR REPLACE TABLE map.mapping_suggestions AS
SELECT
  s.src_id,
  s.src_label,
  out.mondo_id,
  t.label AS mondo_label,
  out.confidence,
  out.rationale,
  'llm+vector' AS method,
  CURRENT_TIMESTAMP() AS created_at
FROM AI.GENERATE_TABLE(
  MODEL `bqml.gemini_model`,
  TABLE map.src_candidates_json,
  PROMPT => '''
  You are mapping source disease terms to MONDO.
  You are given a source label and a JSON array "candidates_json" with the Top-K candidate MONDO terms.
  Choose the single best MONDO id, and explain briefly.

  Output columns (exact names):
    mondo_id STRING,
    confidence FLOAT64,         -- 0 to 1
    rationale STRING

  Decision tips:
   - Prefer exact lexical/synonym match.
   - Avoid choosing a broad parent if an exact term exists.
   - If ambiguous, pick the most specific reasonable match and lower confidence.
  ''',
  INPUT_COLS => ['src_id','src_label','candidates_json']
) AS out
JOIN map.src_candidates_json s USING (src_id)
JOIN map.mondo_terms t ON t.mondo_id = out.mondo_id;

-- 8) Guardrail check — exactness boolean
CREATE OR REPLACE TABLE map.mapping_suggestions_checked AS
SELECT
  ms.*,
  AI.GENERATE_BOOL(
    'Does the source label exactly denote the same disease as the chosen MONDO label/synonyms? True/False only.',
    CONCAT('SRC: ', ms.src_label, ' || MONDO: ', ms.mondo_label)
  ) AS exact_match_bool
FROM map.mapping_suggestions ms;

-- 9) Evaluation against gold (Top-1 accuracy, with conf ≥ 0.7)
CREATE OR REPLACE TABLE map.eval AS
SELECT
  g.src_id,
  g.mondo_id AS gold_mondo,
  s.mondo_id AS pred_mondo,
  s.confidence,
  s.method,
  IF(s.mondo_id = g.mondo_id, 1, 0) AS correct
FROM map.gold_mappings g
LEFT JOIN map.mapping_suggestions_checked s USING (src_id);

-- Metrics
SELECT
  COUNT(*) AS n,
  AVG(correct) AS accuracy_top1,
  AVG(CASE WHEN confidence >= 0.7 THEN correct ELSE NULL END) AS accuracy_top1_conf_ge_0p7
FROM map.eval;

-- 10) Curation queue — lowest confidence / errors first
SELECT
  e.src_id, e.gold_mondo, e.pred_mondo, e.confidence, e.correct,
  s.src_label, s.mondo_label, ms.exact_match_bool
FROM map.eval e
JOIN map.mapping_suggestions_checked ms USING (src_id)
JOIN map.mapping_suggestions s USING (src_id)
ORDER BY (e.correct = 0) DESC, e.confidence ASC, e.src_id
LIMIT 20;

-- 11) LLM-only variant (ablation)
CREATE OR REPLACE TABLE map.mapping_llm_only AS
SELECT
  st.src_id,
  st.src_label,
  out.mondo_id,
  t.label AS mondo_label,
  out.confidence,
  out.rationale,
  'llm_only' AS method,
  CURRENT_TIMESTAMP() AS created_at
FROM AI.GENERATE_TABLE(
  MODEL `bqml.gemini_model`,
  TABLE map.src_terms AS st,
  PROMPT => '''
  Map the given source disease label to the best MONDO id and provide a short rationale.
  Output columns (exact names):
    mondo_id STRING,
    confidence FLOAT64,
    rationale STRING
  If unsure, choose the most likely and reduce confidence.
  ''',
  INPUT_COLS => ['src_id','src_label','context']
) AS out
JOIN map.mondo_terms t ON t.mondo_id = out.mondo_id;

-- 12) Ablation comparison
SELECT method,
       COUNT(*) AS n,
       AVG(CASE WHEN mondo_id = gold_mondo THEN 1 ELSE 0 END) AS accuracy_top1
FROM (
  SELECT g.src_id, g.gold_mondo, m.method, m.mondo_id
  FROM map.gold_mappings g
  JOIN (
    SELECT src_id, mondo_id, method FROM map.mapping_suggestions
    UNION ALL
    SELECT src_id, mondo_id, method FROM map.mapping_llm_only
  ) AS m USING (src_id)
)
GROUP BY method;