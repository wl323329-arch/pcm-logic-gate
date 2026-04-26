# PCM Logic Gate Optimization

MATLAB and Lumerical MODE scripts for binary-material PCM logic-gate optimization.

## Main scripts

- `BPSO_unified.m` - two-stage BPSO/memetic optimization loop.
- `verify_best.m` - verifies the current best saved structure.
- `load_best.m` - loads the current best structure into Lumerical MODE.
- `set_slot.m` and `train_out.m` - Lumerical helper functions.

## Data not committed

Large simulation files and generated results are intentionally ignored:

- `*.lms`
- `*.mat`
- `*.log`
- `*.asv`

Keep local result checkpoints such as `record_unified.mat` and named gate results outside Git.
