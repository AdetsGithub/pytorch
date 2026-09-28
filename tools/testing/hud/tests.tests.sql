-- One row per test case in code. See proposal.md section 4.2.

CREATE TABLE tests.tests
(
    -- What: identity of one test case in code.
    -- Derived: sipHash64(concat(repo, '\0', file, '\0', suite, '\0', case_name)),
    --   computed by the ingester inside the INSERT ... SELECT from the values below.
    -- Used: join key of runs, health_daily and health; the hub's stable URL id.
    test_id       UInt64,

    -- What: repository the test lives in, e.g. pytorch/pytorch.
    -- Derived: GITHUB_REPOSITORY, written by the producer as a testsuite property.
    -- Used: scopes the catalog when other pytorch org repos join; part of the hash.
    repo          LowCardinality(String),

    -- What: repo-relative path of the file that defines the test,
    --   e.g. test/test_torch.py or test/cpp/api/modulelist.cpp.
    -- Derived: pytest, the file part of the nodeid; gtest, the file attribute with
    --   the workspace prefix stripped.
    -- Used: owner lookup through tests.owners; per-file rollups. Distinct
    --   from runs.invoking_file, which is the file that launched the test.
    file          LowCardinality(String),

    -- What: test class or gtest suite; empty for module-level functions.
    -- Derived: pytest, the last component of the class path in the nodeid;
    --   gtest, the classname attribute.
    -- Used: display and search; the disable-issue join on "test_x (__main__.Suite)".
    suite         String,

    -- What: test name exactly as the runner selects it, parametrization included,
    --   e.g. test_add_cpu_float32 or test_foo[1-2].
    -- Derived: pytest, the name part of the nodeid; gtest, the name attribute.
    -- Used: display and search; LIKE filters on parameters until generators emit
    --   them as separate properties (a future params column).
    case_name     String,

    -- What: when the ingester first saw the test.
    -- Derived: ingester clock at the insert, which happens only for an unseen test_id.
    -- Used: first seen for the test; version column of ReplacingMergeTree.
    first_seen_at DateTime
)
ENGINE = ReplacingMergeTree(first_seen_at)
ORDER BY test_id;
