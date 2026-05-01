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

- `src/matlab/BPSO_unified.m` - two-stage BPSO/memetic optimization loop.
- `src/matlab/verify_best.m` - verifies the current best saved structure.
- `src/matlab/load_best.m` - loads the current best structure into Lumerical MODE.
- `src/matlab/plot_field.m` - plots field data from the current best structure.
- `src/matlab/set_slot.m` and `src/matlab/train_out.m` - Lumerical helper functions.

## Local Data

Large simulation files and generated results are intentionally ignored by Git:

- `*.lms`
- `*.mat`
- `*.mdf`
- `*.log`
- `*.asv`

Keep active checkpoints in `results/`, training datasets in `data/`, and Lumerical files in `structure/`.
