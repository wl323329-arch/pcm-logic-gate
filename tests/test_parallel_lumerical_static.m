function tests = test_parallel_lumerical_static()
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
project_dir = fileparts(fileparts(mfilename('fullpath')));
src_dir = fullfile(project_dir, 'src', 'matlab');
addpath(src_dir);
testCase.TestData.project_dir = project_dir;
testCase.TestData.script_path = fullfile(src_dir, 'BPSO_unified.m');
end

function testParallelConfigDefaultsAndEnvOverride(testCase)
old_value = getenv('PCM_LUM_WORKERS');
cleanup = onCleanup(@() setenv('PCM_LUM_WORKERS', old_value));

setenv('PCM_LUM_WORKERS', '');
verifyEqual(testCase, get_env_int('PCM_LUM_WORKERS', 4), 4);

setenv('PCM_LUM_WORKERS', '8');
verifyEqual(testCase, get_env_int('PCM_LUM_WORKERS', 4), 8);

setenv('PCM_LUM_WORKERS', '16');
verifyEqual(testCase, get_env_int('PCM_LUM_WORKERS', 4), 16);

setenv('PCM_LUM_WORKERS', '0');
verifyError(testCase, @() get_env_int('PCM_LUM_WORKERS', 4), 'get_env_int:InvalidInteger');

setenv('PCM_LUM_WORKERS', 'abc');
verifyError(testCase, @() get_env_int('PCM_LUM_WORKERS', 4), 'get_env_int:InvalidInteger');
end

function testBPSOHasParallelLumericalStructure(testCase)
txt = fileread(testCase.TestData.script_path);

must_contain(txt, 'PARALLEL_WORKERS = get_env_int(''PCM_LUM_WORKERS'', 4)');
must_contain(txt, 'ensure_parallel_pool(PARALLEL_WORKERS)');
must_contain(txt, 'parallel.pool.Constant');
must_contain(txt, 'validate_parallel_lumerical_workers');
must_contain(txt, 'updateAttachedFiles(pool)');
must_contain(txt, 'parfevalOnAll(pool, @refresh_parallel_worker_code, 0)');
must_contain(txt, 'run_parallel_eval_batch');
must_contain(txt, 'make_lumerical_worker_session');
must_contain(txt, 'worker_eval_particle');
must_contain(txt, 'parfor');
must_contain(txt, 'open_lumerical_mode(SIM_FILE)');

if contains(txt, 'eval_particle(h, L, eval_cache, last_bits')
    error('BPSO_unified.m still uses the old single-handle eval_particle path.');
end
end

function testWorkerUsesSharedHelpersAndNoDeadMethods(testCase)
src_dir = fullfile(testCase.TestData.project_dir, 'src', 'matlab');
worker_path = fullfile(src_dir, 'LumericalWorkerSession.m');
worker_txt = fileread(worker_path);
script_txt = fileread(testCase.TestData.script_path);

verifyEqual(testCase, exist(fullfile(src_dir, 'softmin_score.m'), 'file'), 2);
verifyEqual(testCase, exist(fullfile(src_dir, 'append_path_once.m'), 'file'), 2);
verifyEqual(testCase, exist(fullfile(src_dir, 'make_eval_result.m'), 'file'), 2);
verifyEqual(testCase, exist(fullfile(src_dir, 'open_lumerical_mode.m'), 'file'), 2);
verifyEqual(testCase, exist(fullfile(src_dir, 'refresh_parallel_worker_code.m'), 'file'), 2);

must_not_contain(worker_txt, 'function resetLastBits');
must_not_contain(worker_txt, 'softmin_score_local');
must_not_contain(worker_txt, 'function result = make_eval_result');
must_contain(worker_txt, 'softmin_score(CR_each, tau, lambda_balance)');
must_contain(worker_txt, 'append_path_once(getenv(''PATH''), lum_bin)');
must_not_contain(script_txt, 'function F = softmin_score(CR_each, tau, lambda_balance)');
must_not_contain(script_txt, 'function h = open_lumerical_handle(sim_file)');
must_contain(script_txt, 'make_eval_result(cached.n_right');
must_contain(script_txt, 'open_lumerical_mode(SIM_FILE)');
must_contain(script_txt, 'refresh_parallel_worker_code.m');
end

function testLumericalScriptsReuseSharedOpenAndPathHelpers(testCase)
src_dir = fullfile(testCase.TestData.project_dir, 'src', 'matlab');
script_names = {'BPSO_unified.m', 'load_best.m', 'plot_field.m', 'verify_best.m'};

for k = 1:numel(script_names)
    txt = fileread(fullfile(src_dir, script_names{k}));
    must_contain(txt, 'append_path_once(getenv(''PATH''), LUM_BIN)');
    must_not_contain(txt, 'setenv(''PATH'', [getenv(''PATH'') '';'' LUM_BIN])');
end

for k = 1:numel(script_names)
    txt = fileread(fullfile(src_dir, script_names{k}));
    must_contain(txt, 'open_lumerical_mode(SIM_FILE)');
    must_not_contain(txt, 'appopen(''mode'')');
end
end

function must_contain(txt, pattern)
if ~contains(txt, pattern)
    error('Expected BPSO_unified.m to contain: %s', pattern);
end
end

function must_not_contain(txt, pattern)
if contains(txt, pattern)
    error('Did not expect text to contain: %s', pattern);
end
end
