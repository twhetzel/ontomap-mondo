#!/usr/bin/env python
"""Basic mapping validation scaffold.

- Connects to BigQuery.
- Reads map.mapping_suggestions and map.mondo_terms.
- Checks for missing MONDO IDs and prints simple accuracy if gold table present.
"""
import argparse
from google.cloud import bigquery

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--project', required=True)
    ap.add_argument('--dataset', default='map')
    args = ap.parse_args()

    client = bigquery.Client(project=args.project)

    # Missing MONDOs
    q_missing = f'''
    SELECT s.src_id, s.mondo_id
    FROM `{args.project}.{args.dataset}.mapping_suggestions` s
    LEFT JOIN `{args.project}.{args.dataset}.mondo_terms` m
    ON s.mondo_id = m.mondo_id
    WHERE m.mondo_id IS NULL
    '''
    print("== Missing MONDO IDs in mondo_terms ==")
    for row in client.query(q_missing):
        print(dict(row))

    # Accuracy if gold exists
    q_eval = f'''
    SELECT
      COUNT(*) AS n,
      AVG(CASE WHEN s.mondo_id = g.mondo_id THEN 1 ELSE 0 END) AS accuracy_top1,
      AVG(CASE WHEN s.confidence >= 0.7 AND s.mondo_id = g.mondo_id THEN 1 ELSE 0 END) AS accuracy_top1_conf_ge_0p7
    FROM `{args.project}.{args.dataset}.mapping_suggestions` s
    JOIN `{args.project}.{args.dataset}.gold_mappings` g USING (src_id)
    '''
    print("\n== Accuracy (if gold_mappings exists) ==")
    for row in client.query(q_eval):
        print(dict(row))

if __name__ == '__main__':
    main()