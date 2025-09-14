# Conda setup

## One-time config
```bash
conda config --add channels conda-forge
conda config --set channel_priority strict
```

## Create & activate environment
```bash
conda env create -f env/environment.yml
conda activate ontomap-mondo
```

## Google Cloud auth
```bash
gcloud auth application-default login
```

## ROBOT options
- **Docker (recommended):**
  ```bash
  ./tools/robot.sh --version
  ```
- **No Docker (local Java via conda):**
  ```bash
  ./tools/robot_local.sh --version
  ```
  The script downloads `tools/robot.jar` on first run.

## Sanity check
```bash
python -c "import pandas, google.cloud.bigquery, oaklib, rdflib; print('env OK')"
```