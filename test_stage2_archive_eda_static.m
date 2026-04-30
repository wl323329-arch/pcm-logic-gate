function test_stage2_archive_eda_static()
% Lightweight structural checks for the stage-2 Archive + Surrogate + EDA path.
script_path = fullfile(fileparts(mfilename('fullpath')), 'BPSO_unified.m');
txt = fileread(script_path);

must_contain(txt, 'METRIC_VERSION = 3');
must_contain(txt, 'cache_CR_each');
must_contain(txt, 'cache_F_soft');
must_contain(txt, 'cache_worst_idx');
must_contain(txt, 'cache_is_full');
must_contain(txt, 'generate_eda_candidates');
must_contain(txt, 'select_candidates_by_surrogate');
must_contain(txt, 'targeted_local_candidates');
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
