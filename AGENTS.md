# Project Notes for Agents

## Scope

This repository contains MATLAB and Lumerical MODE scripts for PCM logic-gate optimization. Active MATLAB code lives in `src/matlab/`; `legacy/` is reference-only.

## Local Runtime

- MATLAB R2024b is available locally.
- MATLAB Parallel Computing Toolbox is used by `src/matlab/BPSO_unified.m` for parallel Lumerical evaluation.
- Lumerical MODE paths are currently hard-coded in the active scripts as `D:\Program Files\Lumerical\v231\bin` and `D:\Program Files\Lumerical\v231\api\matlab`.
- `src/matlab/BPSO_unified.m` defaults to 4 concurrent MODE sessions. Override with `PCM_LUM_WORKERS` before running the optimizer, for example `setenv('PCM_LUM_WORKERS','8')`.
- Parallel startup is fail-fast: if the configured number of MODE sessions cannot open and load `structure/logic_mode.lms`, the optimizer stops instead of silently reducing concurrency.
- Large `.mat`, `.lms`, `.mdf`, and `.log` files are intentionally ignored unless already tracked.

## Checks

Use this for lightweight validation that does not open Lumerical:

```matlab
results = runtests('tests');
assert(all([results.Passed]));
```

Do not run `src/matlab/BPSO_unified.m`, `verify_best.m`, `load_best.m`, or `plot_field.m` as part of routine validation unless the user explicitly wants a Lumerical-backed run. The lightweight tests include static checks for the parallel configuration and do not open Lumerical.

## Checkpoint Contract

`src/matlab/checkpoint_var_names.m` is the canonical checkpoint field list used by `BPSO_unified.m` and the tests. Update that helper and the related tests together when adding or removing persisted state.
