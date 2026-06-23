#!/bin/sh
set -eu

mc alias set lakehouse "${MINIO_ENDPOINT:-http://minio:9000}" \
    "${MINIO_ROOT_USER}" \
    "${MINIO_ROOT_PASSWORD}"

mc mb --ignore-existing "lakehouse/${MINIO_BUCKET_BRONZE:-lakehouse-bronze}"
mc mb --ignore-existing "lakehouse/${MINIO_BUCKET_SILVER:-lakehouse-silver}"
mc mb --ignore-existing "lakehouse/${MINIO_BUCKET_GOLD:-lakehouse-gold}"
mc mb --ignore-existing "lakehouse/${MINIO_BUCKET_DERIVED:-lakehouse-derived}"

echo "MinIO buckets initialized"
