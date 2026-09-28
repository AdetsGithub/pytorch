-- One row per report, and so per test-runner process: the report ledger. A
-- recommended addition that is still an open decision; see proposal.md
-- sections 3.6 and 8.

CREATE TABLE tests.reports
(
    -- What: the report; one test-runner process writes one report.
    -- Derived: the random 64-bit id the report carries (written by LogXMLReruns),
    --   or a new random id for the crashed and missing entries run_test.py writes.
    -- Used: the table's unique id; join to runs; with the job id, locates the
    --   report file in S3.
    report_id              UInt64,

    -- What: the job.
    -- Derived: the JOB_ID property.
    -- Used: join to workflow_job; leading sort key.
    github_workflow_job_id Int64,

    -- What: the environment of the process.
    -- Derived: as in runs; the job-level capture for crashed and missing entries.
    -- Used: coverage per environment.
    env_id                 UInt64,

    -- What: the launched file.
    -- Derived: the report directory, or the plan entry for missing rows.
    -- Used: "which files of this job reported"; sort key.
    invoking_file          LowCardinality(String),

    -- What: how the process ended.
    -- Derived: completed when a report exists; crashed or timed_out from
    --   run_test.py's exit handling; missing when the shard's plan lists the file
    --   and no report arrived.
    -- Used: "did not run" versus "lost".
    state                  Enum8('completed' = 1, 'crashed' = 2, 'timed_out' = 3, 'missing' = 4),

    -- What: testcase elements in the report.
    -- Derived: the tests attribute of <testsuite>.
    -- Used: completeness checks against earlier runs of the same file.
    tests_reported         UInt32,

    -- What: the process span.
    -- Derived: <testsuite timestamp> plus time; job times for synthetic rows.
    -- Used: process wall time and the overhead outside test calls.
    started_at             DateTime64(3, 'UTC'),
    ended_at               DateTime64(3, 'UTC'),

    -- What: when the ingester first saw the report.
    -- Derived: ingester clock.
    -- Used: ReplacingMergeTree version.
    first_seen_at          DateTime
)
ENGINE = ReplacingMergeTree(first_seen_at)
PARTITION BY toYYYYMM(started_at)
ORDER BY (github_workflow_job_id, invoking_file, report_id)
TTL toDateTime(started_at) + INTERVAL 180 DAY;
