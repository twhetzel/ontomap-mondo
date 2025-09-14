SHELL := /bin/bash

PROJECT ?= your-gcp-project
DATASET ?= map

.PHONY: help env robot-version robot-local-version mondo-subset validate-mappings

help:
	@echo "Targets:"
	@echo "  env                     - Create & activate conda env instructions"
	@echo "  robot-version           - ROBOT via Docker"
	@echo "  robot-local-version     - ROBOT via local Java (downloads robot.jar if missing)"
	@echo "  mondo-subset            - Example ROBOT extract (edit input/output paths)"
	@echo "  validate-mappings       - Placeholder Python validation against BigQuery"

env:
	@echo "1) (One-time) set conda-forge priority:"
	@echo "   conda config --add channels conda-forge && conda config --set channel_priority strict"
	@echo "2) Create env:"
	@echo "   conda env create -f env/environment.yml"
	@echo "3) Activate:"
	@echo "   conda activate ontomap-mondo"
	@echo "4) GCP auth for BigQuery:"
	@echo "   gcloud auth application-default login"

robot-version:
	./tools/robot.sh --version

robot-local-version:
	./tools/robot_local.sh --version

# Example: subset MONDO around a single term (edit paths/term first)
mondo-subset:
	./tools/robot_local.sh extract --method BOT \
	  -i data/mondo.owl \
	  --term MONDO:0004975 \
	  -o data/mondo_ad_subset.owl

validate-mappings:
	python scripts/validate_mappings.py --project $(PROJECT) --dataset $(DATASET)