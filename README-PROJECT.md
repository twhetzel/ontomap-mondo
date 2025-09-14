# OntoMap MONDO

## Description
Kaggle BigQuery AI - Building the Future of Data hackathon project. The goal of this project is to use BigQuery AI to create mappings between the diseae ontology MONDO and other disease ontologies such as the [Disease Ontology](https://disease-ontology.org/), [Orphanet](https://www.orpha.net/). Future examples will include [MeSH](https://www.ncbi.nlm.nih.gov/mesh/), [ICD11](https://icd.who.int/) and [OMIM](https://www.omim.org/).  

## Prerequisites
- Conda https://anaconda.org/anaconda/conda
- Google Cloud account https://cloud.google.com
- Docker (if using ROBOT from Docker)
- Java (if using ROBOT local download)
- ROBOT https://robot.obolibrary.org/
- mondo.owl https://github.com/monarch-initiative/mondo/releases/tag/v2025-09-02

## Set-up
### Conda environment
- Create the conda environment as: 
```
conda env create -f env/environment.yml
conda activate ontomap-mondo
 ```
- Sanity check:
`!python -c "import pandas, google.cloud.bigquery, oaklib, rdflib; print('env OK')"`

### Google Cloud project
- Select or create a Google Cloud project [here](https://console.cloud.google.com/cloud-resource-manager)

- Make sure that billing is enabled for [your project](https://cloud.google.com/billing/docs/how-to/modify-project).

- Create a Billing alert for your project. 

- Enable the BigQuery, BigQuery Connection, and Vertex AI APIs [here](https://console.cloud.google.com/flows/enableapi?apiid=bigquery.googleapis.com,bigqueryconnection.googleapis.com,aiplatform.googleapis.com)

- Install the [Cloud SDK](https://cloud.google.com/sdk) to run the notebook locally.


### GCP auth for BigQuery
- Set the Application Default Credentials (ADC) on your machine so Google client libraries (BigQuery, Storage, etc.) can authenticate from your code/notebooks as:
`gcloud auth application-default login`

### ROBOT (choose one)
`sh tools/robot.sh --version`          # via Docker
`sh tools/robot_local.sh --version`    # via local Java (downloads robot.jar)

## Create gold standard mapping set
- Use ROBOT to query Mondo mappings to the Disease Ontology (DOID) 
```
ROBOT_JAVA_ARGS='-Xms4g -Xmx20g' \
sh tools/robot.sh query -i data/mondo.owl -q sparql/get_mappings.rq data/mondo_mappings.tsv
```

## Create tables
-- MONDO dictionary (id, label, synonyms)
CREATE TABLE map.mondo_terms (
  mondo_id STRING,
  label STRING,
  synonyms ARRAY<STRING>,
  emb ARRAY<FLOAT64>  -- for Approach 2
);

-- Canonical (keep as-is)
-- map.mondo_terms(mondo_id, label, synonyms ARRAY<STRING>, emb ARRAY<FLOAT64>)

-- Derived search table (one row per label/synonym)
CREATE OR REPLACE TABLE map.mondo_terms_expanded AS
SELECT mondo_id, label AS term, 'label' AS kind FROM map.mondo_terms
UNION ALL
SELECT mondo_id, s AS term, 'synonym' AS kind
FROM map.mondo_terms, UNNEST(synonyms) AS s;

ALTER TABLE map.mondo_terms_expanded ADD COLUMN emb ARRAY<FLOAT64>;
UPDATE map.mondo_terms_expanded
SET emb = ML.GENERATE_EMBEDDING(MODEL `bqml.text_embedding_model`,
                                STRUCT(term AS content))
WHERE emb IS NULL;

-- (Optional) index for larger tables
CREATE VECTOR INDEX map.mondo_terms_expanded_idx
ON map.mondo_terms_expanded(emb)
OPTIONS (distance_type="COSINE");

-- Vector search returns the best matching label/synonym; join back to the term
WITH q AS (
  SELECT ML.GENERATE_EMBEDDING(MODEL `bqml.text_embedding_model`,
                               STRUCT('parkinsonism' AS content)) AS qemb)
SELECT e.mondo_id, e.term, e.kind, vs.distance
FROM VECTOR_SEARCH(TABLE map.mondo_terms_expanded, 'emb', (SELECT qemb FROM q), 10) vs
JOIN map.mondo_terms_expanded e ON e.mondo_id = vs.id  -- if you used mondo_id as the row id
ORDER BY vs.distance;

=-=-=-=-=-=-=

-- External vocabulary to map (e.g., MeSH)
CREATE TABLE map.src_terms (
  src_id STRING,
  src_label STRING,
  context STRING,     -- optional: scope note/definition
  emb ARRAY<FLOAT64>
);

-- Final mapping suggestions (to be reviewed)
CREATE TABLE map.mapping_suggestions (
  src_id STRING,
  mondo_id STRING,
  mondo_label STRING,
  confidence DOUBLE,
  rationale STRING,
  method STRING,          -- 'llm_only' | 'llm+vector'
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

