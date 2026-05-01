function tests = test_save_checkpoint_smoke()
tests = functiontests(localfunctions);
end

function testWritesCanonicalCheckpoint(testCase)
% Smoke test: verify the checkpoint helper field list writes a valid MAT file.
project_dir = fileparts(fileparts(mfilename('fullpath')));
src_dir = fullfile(project_dir, 'src', 'matlab');
addpath(src_dir);

workspace = make_checkpoint_workspace();
tmp_file = fullfile(tempdir, 'smoke_checkpoint.mat');
if exist(tmp_file, 'file')
    delete(tmp_file);
end
cleanup = onCleanup(@() delete_if_exists(tmp_file));

var_names = checkpoint_var_names();
S = struct();
S.metric_version = 3;
for k = 1:numel(var_names)
    S.(var_names{k}) = workspace.(var_names{k});
end
save(tmp_file, '-struct', 'S', '-v7.3');

verifyEqual(testCase, exist(tmp_file, 'file'), 2);

L = load(tmp_file);
expected = [{'metric_version'}, var_names];
verifyEmpty(testCase, setdiff(expected, fieldnames(L)));
verifyEmpty(testCase, setdiff(fieldnames(L), expected));
verifyEqual(testCase, L.metric_version, 3);
verifyEqual(testCase, L.x, workspace.x);
verifyEqual(testCase, L.cache_is_full, workspace.cache_is_full);
verifyEqual(testCase, L.p_eda, workspace.p_eda);

fprintf('save_checkpoint smoke test passed: %d fields written and verified\n', numel(expected));
end

function workspace = make_checkpoint_workspace()
workspace.phase = 2;
workspace.seed_pool = zeros(0, 49);
workspace.seed_pool_cr = zeros(0, 1);
workspace.record = zeros(16, 49*4 + 6);
workspace.record_time = repmat(string(datetime), 16, 1);
workspace.x = double(rand(16, 49) > 0.5);
workspace.v = zeros(16, 49);
workspace.xm = workspace.x;
workspace.ym = workspace.x(1, :);
workspace.fxm = -inf(16, 1);
workspace.fym = -inf;
workspace.n_right = zeros(16, 1);
workspace.CR_worst = zeros(16, 1);
workspace.loss_mse = zeros(16, 1);
workspace.particle_time_sec = nan(16, 1);
workspace.iter = 1;
workspace.num = 1;
workspace.cache_bits = zeros(0, 49);
workspace.cache_n_right = zeros(0, 1);
workspace.cache_CR_worst = zeros(0, 1);
workspace.cache_loss_mse = zeros(0, 1);
workspace.cache_CR_each = zeros(0, 4);
workspace.cache_F_soft = zeros(0, 1);
workspace.cache_worst_idx = zeros(0, 1);
workspace.cache_is_full = false(0, 1);
workspace.stage2_target_iter = 10;
workspace.stall_gen = 0;
workspace.fym_prev = -inf;
workspace.p_eda = 0.5 * ones(1, 49);
workspace.best_CR_each = nan(1, 4);
workspace.best_worst_idx = 0;
workspace.init_reeval_queue = zeros(0, 49);
end

function delete_if_exists(file_path)
if exist(file_path, 'file')
    delete(file_path);
end
end
