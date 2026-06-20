-- Read-only checks for EEG MVP schema readiness.

SELECT
    table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
      'users',
      'experiments',
      'upload_sessions',
      'experiment_events',
      'source_files',
      'pipeline_runs',
      'pipeline_artifacts',
      'audit_events'
  )
ORDER BY table_name;

SELECT
    tc.constraint_name,
    tc.table_name
FROM information_schema.table_constraints tc
WHERE tc.table_schema = 'public'
  AND tc.constraint_name IN (
      'experiments_experiment_id_key',
      'users_username_key',
      'uq_source_files_bucket_object_key'
  )
ORDER BY tc.table_name, tc.constraint_name;
