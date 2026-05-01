# PCM Logic Gate Optimization

MATLAB and Lumerical MODE scripts for binary-material PCM logic-gate optimization.

## Layout

- `src/matlab/` - active MATLAB optimization, verification, loading, plotting, and helper functions.
- `structure/` - local Lumerical MODE structure files and generated field data.
- `data/` - training input and target data.
- `results/` - current optimization checkpoints and named gate results.
- `results/archive/` - older result files kept for reference.
- `scripts/lumerical/` - Lumerical script helpers.
- `tests/` - lightweight MATLAB structural checks.
- `legacy/` - older scripts kept for reference, not part of the active workflow.

## Main Scripts

- `src/matlab/BPSO_unified.m` - two-stage BPSO/memetic optimization loop with parallel Lumerical evaluations.
- `src/matlab/verify_best.m` - verifies the current best saved structure.
- `src/matlab/load_best.m` - loads the current best structure into Lumerical MODE.
- `src/matlab/plot_field.m` - plots field data from the current best structure.
- `src/matlab/set_slot.m`, `src/matlab/train_out.m`, and `src/matlab/checkpoint_var_names.m` - Lumerical and checkpoint helper functions.

## Runtime Configuration

`src/matlab/BPSO_unified.m` uses MATLAB Parallel Computing Toolbox to run multiple independent Lumerical MODE sessions. The default is 4 concurrent simulations.

Override the worker count before running the optimizer:

```matlab
setenv('PCM_LUM_WORKERS', '8');   % or 16 if licenses and hardware allow it
run('src/matlab/BPSO_unified.m');
```

The optimizer requires the requested number of MODE sessions to start successfully. Each worker copies `structure/logic_mode.lms` to a private temporary directory and opens that copy, so concurrent layout edits do not trigger MODE's "project file has been modified on disk" prompt. If any worker cannot open or load its private project copy, the run stops instead of silently using fewer workers.

## Lightweight Checks

Run the non-Lumerical MATLAB checks with:

```matlab
results = runtests('tests');
assert(all([results.Passed]));
```

These tests cover the stage-2 static structure, parallel configuration, private worker simulation-file copies, and checkpoint save-field consistency. Full optimization and verification scripts still require the local Lumerical MODE install and simulation files.

## Local Data

Large simulation files and generated results are intentionally ignored by Git:

- `*.lms`
- `*.mat`
- `*.mdf`
- `*.log`
- `*.asv`

Keep active checkpoints in `results/`, training datasets in `data/`, and Lumerical files in `structure/`.
