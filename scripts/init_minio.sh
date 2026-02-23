#!/usr/bin/env bash
set -euo pipefail

echo "==> Initialising MinIO bucket for Iceberg warehouse..."

# Wait for MinIO to be reachable
for i in $(seq 1 30); do
  if docker compose exec -T minio mc alias set local http://localhost:9000 minio minio12345 >/dev/null 2>&1; then
    break
  fi
  echo "    Waiting for MinIO... ($i)"
  sleep 2
done

# mc is not bundled inside minio/minio image; use a one-off container instead
docker run --rm --network demo-foundry_default \
  --entrypoint sh minio/mc -c "
    mc alias set myminio http://minio:9000 minio minio12345 &&
    mc mb --ignore-existing myminio/iceberg-warehouse &&
    echo 'Bucket iceberg-warehouse ready.'
  "
