# Graph Report - D:\science\pcm-logic-gate  (2026-05-02)

## Corpus Check
- Corpus is ~9,718 words - fits in a single context window. You may not need a graph.

## Summary
- 119 nodes · 359 edges · 12 communities detected
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.9)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- [[_COMMUNITY_README.md  AGENTS|README.md / AGENTS.md]]
- [[_COMMUNITY_Stage-2 EDASurrogate Search  Checkpoint Contract|Stage-2 EDA/Surrogate Search / Checkpoint Contract]]
- [[_COMMUNITY_Lumerical Simulation Project  Lumerical MODE API|Lumerical Simulation Project / Lumerical MODE API]]
- [[_COMMUNITY_merge_seed_block  fill_stage2_population|merge_seed_block / fill_stage2_population]]
- [[_COMMUNITY_Soft Margin Scoring  archive_guided_candidates|Soft Margin Scoring / archive_guided_candidates]]
- [[_COMMUNITY_Lightweight MATLAB Tests  testTrainOutReadsOutputPowerData|Lightweight MATLAB Tests / testTrainOutReadsOutputPowerData]]
- [[_COMMUNITY_testWorkerUsesSharedHelpersAndNoDeadMethods  testLumericalScriptsReuseSharedOpenAndPathHelpers|testWorkerUsesSharedHelpersAndNoDeadMethods / testLumericalScriptsReuseSharedOpenAndPathHelpers]]
- [[_COMMUNITY_Private Worker Simulation Copies  testBPSOHasParallelLumericalStructure|Private Worker Simulation Copies / testBPSOHasParallelLumericalStructure]]
- [[_COMMUNITY_evalParticle  softmin_score|evalParticle / softmin_score]]
- [[_COMMUNITY_Training Data MAT Files  run_parallel_eval_batch|Training Data MAT Files / run_parallel_eval_batch]]
- [[_COMMUNITY_testWorkerSimulationFileUsesPrivateCopy  make_lumerical_worker_sim_file|testWorkerSimulationFileUsesPrivateCopy / make_lumerical_worker_sim_file]]
- [[_COMMUNITY_get_env_int  testParallelConfigDefaultsAndEnvOverride|get_env_int / testParallelConfigDefaultsAndEnvOverride]]

## God Nodes (most connected - your core abstractions)
1. `Lightweight MATLAB Tests` - 32 edges
2. `Soft Margin Scoring` - 21 edges
3. `Lumerical Simulation Project` - 21 edges
4. `Lumerical MODE API` - 19 edges
5. `Stage-2 EDA/Surrogate Search` - 14 edges
6. `testWorkerUsesSharedHelpersAndNoDeadMethods` - 12 edges
7. `open_lumerical_mode` - 11 edges
8. `Checkpoint Contract` - 10 edges
9. `Private Worker Simulation Copies` - 9 edges
10. `Training Data MAT Files` - 9 edges

## Surprising Connections (you probably didn't know these)
- `test_parallel_lumerical_static` --references--> `Lightweight MATLAB Tests`  [EXTRACTED]
  tests\test_parallel_lumerical_static.m → AGENTS.md
- `setupOnce` --references--> `Lightweight MATLAB Tests`  [EXTRACTED]
  tests\test_parallel_lumerical_static.m → AGENTS.md
- `test_stage2_archive_eda_static` --references--> `Lightweight MATLAB Tests`  [EXTRACTED]
  tests\test_stage2_archive_eda_static.m → AGENTS.md
- `initialize_eda_probability` --references--> `Stage-2 EDA/Surrogate Search`  [EXTRACTED]
  src\matlab\BPSO_unified.m → AGENTS.md
- `delete` --references--> `Lumerical MODE API`  [EXTRACTED]
  src\matlab\LumericalWorkerSession.m → AGENTS.md

## Hyperedges (group relationships)
- **Parallel Lumerical Evaluation Flow** — src_matlab_bpso_unified_m, src_matlab_lumericalworkersession_m, src_matlab_make_lumerical_worker_session_m, src_matlab_make_lumerical_worker_sim_file_m, src_matlab_worker_eval_particle_m, src_matlab_open_lumerical_mode_m, src_matlab_set_slot_m, src_matlab_train_out_m, concept_matlab_parallel_toolbox, concept_private_worker_simulation_copies, concept_lumerical_mode_api [INFERRED 0.85]
- **Checkpoint Contract Flow** — src_matlab_bpso_unified_m, src_matlab_checkpoint_var_names_m, tests_test_save_checkpoint_smoke_m, tests_test_evalin_caller_script_m, tests_test_stage2_archive_eda_static_m, concept_checkpoint_contract, concept_result_checkpoints [INFERRED 0.85]
- **Best Structure Verification and Field Plotting Flow** — src_matlab_verify_best_m, src_matlab_load_best_m, src_matlab_plot_field_m, src_matlab_set_slot_m, src_matlab_train_out_m, concept_lumerical_simulation_project, concept_training_data, concept_result_checkpoints [INFERRED 0.85]

## Communities

### Community 0 - "README.md / AGENTS.md"
Cohesion: 0.14
Nodes (11): Checkpoint Contract, Checks, Local Runtime, Scope, PCM Logic-Gate Optimization, Layout, Lightweight Checks, Local Data (+3 more)

### Community 1 - "Stage-2 EDA/Surrogate Search / Checkpoint Contract"
Cohesion: 0.22
Nodes (16): Checkpoint Contract, Stage-2 EDA/Surrogate Search, cleanup_lumerical_constant, predict_surrogate, save_checkpoint, select_candidates_by_surrogate, targeted_local_candidates, checkpoint_var_names (+8 more)

### Community 2 - "Lumerical Simulation Project / Lumerical MODE API"
Cohesion: 0.27
Nodes (11): Lumerical MODE API, Lumerical Simulation Project, Result Checkpoints, append_path_once, cleanupWorkerSimulationFile, doIncrementalSet, LumericalWorkerSession, make_lumerical_worker_session (+3 more)

### Community 3 - "merge_seed_block / fill_stage2_population"
Cohesion: 0.24
Nodes (11): build_record, collect_initial_reeval_candidates, fill_stage2_population, import_existing_results, initialize_eda_probability, merge_seed_block, remove_cached_candidates, resize_col (+3 more)

### Community 4 - "Soft Margin Scoring / archive_guided_candidates"
Cohesion: 0.32
Nodes (8): Soft Margin Scoring, archive_guided_candidates, generate_eda_candidates, rebuild_eval_cache, scale01, store_eval_cache, train_surrogate, update_eda_probability

### Community 5 - "Lightweight MATLAB Tests / testTrainOutReadsOutputPowerData"
Cohesion: 0.5
Nodes (7): Lightweight MATLAB Tests, test_save_checkpoint_smoke, cleanup_mock_dir, setupOnce, test_train_out_lumerical_script, testTrainOutReadsOutputPowerData, write_text_file

### Community 6 - "testWorkerUsesSharedHelpersAndNoDeadMethods / testLumericalScriptsReuseSharedOpenAndPathHelpers"
Cohesion: 0.48
Nodes (6): must_contain, must_not_contain, setupOnce, test_parallel_lumerical_static, testLumericalScriptsReuseSharedOpenAndPathHelpers, testWorkerUsesSharedHelpersAndNoDeadMethods

### Community 7 - "Private Worker Simulation Copies / testBPSOHasParallelLumericalStructure"
Cohesion: 0.43
Nodes (6): MATLAB Parallel Computing Toolbox, Private Worker Simulation Copies, attach_parallel_files, ensure_parallel_pool, refresh_parallel_worker_code, testBPSOHasParallelLumericalStructure

### Community 8 - "evalParticle / softmin_score"
Cohesion: 0.4
Nodes (4): result_from_cache, evalParticle, make_eval_result, softmin_score

### Community 9 - "Training Data MAT Files / run_parallel_eval_batch"
Cohesion: 0.5
Nodes (4): Training Data MAT Files, infer_logic_gate_name, run_parallel_eval_batch, worker_eval_particle

### Community 10 - "testWorkerSimulationFileUsesPrivateCopy / make_lumerical_worker_sim_file"
Cohesion: 0.4
Nodes (4): make_lumerical_worker_sim_file, cleanup_dir, testWorkerSimulationFileUsesPrivateCopy, write_text_file

### Community 11 - "get_env_int / testParallelConfigDefaultsAndEnvOverride"
Cohesion: 0.67
Nodes (2): get_env_int, testParallelConfigDefaultsAndEnvOverride

## Knowledge Gaps
- **7 isolated node(s):** `collect_initial_reeval_candidates`, `remove_cached_candidates`, `validate_parallel_lumerical_workers`, `Scope`, `Layout` (+2 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **Thin community `get_env_int / testParallelConfigDefaultsAndEnvOverride`** (3 nodes): `get_env_int.m`, `get_env_int`, `testParallelConfigDefaultsAndEnvOverride`
  Too small to be a meaningful cluster - may be noise or needs more connections extracted.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Lightweight MATLAB Tests` connect `Lightweight MATLAB Tests / testTrainOutReadsOutputPowerData` to `README.md / AGENTS.md`, `Stage-2 EDA/Surrogate Search / Checkpoint Contract`, `testWorkerUsesSharedHelpersAndNoDeadMethods / testLumericalScriptsReuseSharedOpenAndPathHelpers`, `Private Worker Simulation Copies / testBPSOHasParallelLumericalStructure`, `testWorkerSimulationFileUsesPrivateCopy / make_lumerical_worker_sim_file`, `get_env_int / testParallelConfigDefaultsAndEnvOverride`?**
  _High betweenness centrality (0.126) - this node is a cross-community bridge._
- **Why does `Lumerical Simulation Project` connect `Lumerical Simulation Project / Lumerical MODE API` to `README.md / AGENTS.md`, `merge_seed_block / fill_stage2_population`, `testWorkerUsesSharedHelpersAndNoDeadMethods / testLumericalScriptsReuseSharedOpenAndPathHelpers`, `Private Worker Simulation Copies / testBPSOHasParallelLumericalStructure`, `testWorkerSimulationFileUsesPrivateCopy / make_lumerical_worker_sim_file`?**
  _High betweenness centrality (0.071) - this node is a cross-community bridge._
- **Why does `Lumerical MODE API` connect `Lumerical Simulation Project / Lumerical MODE API` to `README.md / AGENTS.md`, `Stage-2 EDA/Surrogate Search / Checkpoint Contract`, `merge_seed_block / fill_stage2_population`, `Lightweight MATLAB Tests / testTrainOutReadsOutputPowerData`, `testWorkerUsesSharedHelpersAndNoDeadMethods / testLumericalScriptsReuseSharedOpenAndPathHelpers`?**
  _High betweenness centrality (0.059) - this node is a cross-community bridge._
- **What connects `collect_initial_reeval_candidates`, `remove_cached_candidates`, `validate_parallel_lumerical_workers` to the rest of the system?**
  _7 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `README.md / AGENTS.md` be split into smaller, more focused modules?**
  _Cohesion score 0.14 - nodes in this community are weakly interconnected._

## Extraction Notes
- Semantic LLM extraction was not run because no `ANTHROPIC_API_KEY` or `MOONSHOT_API_KEY` is set in this shell.
- The graph uses graphify plus a deterministic MATLAB/Lumerical-aware pass for functions, classes, calls, document headings, path references, and high-confidence architecture edges.
- Token cost is therefore 0 for this run; INFERRED edges are limited to explicit architecture patterns present in the repo docs and code references.
