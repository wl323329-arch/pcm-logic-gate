% Smoke script: 验证 BPSO_unified.m 用的"script + local function + evalin('caller')"模式真的能跨层抓变量。
% 这是 save_checkpoint helper 依赖的核心机制。

project_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(project_dir, 'src', 'matlab'));

% 模拟 BPSO_unified.m 的 base workspace
METRIC_VERSION = 3;
phase = 2;
seed_pool = zeros(0, 49);
seed_pool_cr = zeros(0, 1);
record = zeros(16, 49*4 + 6);
record_time = repmat(string(datetime), 16, 1);
x = double(rand(16, 49) > 0.5);
v = zeros(16, 49);
xm = x;
ym = x(1, :);
fxm = -inf(16, 1);
fym = -inf;
n_right = zeros(16, 1);
CR_worst = zeros(16, 1);
loss_mse = zeros(16, 1);
particle_time_sec = nan(16, 1);
iter = 1;
num = 1;
cache_bits = zeros(0, 49);
cache_n_right = zeros(0, 1);
cache_CR_worst = zeros(0, 1);
cache_loss_mse = zeros(0, 1);
cache_CR_each = zeros(0, 4);
cache_F_soft = zeros(0, 1);
cache_worst_idx = zeros(0, 1);
cache_is_full = false(0, 1);
stage2_target_iter = 10;
stall_gen = 0;
fym_prev = -inf;
p_eda = 0.5 * ones(1, 49);
best_CR_each = nan(1, 4);
best_worst_idx = 0;
init_reeval_queue = zeros(0, 49);

tmp_file = fullfile(tempdir, 'evalin_caller_test.mat');
if exist(tmp_file, 'file'); delete(tmp_file); end

% 调用 local function（这就是 BPSO_unified.m 用的同一种模式）
save_checkpoint(tmp_file);

L = load(tmp_file);
assert(L.metric_version == 3, 'metric_version not picked up via evalin');
assert(isequal(L.x, x), 'x not picked up via evalin');
assert(isequal(L.cache_is_full, cache_is_full), 'cache_is_full not picked up');
assert(isequal(L.p_eda, p_eda), 'p_eda not picked up');
expected = [{'metric_version'}, checkpoint_var_names()];
assert(numel(fieldnames(L)) == numel(expected), ...
    sprintf('expected %d fields, got %d', numel(expected), numel(fieldnames(L))));

delete(tmp_file);
fprintf('evalin(''caller'') across script->local function: PASS (%d fields)\n', numel(fieldnames(L)));

%% --- 与 BPSO_unified.m 中字面相同的 helper（复制粘贴） ---
function save_checkpoint(save_file)
    var_names = checkpoint_var_names();
    S = struct();
    S.metric_version = evalin('caller', 'METRIC_VERSION');
    for k = 1:numel(var_names)
        S.(var_names{k}) = evalin('caller', var_names{k});
    end
    save(save_file, '-struct', 'S', '-v7.3');
end
