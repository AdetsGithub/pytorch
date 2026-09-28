-- One row per attempt of one test in one environment in one CI job.
-- See proposal.md section 4.4.

CREATE TABLE tests.runs
(
    -- what ran and how ----------------------------------------------------------

    -- What: which test.
    -- Derived: hash of the producer-emitted identity fields, section 4.1, computed
    --   by the ingester.
    -- Used: leading sort key; join to tests.tests.
    test_id                UInt64,

    -- What: in which environment.
    -- Derived: hash of the environment's identity fields, section 4.1, computed
    --   by the ingester.
    -- Used: second sort key; join to tests.environments.
    env_id                 UInt64,

    -- What: the file run_test.py launched, when it differs from the defining file
    --   (test_jit_legacy.py running the tests defined in jit/test_dce.py).
    -- Derived: the report directory name today; a testsuite property once the
    --   producer emits it.
    -- Used: target-determination timings and per-file cost, which key on the
    --   launching file; wrapper-file cases.
    invoking_file          LowCardinality(String),

    -- where it ran; everything else about the job is in default.workflow_job -----

    -- What: the CI job.
    -- Derived: the JOB_ID the job exports, written as a testsuite property.
    -- Used: join to default.workflow_job for commit, branch, runner, conclusion and
    --   URL; the by_job projection for per-commit reads.
    github_workflow_job_id Int64,

    -- What: what the job tested: main (push to main), trunk_tag (workflow_dispatch
    --   on a trunk/<sha> tag), pr (pull_request), ciflow_tag (push on a
    --   ciflow/<workflow>/<pr> tag), release, nightly, other.
    -- Derived: by the ingester, from the branch or tag name and the event name the
    --   producer stamps.
    -- Used: trunk-only health and "main versus PR" without a join; rollup key.
    ref_kind               Enum8('other' = 0, 'main' = 1, 'trunk_tag' = 2, 'pr' = 3,
                                 'ciflow_tag' = 4, 'release' = 5, 'nightly' = 6),

    -- What: the workflow: pull, trunk, inductor, periodic, ...
    -- Derived: the GITHUB_WORKFLOW property.
    -- Used: "where does it run"; rollup key.
    workflow_name          LowCardinality(String),

    -- attempt lineage ------------------------------------------------------------

    -- What: the report this attempt came from; one test-runner process writes one
    --   report, so this also identifies the process.
    -- Derived: the random 64-bit id the report carries (written by LogXMLReruns).
    -- Used: groups the attempts of one process; per-process wall time; separates a
    --   new-process retry from an in-process rerun; join to tests.reports; with the
    --   job id, locates the report file in S3.
    report_id              UInt64,

    -- What: why this execution exists: first (first execution in a normally
    --   launched process), in_process_rerun (a later execution in the same
    --   process, from pytest-rerunfailures), new_process_retry (first execution
    --   in a process run_test.py started to retry a test).
    -- Derived: position within the report plus PYTORCH_TEST_RETRY_ROUND.
    -- Used: rerun and retry counts. The verdict is by time, not by this field.
    attempt_kind           Enum8('first' = 1, 'in_process_rerun' = 2, 'new_process_retry' = 3),

    -- outcome ---------------------------------------------------------------------

    -- What: what happened, appendix B. crashed, timed_out and not_run are always
    --   synthetic rows written by run_test.py, so no separate source flag exists.
    -- Derived: the JUnit children (failure, error, skipped with its type) for
    --   report rows; run_test.py's exit handling for synthetic rows.
    -- Used: every count in the rollups; the verdict of a job.
    outcome                Enum8('passed' = 1, 'failed' = 2, 'error' = 3, 'skipped' = 4,
                                 'xfailed' = 5, 'xpassed' = 6, 'crashed' = 7,
                                 'timed_out' = 8, 'not_run' = 9),

    -- What: the exception class or gtest failure kind, e.g. AssertionError;
    --   empty unless failed or errored.
    -- Derived: the type attribute of <failure> or <error>, else the first token of
    --   the message.
    -- Used: "what kinds of failures" aggregation; a cheap failure signature.
    failure_type           LowCardinality(String),

    -- What: the first 96 bytes of the skip message, whitespace-normalized; empty
    --   unless skipped. The only text on the row.
    -- Derived: the message attribute of <skipped>.
    -- Used: "why is it skipped" aggregation; candidate for a skip_kind enum later.
    skip_reason            LowCardinality(String),

    -- time ------------------------------------------------------------------------

    -- What: when the attempt started and ended; the duration is the difference.
    -- Derived: pytest TestReport.start and .stop, written as testcase attributes;
    --   gtest timestamp plus time.
    -- Used: ordering of attempts and verdicts, durations, partitioning, TTL.
    started_at             DateTime64(3, 'UTC'),
    ended_at               DateTime64(3, 'UTC'),

    -- provenance ------------------------------------------------------------------

    -- What: when the ingester first saw the attempt.
    -- Derived: ingester clock.
    -- Used: version column of ReplacingMergeTree; ingestion-lag monitoring.
    first_seen_at          DateTime,

    PROJECTION by_job (SELECT * ORDER BY (github_workflow_job_id, test_id, started_at))
)
ENGINE = ReplacingMergeTree(first_seen_at)
PARTITION BY toDate(started_at)
PRIMARY KEY (test_id, env_id, started_at)
ORDER BY (test_id, env_id, started_at, github_workflow_job_id, report_id)
TTL toDateTime(started_at) + INTERVAL 180 DAY
SETTINGS index_granularity = 8192;
