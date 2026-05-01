function test_stage2_archive_eda_static()
% Lightweight structural checks for the stage-2 Archive + Surrogate + EDA path.
project_dir = fileparts(fileparts(mfilename('fullpath')));
script_path = fullfile(project_dir, 'src', 'matlab', 'BPSO_unified.m');
txt = fileread(script_path);

must_contain(txt, 'METRIC_VERSION = 3');
must_contain(txt, 'cache_CR_each');
must_contain(txt, 'cache_F_soft');
must_contain(txt, 'cache_worst_idx');
must_contain(txt, 'cache_is_full');
must_contain(txt, 'generate_eda_candidates');
must_contain(txt, 'select_candidates_by_surrogate');
must_contain(txt, 'select_candidates_by_surrogate(cand, surrogate, ym, K_TRUE, stall_gen)');
must_contain(txt, 'function selected = select_candidates_by_surrogate(cand, surrogate, ym, K_TRUE, stall_gen)');
must_contain(txt, 'hd_weight = 0.03 + 0.02 * min(stall_gen, 8)');
must_contain(txt, 'max_flip = min(d, 4 + min(stall_gen, 8))');
must_contain(txt, 'archive_guided_candidates');
must_contain(txt, 'cache_CR_worst, cache_F_soft, cache_is_full');
must_contain(txt, 'score = cr_score + 0.35 * soft_score');
must_contain(txt, 'n_archive = round(0.20 * N_CAND)');
must_contain(txt, 'targeted_local_candidates');
must_contain(txt, 'targeted_local_candidates(ym, surrogate, d, LOCAL_1BIT_EVAL,');
must_contain(txt, 'LOCAL_2BIT_EVAL, stall_gen)');
must_contain(txt, 'function selected_local = targeted_local_candidates(ym, surrogate, d, K1, K2_TOP_BITS, K2, stall_gen)');
must_contain(txt, 'if stall_gen >= 5');
must_contain(txt, 'eval_3bit');
must_contain(txt, 'softmin_score');
must_contain(txt, 'full_eval');
must_contain(txt, 'TreeBagger');

if contains(txt, 'x = build_next_population(ym, xm, fxm')
    error('Stage 2 still calls the old BPSO/memetic build_next_population path.');
end

fprintf('stage2 archive/EDA static checks passed\n');
end

function must_contain(txt, pattern)
if ~contains(txt, pattern)
    error('Expected BPSO_unified.m to contain: %s', pattern);
end
end
