# API image for Bodegas del Atuel (task 6.13).
#
# Build from the repository root (the build context must be the root so the
# api/ tree can be copied):
#
#   docker build -f api/Dockerfile -t bodegas-api .
#
# Run with the environment documented in docs/informe/07-api.md
# (POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, DB_USER, DB_PASSWORD,
# POSTGRES_SSLMODE — use sslmode=require for Aiven) — never bake credentials
# into the image:
#
#   docker run --rm -p 8000:8000 --env-file .env bodegas-api
#
# The image runs the API as the application role app_rw through those
# variables; it is NOT a database image and never needs the owner role.

FROM python:3.11-slim

WORKDIR /srv/api

# Pinned runtime and test dependencies (api/requirements.txt).
COPY api/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Application package only: routers, repos, schemas, errors, config, db.
COPY api/app ./app

# No ENV defaults on purpose: credentials are supplied at run time only
# (docker run --env-file), and the app already fails fast when required
# configuration is missing (app/config.py). Never bake secrets into the image.

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/salud', timeout=4).status == 200 else 1)"

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
