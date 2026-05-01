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
must_contain(txt, 'run_parallel_eval_batch');
must_contain(txt, 'make_lumerical_worker_session');
must_contain(txt, 'worker_eval_particle');
must_contain(txt, 'parfor');
must_contain(txt, 'appopen(''mode'')');

if contains(txt, 'eval_particle(h, L, eval_cache, last_bits')
    error('BPSO_unified.m still uses the old single-handle eval_particle path.');
end
end

function must_contain(txt, pattern)
if ~contains(txt, pattern)
    error('Expected BPSO_unified.m to contain: %s', pattern);
end
end
