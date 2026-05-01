clearvars; close all; clc;

%% 路径设置
LUM_BIN  = 'D:\Program Files\Lumerical\v231\bin';
LUM_API  = 'D:\Program Files\Lumerical\v231\api\matlab';
SCRIPT_DIR = fileparts(mfilename('fullpath'));
if isempty(SCRIPT_DIR)
    SCRIPT_DIR = pwd;
end
PROJECT_DIR = fileparts(fileparts(SCRIPT_DIR));
DATA_DIR = fullfile(PROJECT_DIR, 'data');
RESULTS_DIR = fullfile(PROJECT_DIR, 'results');
STRUCTURE_DIR = fullfile(PROJECT_DIR, 'structure');
SIM_FILE = fullfile(STRUCTURE_DIR, 'logic_mode.lms');

setenv('PATH', append_path_once(getenv('PATH'), LUM_BIN));
addpath(LUM_API);
addpath(SCRIPT_DIR);

assert(exist(SIM_FILE, 'file') == 2, 'Simulation file not found: %s', SIM_FILE);
assert(exist(fullfile(DATA_DIR, 'train_data.mat'), 'file') == 2, 'Missing train_data.mat in %s', DATA_DIR);
assert(exist(fullfile(DATA_DIR, 'train_target.mat'), 'file') == 2, 'Missing train_target.mat in %s', DATA_DIR);
if exist(RESULTS_DIR, 'dir') ~= 7
    mkdir(RESULTS_DIR);
end

%% 加载数据集及初始化
load(fullfile(DATA_DIR, 'train_data.mat'));
load(fullfile(DATA_DIR, 'train_target.mat'));

size_train  = size(train_data);
size_target = size(train_target);
RESULT_TAG = infer_logic_gate_name(train_data, train_target);

train_data = train_data * pi;   % 将训练集数据加载到相位上

%% 参数设置
N1  = 5000;              % 阶段1种群规模
N2  = 16;                % stage-2 true evaluations per generation
d   = 49;                % 49个孔洞的二进制材料变量
ger2 = 10;               % 首次运行阶段2基础代数
N_SEED_TARGET = 25;       % 阶段1需要找到的全对结构数

CONTINUE_FROM_EXISTING_RESULTS = true;  % 自动导入 record_unified*.mat 作为阶段2种子
START_STAGE2_WITH_IMPORTED_SEEDS = true;
STAGE2_EXTRA_GENERATIONS_ON_RESUME = 20;
MAX_IMPORTED_SEEDS = 200;
N_INIT_REEVAL = 80;
N_CAND = 5000;
K_TRUE = N2;
ELITE_FRAC = 0.15;
rho = 0.25;
p_min = 0.05;
p_max = 0.95;
tau = 2.0;
lambda_balance = 0.05;
LOCAL_1BIT_EVAL = 10;
LOCAL_2BIT_TOP_BITS = 12;
LOCAL_2BIT_EVAL = 8;
SURROGATE_MIN_SAMPLES = 60;
STALL_RESET_GEN = 4;
PARALLEL_WORKERS = get_env_int('PCM_LUM_WORKERS', 4);

% 材料名（增量 set_slot 用）
matA = 'A_Sb2Se3';   % 非晶态
matB = 'B_Sb2Se3';   % 晶态

SAVE_FILE = fullfile(RESULTS_DIR, 'record_unified.mat');
NAMED_SAVE_FILE = fullfile(RESULTS_DIR, ['record_unified' RESULT_TAG '.mat']);
RESULT_PATTERNS = {SAVE_FILE, NAMED_SAVE_FILE, fullfile(RESULTS_DIR, ['record_unified' RESULT_TAG '_*.mat'])};
METRIC_VERSION = 3;  % v3 = full margins + soft archive score; best still uses true CR_worst

%% 共享优化基础设施
eval_cache = containers.Map('KeyType','char','ValueType','any');
stat_cache_hit   = 0;
stat_cache_total = 0;
stat_early_stop  = 0;
cache_bits = zeros(0, d);
cache_n_right = zeros(0, 1);
cache_CR_worst = zeros(0, 1);
cache_loss_mse = zeros(0, 1);
cache_CR_each = zeros(0, size_train(1));
cache_F_soft = zeros(0, 1);
cache_worst_idx = zeros(0, 1);
cache_is_full = false(0, 1);
stage2_target_iter = ger2;
stall_gen = 0;
fym_prev = -inf;
p_eda = 0.5 * ones(1, d);
best_CR_each = nan(1, size_train(1));
best_worst_idx = 0;
init_reeval_queue = zeros(0, d);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% 断点续跑 / 首次运行初始化
resume_ok = false;

if exist(SAVE_FILE, 'file')
    try
        S = load(SAVE_FILE);

        needed_vars = {'phase','x','v','xm','ym','fxm','fym',...
                       'n_right','CR_worst','loss_mse',...
                       'record','record_time','iter','num',...
                       'particle_time_sec','seed_pool','seed_pool_cr'};
        has_all = true;
        for ii = 1:length(needed_vars)
            if ~isfield(S, needed_vars{ii})
                has_all = false;
                break;
            end
        end

        if has_all
            % 版本检查：防止新旧指标混用
            if ~isfield(S, 'metric_version') || S.metric_version ~= METRIC_VERSION
                old_ver = 1;
                if isfield(S, 'metric_version'), old_ver = S.metric_version; end
                fprintf('[WARN] Checkpoint 使用旧指标 (v%d)，当前需要 v%d。忽略旧存档，重新开始。\n', ...
                    old_ver, METRIC_VERSION);
                has_all = false;
            end
        end

        if has_all
            phase = S.phase;
            x = S.x;
            v = S.v;
            xm = S.xm;
            ym = S.ym;
            fxm = S.fxm;
            fym = S.fym;
            n_right = S.n_right;
            CR_worst = S.CR_worst;
            loss_mse = S.loss_mse;
            record = S.record;
            record_time = S.record_time;
            iter = S.iter;
            num = S.num;
            particle_time_sec = S.particle_time_sec;
            seed_pool = S.seed_pool;
            seed_pool_cr = S.seed_pool_cr;
            if isfield(S, 'cache_bits'), cache_bits = S.cache_bits; end
            if isfield(S, 'cache_n_right'), cache_n_right = S.cache_n_right; end
            if isfield(S, 'cache_CR_worst'), cache_CR_worst = S.cache_CR_worst; end
            if isfield(S, 'cache_loss_mse'), cache_loss_mse = S.cache_loss_mse; end
            if isfield(S, 'cache_CR_each'), cache_CR_each = S.cache_CR_each; end
            if isfield(S, 'cache_F_soft'), cache_F_soft = S.cache_F_soft; end
            if isfield(S, 'cache_worst_idx'), cache_worst_idx = S.cache_worst_idx; end
            if isfield(S, 'cache_is_full'), cache_is_full = S.cache_is_full; end
            if isfield(S, 'stage2_target_iter'), stage2_target_iter = S.stage2_target_iter; end
            if isfield(S, 'stall_gen'), stall_gen = S.stall_gen; end
            if isfield(S, 'fym_prev'), fym_prev = S.fym_prev; end
            if isfield(S, 'p_eda'), p_eda = S.p_eda; end
            if isfield(S, 'best_CR_each'), best_CR_each = S.best_CR_each; end
            if isfield(S, 'best_worst_idx'), best_worst_idx = S.best_worst_idx; end
            if isfield(S, 'init_reeval_queue'), init_reeval_queue = S.init_reeval_queue; end
            [cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full] = ...
                normalize_archive_fields(cache_bits, cache_n_right, cache_CR_worst, ...
                                         cache_CR_each, cache_F_soft, cache_worst_idx, ...
                                         cache_is_full, size_train(1), tau, lambda_balance);
            eval_cache = rebuild_eval_cache(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                            cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full);

            % 尺寸校验
            if phase == 1
                N_cur = N1;
            else
                N_cur = N2;
                stage2_target_iter = max(stage2_target_iter, iter + STAGE2_EXTRA_GENERATIONS_ON_RESUME);
            end

            if isequal(size(x,1), N_cur) && size(x,2) == d ...
                    && size(record_time,1) == N_cur
                resume_ok = true;
                fprintf('[INFO] 检测到 %s，继续运行。\n', SAVE_FILE);
                fprintf('[INFO] phase = %d, iter = %d, num = %d, 种子数 = %d\n', ...
                    phase, iter, num, size(seed_pool, 1));
            end
        end
    catch
        resume_ok = false;
    end
end

if ~resume_ok
    [seed_pool, seed_pool_cr] = import_existing_results(RESULT_PATTERNS, d, size_train(1), MAX_IMPORTED_SEEDS);
    init_reeval_queue = collect_initial_reeval_candidates(RESULT_PATTERNS, d, N_INIT_REEVAL);

    if CONTINUE_FROM_EXISTING_RESULTS && START_STAGE2_WITH_IMPORTED_SEEDS && ~isempty(seed_pool)
        phase = 2;
        [x, v, xm, fxm, fym, ym, n_right, CR_worst, loss_mse, ...
         particle_time_sec, record, record_time] = ...
            init_memetic_population(seed_pool, seed_pool_cr, N2, d);
        stage2_target_iter = ger2 + STAGE2_EXTRA_GENERATIONS_ON_RESUME;
        fprintf('[INFO] 已导入 %d 个历史全对结构，直接进入阶段2继续优化。\n', size(seed_pool, 1));
    else
        phase = 1;
        seed_pool    = zeros(0, d);   % 存放发现的全对结构
        seed_pool_cr = zeros(0, 1);   % 每个种子对应的 CR_worst

        % 阶段1初始化
        x = double(rand(N1, d) > 0.5);
        v = randn(N1, d);  % 仅保留 record 兼容字段
        xm = x;
        ym = zeros(1, d);
        fxm = -inf(N1, 1);
        fym = -inf;
        n_right  = zeros(N1, 1);
        CR_worst = zeros(N1, 1);
        loss_mse = zeros(N1, 1);
        particle_time_sec = nan(N1, 1);

        record = build_record(x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse);
        record_time = repmat(string(datetime), N1, 1);
    end

    iter = 1;
    num  = 1;
    p_eda = initialize_eda_probability(seed_pool, d, p_min, p_max);
end

%% 启动并行 Lumerical worker
path(path, LUM_API);
h = [];
lum_workers = [];

%% ==================== 阶段1: 发现 ====================
try
pool = ensure_parallel_pool(PARALLEL_WORKERS);
attach_parallel_files(pool, SCRIPT_DIR);
lum_workers = parallel.pool.Constant( ...
    @() make_lumerical_worker_session(SIM_FILE, LUM_BIN, LUM_API, matA, matB, d), ...
    @close_lumerical_worker_session);
validate_parallel_lumerical_workers(lum_workers, PARALLEL_WORKERS);
fprintf('[INFO] Parallel Lumerical workers ready: %d MODE sessions.\n', PARALLEL_WORKERS);

if phase == 1
    % 阶段1 是单遍随机扫描（ger=1），不做速度/位置迭代更新
    fprintf('========== 阶段1: 发现全对结构 (N=%d) ==========\n', N1);

    while num <= N1
        batch_start = num;
        batch_end = min(N1, batch_start + PARALLEL_WORKERS - 1);
        batch_idx = batch_start:batch_end;
        batch_results = run_parallel_eval_batch(lum_workers, x(batch_idx,:), eval_cache, ...
            train_data, train_target, size_train, size_target, tau, lambda_balance, false);

        for bi = 1:numel(batch_idx)
            idx = batch_idx(bi);
            r = batch_results{bi};
            stat_cache_total = stat_cache_total + 1;

            n_right(idx,1)  = r.n_right;
            CR_worst(idx,1) = r.CR_worst;
            loss_mse(idx,1) = r.loss_mse;

            if r.cache_hit
                stat_cache_hit = stat_cache_hit + 1;
            end
            if r.early_stopped
                stat_early_stop = stat_early_stop + 1;
            end
            if ~r.cache_hit
                eval_cache = store_eval_cache(eval_cache, x(idx,:), r);
                [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                 cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full] = ...
                    append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                        cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full, ...
                                        x(idx,:), r.n_right, r.CR_worst, r.loss_mse, r.CR_each, r.F_soft, ...
                                        r.worst_idx, r.is_full);
            end

            fit_now = n_right(idx,1) - loss_mse(idx,1);

            if fit_now > fxm(idx,1)
                fxm(idx,1) = fit_now;
                xm(idx,:) = x(idx,:);
            end

            if fit_now > fym
                fym = fit_now;
                ym = x(idx,:);
            end

            if r.n_right == size_train(1)
                old_seed_count = size(seed_pool, 1);
                [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, x(idx,:), r.CR_worst, MAX_IMPORTED_SEEDS);
                if size(seed_pool, 1) > old_seed_count
                    fprintf('[发现] 第 %d 个全对结构: 粒子 %d, CR_worst = %.4f dB\n', ...
                        size(seed_pool,1), idx, r.CR_worst);
                end
            end

            particle_time_sec(idx,1) = r.duration_sec;

            done_idx = find(~isnan(particle_time_sec));
            avg_dt   = mean(particle_time_sec(done_idx));
            remain_num  = N1 - idx;
            eta_sec     = remain_num * avg_dt / max(PARALLEL_WORKERS, 1);
            finish_time = datetime('now') + seconds(eta_sec);
            finish_time.Format = 'yyyy-MM-dd HH:mm:ss';
            num_right4  = sum(n_right(1:idx) == size_train(1));
            cache_rate  = stat_cache_hit / max(stat_cache_total, 1) * 100;
            estop_rate  = stat_early_stop / max(stat_cache_total - stat_cache_hit, 1) * 100;

            fprintf('[阶段1] 粒子 %d / %d | %.2f s | 均 %.2f s | 全对 %d | 种子 %d/%d | parallel=%d\n', ...
                idx, N1, r.duration_sec, avg_dt, num_right4, size(seed_pool,1), N_SEED_TARGET, PARALLEL_WORKERS);
            fprintf('  缓存 %.1f%% (%d/%d) | 早停 %.1f%% | 预计 %s\n', ...
                cache_rate, stat_cache_hit, stat_cache_total, estop_rate, ...
                char(finish_time));

            record = build_record(x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse); %#ok<NASGU>
            record_time(idx,1) = string(datetime);
            num = idx + 1;
            save_checkpoint(SAVE_FILE);
        end

        if size(seed_pool, 1) >= N_SEED_TARGET
            fprintf('\n[阶段切换] 已收集 %d 个全对结构，切换到优化阶段。\n\n', ...
                size(seed_pool, 1));
            break;
        end
    end

    if size(seed_pool, 1) < N_SEED_TARGET
        fprintf('[警告] 阶段1结束，仅找到 %d 个全对结构（目标 %d），仍进入阶段2。\n', ...
            size(seed_pool, 1), N_SEED_TARGET);
    end

    % 切换到阶段2
    phase = 2;

    %% 阶段2初始化：从 seed_pool 填充 N2 粒子
    n_seed = size(seed_pool, 1);
    assert(n_seed > 0, '未找到任何全对结构，无法进入阶段2。');

    [x, v, xm, fxm, fym, ym, n_right, CR_worst, loss_mse, ...
     particle_time_sec, record, record_time] = ...
        init_memetic_population(seed_pool, seed_pool_cr, N2, d);
    p_eda = initialize_eda_probability(seed_pool, d, p_min, p_max);

    iter = 1;
    num  = 1;

    save_checkpoint(SAVE_FILE);
end

%% ==================== 阶段2: 优化 ====================
if phase == 2
    fprintf('========== 阶段2: Archive + Surrogate + EDA (K_TRUE=%d, target_iter=%d) ==========\n', ...
        K_TRUE, stage2_target_iter);

    while iter <= stage2_target_iter
        if num == 1
            if size(cache_bits, 1) >= SURROGATE_MIN_SAMPLES
                surrogate = train_surrogate(cache_bits, cache_F_soft);
            else
                surrogate = [];
            end

            init_reeval_queue = remove_cached_candidates(init_reeval_queue, eval_cache);
            if ~isempty(init_reeval_queue)
                take_init = min(K_TRUE, size(init_reeval_queue, 1));
                selected = init_reeval_queue(1:take_init, :);
                init_reeval_queue = init_reeval_queue(take_init+1:end, :);
                cand = selected;
                fprintf('[archive bootstrap] queued %d historical candidates for full v3 evaluation.\n', take_init);
            else
                cand = generate_eda_candidates(p_eda, ym, d, N_CAND, stall_gen, cache_bits, cache_CR_worst, cache_F_soft, cache_is_full);
                cand = remove_cached_candidates(cand, eval_cache);
                if ~isempty(surrogate)
                    selected = select_candidates_by_surrogate(cand, surrogate, ym, K_TRUE, stall_gen);
                else
                    selected = cand(1:min(K_TRUE, size(cand,1)), :);
                end
                if isempty(selected)
                    selected = generate_eda_candidates(p_eda, ym, d, K_TRUE, stall_gen, cache_bits, cache_CR_worst, cache_F_soft, cache_is_full);
                end
            end
            x = fill_stage2_population(selected, p_eda, ym, N2, d, eval_cache);
            v = zeros(N2, d);
            fprintf('[EDA] iter %d generated %d unique candidates, selected %d true evaluations.\n', ...
                iter, size(cand, 1), size(selected, 1));
        end

        while num <= N2
            batch_start = num;
            batch_end = min(N2, batch_start + PARALLEL_WORKERS - 1);
            batch_idx = batch_start:batch_end;
            batch_results = run_parallel_eval_batch(lum_workers, x(batch_idx,:), eval_cache, ...
                train_data, train_target, size_train, size_target, tau, lambda_balance, true);

            for bi = 1:numel(batch_idx)
                idx = batch_idx(bi);
                r = batch_results{bi};
                stat_cache_total = stat_cache_total + 1;

                n_right(idx,1)  = r.n_right;
                CR_worst(idx,1) = r.CR_worst;
                loss_mse(idx,1) = r.loss_mse;

                if r.cache_hit
                    stat_cache_hit = stat_cache_hit + 1;
                end
                if r.early_stopped
                    stat_early_stop = stat_early_stop + 1;
                end
                if ~r.cache_hit
                    eval_cache = store_eval_cache(eval_cache, x(idx,:), r);
                    [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                     cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full] = ...
                        append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                            cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full, ...
                                            x(idx,:), r.n_right, r.CR_worst, r.loss_mse, r.CR_each, r.F_soft, ...
                                            r.worst_idx, r.is_full);
                end

                if r.n_right == size_train(1) && r.CR_worst > fxm(idx)
                    fxm(idx) = r.CR_worst;
                    xm(idx,:) = x(idx,:);
                    if fxm(idx) > fym
                        fym = fxm(idx);
                        ym = xm(idx,:);
                        best_CR_each = r.CR_each(:)';
                        best_worst_idx = r.worst_idx;
                    end
                end
                if r.n_right == size_train(1)
                    [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, x(idx,:), r.CR_worst, MAX_IMPORTED_SEEDS);
                end

                particle_time_sec(idx,1) = r.duration_sec;

                done_idx = find(~isnan(particle_time_sec));
                avg_dt   = mean(particle_time_sec(done_idx));
                remain_num  = N2 - idx;
                eta_sec     = remain_num * avg_dt / max(PARALLEL_WORKERS, 1);
                finish_time = datetime('now') + seconds(eta_sec);
                finish_time.Format = 'yyyy-MM-dd HH:mm:ss';
                num_right4  = sum(n_right(1:idx) == size_train(1));
                cache_rate  = stat_cache_hit / max(stat_cache_total, 1) * 100;

                fprintf('[iter %d] 粒子 %d / %d | %.2f s | 均 %.2f s | 全对 %d | fym=%.4f dB | parallel=%d\n', ...
                    iter, idx, N2, r.duration_sec, avg_dt, num_right4, fym, PARALLEL_WORKERS);
                fprintf('  缓存 %.1f%% (%d/%d) | 预计 %s\n', ...
                    cache_rate, stat_cache_hit, stat_cache_total, ...
                    char(finish_time));

                record = build_record(x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse); %#ok<NASGU>
                record_time(idx,1) = string(datetime);
                num = idx + 1;
                save_checkpoint(SAVE_FILE);
            end
        end


        %% 一代结束
        fprintf('[Generation %d] fym = %.6f dB | 本代全对 %d / %d\n', ...
            iter, fym, sum(n_right == size_train(1)), N2);
        fprintf('  缓存大小 %d | 总命中率 %.1f%%\n', eval_cache.Count, ...
            stat_cache_hit / max(stat_cache_total, 1) * 100);
        fprintf('-------------------------------\n');

        improved_gen = fym > fym_prev + 1e-9;
        if improved_gen
            stall_gen = 0;
        else
            stall_gen = stall_gen + 1;
        end
        fym_prev = fym;

        %% 目标化局部搜索：代理模型排序后的 1-bit/2-bit 邻域
        if iter < stage2_target_iter && size(cache_bits, 1) >= SURROGATE_MIN_SAMPLES
            surrogate = train_surrogate(cache_bits, cache_F_soft);
            selected_local = targeted_local_candidates(ym, surrogate, d, LOCAL_1BIT_EVAL, ...
                                                       LOCAL_2BIT_TOP_BITS, LOCAL_2BIT_EVAL, stall_gen);
            selected_local = remove_cached_candidates(selected_local, eval_cache);
            fprintf('[targeted local] evaluating %d surrogate-ranked neighbors, stall=%d.\n', ...
                size(selected_local, 1), stall_gen);
            local_improved = 0;

            local_results = run_parallel_eval_batch(lum_workers, selected_local, eval_cache, ...
                train_data, train_target, size_train, size_target, tau, lambda_balance, true);
            for li = 1:size(selected_local, 1)
                neighbor = selected_local(li, :);
                r = local_results{li};

                stat_cache_total = stat_cache_total + 1;
                if r.cache_hit
                    stat_cache_hit = stat_cache_hit + 1;
                end
                if r.early_stopped
                    stat_early_stop = stat_early_stop + 1;
                end
                if ~r.cache_hit
                    eval_cache = store_eval_cache(eval_cache, neighbor, r);
                    [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                     cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full] = ...
                        append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                            cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full, ...
                                            neighbor, r.n_right, r.CR_worst, r.loss_mse, r.CR_each, r.F_soft, ...
                                            r.worst_idx, r.is_full);
                end

                if r.n_right == size_train(1) && r.CR_worst > fym
                    fym = r.CR_worst;
                    ym  = neighbor;
                    best_CR_each = r.CR_each(:)';
                    best_worst_idx = r.worst_idx;
                    local_improved = local_improved + 1;
                    [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, neighbor, r.CR_worst, MAX_IMPORTED_SEEDS);
                    fprintf('  [targeted local] improved fym = %.6f dB, worst logic=%d\n', fym, best_worst_idx);
                end
            end

            fprintf('[targeted local] done, improvements=%d, current fym=%.6f dB\n', local_improved, fym);
        end

        p_eda = update_eda_probability(cache_bits, cache_CR_worst, cache_F_soft, cache_is_full, ...
                                       p_eda, rho, ELITE_FRAC, p_min, p_max);
        if stall_gen >= STALL_RESET_GEN
            p_eda = min(max(0.85 * p_eda + 0.15 * 0.5, p_min), p_max);
            fprintf('[EDA] probability annealed after %d stalled generations.\n', stall_gen);
        end

        % 重置每代指标
        n_right  = zeros(N2, 1);
        CR_worst = zeros(N2, 1);
        loss_mse = zeros(N2, 1);
        particle_time_sec = nan(N2, 1);

        iter = iter + 1;
        num  = 1;

        % 代结束保存
        record = build_record(x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse);

        save_checkpoint(SAVE_FILE);
    end
end

catch ME
    try
        record = build_record(x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse); %#ok<NASGU>
        save_checkpoint(SAVE_FILE);
    catch
    end
    cleanup_lumerical_constant(lum_workers);
    if ~isempty(h)
        try appclose(h); catch; end
    end
    rethrow(ME);
end

%% ==================== 输出最优结果 ====================
fprintf('\n===== 最优结构验证 =====\n');
cleanup_lumerical_constant(lum_workers);
h = open_lumerical_mode(SIM_FILE);
L = ym';
set_slot(h, L);

p_final = zeros(size_target);
for tt = 1:size_train(1)
    phs = train_data(tt,:) * 180/pi;
    p_final(tt,:) = train_out(h, phs);
end

fprintf('最优对比度 fym = %.6f dB\n', fym);
for kk = 1:size_train(1)
    fprintf('输入%d: P1 = %.6e, P2 = %.6e\n', kk, p_final(kk,1), p_final(kk,2));
end

% 重新计算 CR 验证
CR_verify = zeros(size_train(1), 1);
eps_val = 1e-30;
for kk = 1:size_train(1)
    if train_target(kk,1) > train_target(kk,2)
        P_right = abs(p_final(kk,1));
        P_wrong = abs(p_final(kk,2));
    else
        P_right = abs(p_final(kk,2));
        P_wrong = abs(p_final(kk,1));
    end
    CR_verify(kk) = 10 * log10((P_right + eps_val) / (P_wrong + eps_val));
    fprintf('  CR_%d = %.4f dB\n', kk, CR_verify(kk));
end
fprintf('CR_worst (验证) = %.4f dB\n', min(CR_verify));

fprintf('\n===== 优化统计 =====\n');
fprintf('种子数: %d\n', size(seed_pool, 1));
fprintf('缓存大小: %d | 总命中: %d / %d (%.1f%%)\n', ...
    eval_cache.Count, stat_cache_hit, stat_cache_total, ...
    stat_cache_hit / max(stat_cache_total, 1) * 100);
fprintf('早停次数: %d\n', stat_early_stop);
fprintf('最优结构: %s\n', char(ym + '0'));

if exist(SAVE_FILE, 'file')
    copyfile(SAVE_FILE, NAMED_SAVE_FILE);
    fprintf('[INFO] Named result saved: %s\n', NAMED_SAVE_FILE);
end

if ~isempty(h)
    appclose(h);
end

%% ==================== 本地函数 ====================

function tag = infer_logic_gate_name(train_data_raw, train_target)
    tag = char([26410 30693 38376]);
    if size(train_target, 2) < 2 || size(train_target, 1) ~= 4
        return;
    end

    if size(train_data_raw, 2) >= 3 && isscalar(unique(train_data_raw(:, 2)))
        a = train_data_raw(:, 1) > 0.5;
        b = train_data_raw(:, 3) > 0.5;
    elseif size(train_data_raw, 2) >= 2
        a = train_data_raw(:, 1) > 0.5;
        b = train_data_raw(:, 2) > 0.5;
    else
        return;
    end

    y = train_target(:, 2) > train_target(:, 1);
    truth = nan(4, 1);
    for i = 1:numel(y)
        idx = 1 + 2 * double(a(i)) + double(b(i));
        truth(idx) = y(i);
    end
    if any(isnan(truth))
        return;
    end

    key = char(truth(:)' + '0');
    switch key
        case '0001'
            tag = char([19982 38376]);
        case '0111'
            tag = char([25110 38376]);
        case '0110'
            tag = char([24322 25110 38376]);
        case '1001'
            tag = char([21516 25110 38376]);
        case '1110'
            tag = char([19982 38750 38376]);
        case '1000'
            tag = char([25110 38750 38376]);
    end
end

function [seed_pool, seed_pool_cr] = import_existing_results(patterns, d, n_logic, max_seeds)
% 从历史 record_unified*.mat 读取已找到的结构；旧指标文件只继承结构，不继承 CR。
    seed_pool = zeros(0, d);
    seed_pool_cr = zeros(0, 1);
    if ischar(patterns) || isstring(patterns)
        patterns = cellstr(patterns);
    end
    files = [];
    for pi = 1:numel(patterns)
        files = [files; dir(patterns{pi})]; %#ok<AGROW>
    end
    if ~isempty(files)
        file_paths = arrayfun(@(f) fullfile(f.folder, f.name), files, 'UniformOutput', false);
        [~, unique_idx] = unique(file_paths, 'stable');
        files = files(unique_idx);
    end

    for fi = 1:length(files)
        file_path = fullfile(files(fi).folder, files(fi).name);
        try
            S = load(file_path);
        catch
            fprintf('[WARN] 无法读取历史结果 %s，已跳过。\n', file_path);
            continue;
        end

        metric_ok = isfield(S, 'metric_version') && any(S.metric_version == [2 3]);

        if isfield(S, 'seed_pool') && ~isempty(S.seed_pool)
            bits = double(S.seed_pool);
            if isfield(S, 'seed_pool_cr') && metric_ok
                cr = double(S.seed_pool_cr(:));
            else
                cr = -inf(size(bits, 1), 1);
            end
            [seed_pool, seed_pool_cr] = merge_seed_block(seed_pool, seed_pool_cr, bits, cr, max_seeds);
        end

        if isfield(S, 'ym') && numel(S.ym) == d
            bits = double(S.ym(:)');
            if isfield(S, 'fym') && metric_ok
                cr = double(S.fym);
            else
                cr = -inf;
            end
            [seed_pool, seed_pool_cr] = merge_seed_block(seed_pool, seed_pool_cr, bits, cr, max_seeds);
        end

        if metric_ok && isfield(S, 'record') && size(S.record, 2) >= 4*d + 4
            rec_bits = double(S.record(:, 1:d));
            rec_nr = double(S.record(:, 4*d + 3));
            rec_cr = double(S.record(:, 4*d + 4));
            keep = all(rec_bits == 0 | rec_bits == 1, 2) & rec_nr == n_logic & isfinite(rec_cr);
            [seed_pool, seed_pool_cr] = merge_seed_block(seed_pool, seed_pool_cr, rec_bits(keep,:), rec_cr(keep), max_seeds);
        end
    end

    if ~isempty(seed_pool)
        [seed_pool_cr, idx] = sort(seed_pool_cr, 'descend');
        seed_pool = seed_pool(idx, :);
        fprintf('[INFO] 历史结果导入完成：%d 个唯一结构。\n', size(seed_pool, 1));
    end
end

function cand = collect_initial_reeval_candidates(patterns, d, max_candidates)
    cand = zeros(0, d);
    if ischar(patterns) || isstring(patterns)
        patterns = cellstr(patterns);
    end
    files = [];
    for pi = 1:numel(patterns)
        files = [files; dir(patterns{pi})]; %#ok<AGROW>
    end
    if isempty(files)
        return;
    end
    file_paths = arrayfun(@(f) fullfile(f.folder, f.name), files, 'UniformOutput', false);
    [~, unique_idx] = unique(file_paths, 'stable');
    files = files(unique_idx);

    for fi = 1:length(files)
        file_path = fullfile(files(fi).folder, files(fi).name);
        try
            S = load(file_path);
        catch
            continue;
        end
        local_cand = zeros(0, d);
        if isfield(S, 'ym') && numel(S.ym) == d
            local_cand = [local_cand; double(S.ym(:)')]; %#ok<AGROW>
        end
        if isfield(S, 'seed_pool') && size(S.seed_pool, 2) == d
            local_cand = [local_cand; double(S.seed_pool)]; %#ok<AGROW>
        end
        if isfield(S, 'cache_bits') && size(S.cache_bits, 2) == d
            cb = double(S.cache_bits);
            if isfield(S, 'cache_CR_worst') && numel(S.cache_CR_worst) == size(cb, 1)
                [~, ord] = sort(double(S.cache_CR_worst(:)), 'descend');
                cb = cb(ord, :);
            end
            local_cand = [local_cand; cb(1:min(size(cb, 1), max_candidates), :)]; %#ok<AGROW>
        end
        if isfield(S, 'record') && size(S.record, 2) >= d
            rb = double(S.record(:, 1:d));
            rb = rb(all(rb == 0 | rb == 1, 2), :);
            local_cand = [local_cand; rb(1:min(size(rb, 1), max_candidates), :)]; %#ok<AGROW>
        end
        local_cand = local_cand(all(local_cand == 0 | local_cand == 1, 2), :);
        cand = unique([cand; local_cand], 'rows', 'stable');
        if size(cand, 1) >= max_candidates
            cand = cand(1:max_candidates, :);
            break;
        end
    end
    if ~isempty(cand)
        fprintf('[INFO] 已建立 %d 个历史结构的 v3 完整重评估队列。\n', size(cand, 1));
    end
end

function [seed_pool, seed_pool_cr] = merge_seed_block(seed_pool, seed_pool_cr, bits, cr, max_seeds)
    if isempty(bits)
        return;
    end
    if size(bits, 2) ~= size(seed_pool, 2)
        return;
    end
    cr = cr(:);
    if length(cr) < size(bits, 1)
        cr(end+1:size(bits, 1), 1) = -inf;
    end
    for i = 1:size(bits, 1)
        if all(bits(i,:) == 0 | bits(i,:) == 1)
            [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, bits(i,:), cr(i), max_seeds);
        end
    end
end

function [x, v, xm, fxm, fym, ym, n_right, CR_worst, loss_mse, particle_time_sec, record, record_time] = ...
        init_memetic_population(seed_pool, seed_pool_cr, N, d)
    [seed_pool_cr, sort_idx] = sort(seed_pool_cr(:), 'descend');
    seed_pool = seed_pool(sort_idx, :);
    n_seed = size(seed_pool, 1);

    x = zeros(N, d);
    take_n = min(n_seed, N);
    x(1:take_n, :) = seed_pool(1:take_n, :);
    for i = (take_n+1):N
        base = seed_pool(randi(n_seed), :);
        flip_count = randi([1, min(4, d)]);
        flip_idx = randperm(d, flip_count);
        base(flip_idx) = 1 - base(flip_idx);
        x(i,:) = base;
    end

    v = zeros(N, d);  % 保留旧 record 列，不再作为速度使用
    xm = x;
    fxm = -inf(N, 1);
    fxm(1:take_n) = seed_pool_cr(1:take_n);
    [fym, best_idx] = max(fxm);
    if isinf(fym) && fym < 0
        best_idx = 1;
    end
    ym = xm(best_idx, :);

    n_right  = zeros(N, 1);
    CR_worst = zeros(N, 1);
    loss_mse = zeros(N, 1);
    particle_time_sec = nan(N, 1);
    record = build_record(x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse);
    record_time = repmat(string(datetime), N, 1);
end

function [cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full] = ...
        normalize_archive_fields(cache_bits, cache_n_right, cache_CR_worst, ...
                                 cache_CR_each, cache_F_soft, cache_worst_idx, ...
                                 cache_is_full, n_logic, tau, lambda_balance)
    n = size(cache_bits, 1);
    if size(cache_CR_each, 1) ~= n || size(cache_CR_each, 2) ~= n_logic
        new_CR_each = nan(n, n_logic);
        rows = min(size(cache_CR_each, 1), n);
        cols = min(size(cache_CR_each, 2), n_logic);
        if rows > 0 && cols > 0
            new_CR_each(1:rows, 1:cols) = cache_CR_each(1:rows, 1:cols);
        end
        cache_CR_each = new_CR_each;
    end
    cache_F_soft = resize_col(cache_F_soft, n, -inf);
    cache_worst_idx = resize_col(cache_worst_idx, n, 0);
    cache_is_full = logical(resize_col(cache_is_full, n, false));

    for i = 1:n
        if all(isfinite(cache_CR_each(i,:)))
            if ~isfinite(cache_F_soft(i))
                cache_F_soft(i) = softmin_score(cache_CR_each(i,:)', tau, lambda_balance);
            end
            if cache_worst_idx(i) <= 0
                [~, cache_worst_idx(i)] = min(cache_CR_each(i,:));
            end
        elseif cache_n_right(i) == n_logic && isfinite(cache_CR_worst(i))
            cache_CR_each(i,:) = cache_CR_worst(i);
            cache_F_soft(i) = softmin_score(cache_CR_each(i,:)', tau, lambda_balance);
            cache_worst_idx(i) = 1;
        end
        cache_is_full(i) = cache_n_right(i) == n_logic && all(isfinite(cache_CR_each(i,:)));
    end
end

function record = build_record(x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse)
    n = size(x, 1);
    record = [x, v, xm, repmat(ym, n, 1), fxm, repmat(fym, n, 1), ...
              n_right, CR_worst, loss_mse];
end

function v = resize_col(v, n, fill_value)
    v = v(:);
    if length(v) < n
        v(end+1:n, 1) = fill_value;
    elseif length(v) > n
        v = v(1:n);
    end
end

function eval_cache = rebuild_eval_cache(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                         cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full)
    eval_cache = containers.Map('KeyType','char','ValueType','any');
    for i = 1:size(cache_bits, 1)
        bits = cache_bits(i,:);
        if ~all(bits == 0 | bits == 1)
            continue;
        end
        ce.p = [];
        ce.n_right = cache_n_right(i);
        ce.CR_worst = cache_CR_worst(i);
        ce.loss_mse = cache_loss_mse(i);
        ce.CR_each = cache_CR_each(i,:)';
        ce.F_soft = cache_F_soft(i);
        ce.worst_idx = cache_worst_idx(i);
        ce.is_full = cache_is_full(i);
        eval_cache(char(bits + '0')) = ce;
    end
end

function [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
          cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full] = ...
        append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                            cache_CR_each, cache_F_soft, cache_worst_idx, cache_is_full, ...
                            bits, nr, crw, lmse, CR_each, F_soft, worst_idx, is_full)
    bits = double(bits(:)');
    key = char(bits + '0');
    CR_each = double(CR_each(:)');
    for i = 1:size(cache_bits, 1)
        if strcmp(char(cache_bits(i,:) + '0'), key)
            cache_n_right(i) = nr;
            cache_CR_worst(i) = crw;
            cache_loss_mse(i) = lmse;
            cache_CR_each(i,:) = CR_each;
            cache_F_soft(i) = F_soft;
            cache_worst_idx(i) = worst_idx;
            cache_is_full(i) = is_full;
            return;
        end
    end
    cache_bits = [cache_bits; bits];
    cache_n_right = [cache_n_right; nr];
    cache_CR_worst = [cache_CR_worst; crw];
    cache_loss_mse = [cache_loss_mse; lmse];
    cache_CR_each = [cache_CR_each; CR_each];
    cache_F_soft = [cache_F_soft; F_soft];
    cache_worst_idx = [cache_worst_idx; worst_idx];
    cache_is_full = [cache_is_full; is_full];
end

function [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, bits, cr, max_seeds)
    bits = double(bits(:)');
    for i = 1:size(seed_pool, 1)
        if isequal(seed_pool(i,:), bits)
            seed_pool_cr(i) = max(seed_pool_cr(i), cr);
            return;
        end
    end
    seed_pool = [seed_pool; bits];
    seed_pool_cr = [seed_pool_cr; cr];
    [seed_pool_cr, idx] = sort(seed_pool_cr, 'descend');
    seed_pool = seed_pool(idx, :);
    if size(seed_pool, 1) > max_seeds
        seed_pool = seed_pool(1:max_seeds, :);
        seed_pool_cr = seed_pool_cr(1:max_seeds);
    end
end

function tf = row_exists(A, row)
    if isempty(A)
        tf = false;
    else
        tf = any(all(A == row, 2));
    end
end

function p_eda = initialize_eda_probability(seed_pool, d, p_min, p_max)
    if ~isempty(seed_pool)
        p_eda = 0.6 * mean(double(seed_pool), 1) + 0.4 * 0.5;
    else
        p_eda = 0.5 * ones(1, d);
    end
    p_eda = min(max(p_eda, p_min), p_max);
end

function surrogate = train_surrogate(cache_bits, cache_F_soft)
    surrogate = [];
    ok = all(isfinite(cache_bits), 2) & isfinite(cache_F_soft(:));
    X = double(cache_bits(ok, :));
    y = double(cache_F_soft(ok));
    if size(X, 1) < 10
        return;
    end
    try
        if exist('TreeBagger', 'file') == 2
            surrogate = TreeBagger(120, X, y, ...
                'Method', 'regression', ...
                'OOBPrediction', 'on');
        elseif exist('fitrensemble', 'file') == 2
            surrogate = fitrensemble(X, y, 'Method', 'Bag');
        end
    catch ME
        fprintf('[WARN] surrogate training failed: %s\n', ME.message);
        surrogate = [];
    end
end

function cand = generate_eda_candidates(p_eda, ym, d, N_CAND, stall_gen, cache_bits, cache_CR_worst, cache_F_soft, cache_is_full)
    if nargin < 6
        cache_bits = zeros(0, d);
        cache_CR_worst = zeros(0, 1);
        cache_F_soft = zeros(0, 1);
        cache_is_full = false(0, 1);
    end

    if stall_gen >= 5
        n_archive = round(0.20 * N_CAND);
    else
        n_archive = round(0.08 * N_CAND);
    end
    n_eda = round(0.55 * N_CAND);
    n_local = round(0.20 * N_CAND);
    n_rand = max(0, N_CAND - n_eda - n_local - n_archive);

    eda = double(rand(n_eda, d) < repmat(p_eda, n_eda, 1));
    local = repmat(double(ym(:)'), n_local, 1);
    max_flip = min(d, 4 + min(stall_gen, 8));
    min_flip = 1;
    if stall_gen >= 5
        min_flip = min(max_flip, 3);
    end
    for i = 1:n_local
        flip_count = randi([min_flip, max_flip]);
        flip_idx = randperm(d, flip_count);
        local(i, flip_idx) = 1 - local(i, flip_idx);
    end
    archive = archive_guided_candidates(ym, cache_bits, cache_CR_worst, cache_F_soft, cache_is_full, d, n_archive, stall_gen);
    random_part = double(rand(n_rand, d) > 0.5);
    cand = unique([eda; local; archive; random_part], 'rows', 'stable');
end

function cand = archive_guided_candidates(ym, cache_bits, cache_CR_worst, cache_F_soft, cache_is_full, d, n_archive, stall_gen)
    cand = zeros(0, d);
    if n_archive <= 0 || isempty(cache_bits) || isempty(cache_is_full)
        return;
    end

    full_idx = find(cache_is_full(:));
    if isempty(full_idx)
        return;
    end

    cr = double(cache_CR_worst(full_idx));
    soft = double(cache_F_soft(full_idx));
    ok = isfinite(cr) & isfinite(soft);
    full_idx = full_idx(ok);
    cr = cr(ok);
    soft = soft(ok);
    if isempty(full_idx)
        return;
    end

    cr_score = scale01(cr);
    soft_score = scale01(soft);
    score = cr_score + 0.35 * soft_score;
    [~, ord] = sort(score, 'descend');
    pool_n = min(numel(ord), max(12, ceil(0.20 * numel(ord))));
    pool = double(cache_bits(full_idx(ord(1:pool_n)), :));

    hd_pool = sum(abs(pool - repmat(double(ym(:)'), size(pool, 1), 1)), 2);
    diverse_pool = pool(hd_pool >= 2, :);
    if ~isempty(diverse_pool)
        pool = diverse_pool;
    end
    if isempty(pool)
        return;
    end

    cand = zeros(n_archive, d);
    base = double(ym(:)');
    cross_rate = min(0.65, 0.30 + 0.03 * min(stall_gen, 10));
    min_mut = 1;
    if stall_gen >= 5
        min_mut = 2;
    end
    max_mut = min(d, 5 + min(stall_gen, 10));

    for i = 1:n_archive
        parent = pool(randi(size(pool, 1)), :);
        if size(pool, 1) > 1 && rand < 0.50
            parent2 = pool(randi(size(pool, 1)), :);
            mask = rand(1, d) < 0.50;
            parent(mask) = parent2(mask);
        end

        trial = base;
        inherit_mask = rand(1, d) < cross_rate;
        trial(inherit_mask) = parent(inherit_mask);
        flip_count = randi([min_mut, max_mut]);
        flip_idx = randperm(d, flip_count);
        trial(flip_idx) = 1 - trial(flip_idx);
        cand(i, :) = trial;
    end

    cand = unique(cand, 'rows', 'stable');
end

function cand = remove_cached_candidates(cand, eval_cache)
    if isempty(cand)
        return;
    end
    keep = true(size(cand, 1), 1);
    for i = 1:size(cand, 1)
        key = char(cand(i,:) + '0');
        if eval_cache.isKey(key)
            cached = eval_cache(key);
            keep(i) = ~(isfield(cached, 'is_full') && cached.is_full);
        end
    end
    cand = cand(keep, :);
end

function selected = select_candidates_by_surrogate(cand, surrogate, ym, K_TRUE, stall_gen)
    if nargin < 5 || isempty(stall_gen)
        stall_gen = 0;
    end
    if isempty(cand)
        selected = zeros(0, numel(ym));
        return;
    end
    pred_F = predict_surrogate(surrogate, cand);
    hd = sum(abs(cand - repmat(ym, size(cand, 1), 1)), 2) / size(cand, 2);
    hd_weight = 0.03 + 0.02 * min(stall_gen, 8);
    acq = pred_F + hd_weight * hd;

    if stall_gen >= 5
        n_top_frac = 0.50;
        n_mid_frac = 0.30;
        mid_min_hd = 0.10;
        mid_max_hd = 0.65;
    else
        n_top_frac = 0.70;
        n_mid_frac = 0.20;
        mid_min_hd = 0.08;
        mid_max_hd = 0.45;
    end

    n_top = min(size(cand, 1), max(1, round(n_top_frac * K_TRUE)));
    n_mid = min(size(cand, 1) - n_top, max(0, round(n_mid_frac * K_TRUE)));
    n_rand = max(0, K_TRUE - n_top - n_mid);

    [~, ord_acq] = sort(acq, 'descend');
    pick = ord_acq(1:n_top);

    mid_pool = find(hd >= mid_min_hd & hd <= mid_max_hd);
    mid_pool = setdiff(mid_pool, pick, 'stable');
    if ~isempty(mid_pool) && n_mid > 0
        [~, ord_mid] = sort(pred_F(mid_pool), 'descend');
        pick = [pick; mid_pool(ord_mid(1:min(n_mid, numel(ord_mid))))];
    end

    remain = setdiff((1:size(cand, 1))', pick, 'stable');
    if ~isempty(remain) && n_rand > 0
        rp = remain(randperm(numel(remain), min(n_rand, numel(remain))));
        pick = [pick; rp];
    end

    if numel(pick) < K_TRUE
        remain = setdiff((1:size(cand, 1))', pick, 'stable');
        pick = [pick; remain(1:min(K_TRUE - numel(pick), numel(remain)))];
    end
    selected = cand(pick(1:min(K_TRUE, numel(pick))), :);
end

function pred = predict_surrogate(surrogate, X)
    if isempty(surrogate)
        pred = zeros(size(X, 1), 1);
        return;
    end
    pred = predict(surrogate, double(X));
    if iscell(pred)
        pred = str2double(pred);
    end
    pred = double(pred(:));
end

function x = fill_stage2_population(selected, p_eda, ym, N, d, eval_cache)
    x = zeros(N, d);
    take_n = min(N, size(selected, 1));
    if take_n > 0
        x(1:take_n, :) = selected(1:take_n, :);
    end
    i = take_n + 1;
    attempts = 0;
    while i <= N
        attempts = attempts + 1;
        if rand < 0.7
            trial = double(rand(1, d) < p_eda);
        else
            trial = ym;
            flip_count = randi([1, min(4, d)]);
            flip_idx = randperm(d, flip_count);
            trial(flip_idx) = 1 - trial(flip_idx);
        end
        if ~eval_cache.isKey(char(trial + '0')) && ~row_exists(x(1:i-1,:), trial)
            x(i,:) = trial;
            i = i + 1;
            attempts = 0;
        elseif attempts > 50
            x(i,:) = double(rand(1, d) > 0.5);
            i = i + 1;
            attempts = 0;
        end
    end
end

function p_eda = update_eda_probability(cache_bits, cache_CR_worst, cache_F_soft, cache_is_full, ...
                                        p_eda, rho, elite_frac, p_min, p_max)
    idx_full = find(cache_is_full);
    if numel(idx_full) >= 10
        pool_idx = idx_full;
        cr_score = scale01(cache_CR_worst(pool_idx));
        soft_score = scale01(cache_F_soft(pool_idx));
        score = cr_score + 0.35 * soft_score;
    else
        pool_idx = (1:size(cache_bits, 1))';
        score = cache_F_soft(pool_idx);
    end
    ok = isfinite(score);
    pool_idx = pool_idx(ok);
    score = score(ok);
    if isempty(pool_idx)
        return;
    end
    [~, ord] = sort(score, 'descend');
    n_elite = min(numel(ord), max(8, round(elite_frac * numel(pool_idx))));
    elite_bits = cache_bits(pool_idx(ord(1:n_elite)), :);
    p_new = mean(elite_bits, 1);
    p_eda = (1 - rho) * p_eda + rho * p_new;
    p_eda = min(max(p_eda, p_min), p_max);
end

function y = scale01(x)
    x = double(x(:));
    y = -inf(size(x));
    ok = isfinite(x);
    if ~any(ok)
        return;
    end
    xmin = min(x(ok));
    xmax = max(x(ok));
    if xmax > xmin
        y(ok) = (x(ok) - xmin) / (xmax - xmin);
    else
        y(ok) = 0.5;
    end
end

function pool = ensure_parallel_pool(worker_count)
    if license('test', 'Distrib_Computing_Toolbox') ~= 1
        error('BPSO:ParallelToolboxUnavailable', ...
            'Parallel Computing Toolbox is required for parallel Lumerical evaluation.');
    end

    pool = gcp('nocreate');
    if ~isempty(pool) && pool.NumWorkers ~= worker_count
        fprintf('[INFO] Recreating parallel pool: existing=%d, requested=%d.\n', ...
            pool.NumWorkers, worker_count);
        delete(pool);
        pool = [];
    end
    if isempty(pool)
        pool = parpool('local', worker_count);
    end
    if pool.NumWorkers ~= worker_count
        error('BPSO:ParallelWorkerCountMismatch', ...
            'Expected %d workers, got %d.', worker_count, pool.NumWorkers);
    end
end

function attach_parallel_files(pool, script_dir)
    files = { ...
        fullfile(script_dir, 'LumericalWorkerSession.m'), ...
        fullfile(script_dir, 'make_lumerical_worker_session.m'), ...
        fullfile(script_dir, 'close_lumerical_worker_session.m'), ...
        fullfile(script_dir, 'worker_eval_particle.m'), ...
        fullfile(script_dir, 'append_path_once.m'), ...
        fullfile(script_dir, 'make_eval_result.m'), ...
        fullfile(script_dir, 'open_lumerical_mode.m'), ...
        fullfile(script_dir, 'softmin_score.m'), ...
        fullfile(script_dir, 'set_slot.m'), ...
        fullfile(script_dir, 'train_out.m')};
    files = files(cellfun(@(f) exist(f, 'file') == 2, files));
    addAttachedFiles(pool, files);
end

function validate_parallel_lumerical_workers(lum_workers, expected_workers)
    spmd
        worker_ok = false;
        worker_msg = '';
        try
            session = lum_workers.Value;
            worker_ok = ~isempty(session) && ~isempty(session.h);
            if ~worker_ok
                worker_msg = 'MODE handle is empty.';
            end
        catch ME
            worker_msg = ME.message;
        end
    end

    ok = false(1, numel(worker_ok));
    msg = cell(1, numel(worker_ok));
    for i = 1:numel(worker_ok)
        ok(i) = worker_ok{i};
        msg{i} = worker_msg{i};
    end

    if numel(ok) ~= expected_workers || ~all(ok)
        detail = strjoin(msg(~ok), ' | ');
        if isempty(detail)
            detail = 'unknown worker startup failure';
        end
        error('BPSO:LumericalWorkerStartupFailed', ...
            'Failed to start exactly %d Lumerical MODE worker sessions: %s', ...
            expected_workers, detail);
    end
end

function results = run_parallel_eval_batch(lum_workers, candidates, eval_cache, ...
        train_data, train_target, size_train, size_target, tau, lambda_balance, full_eval)
    n = size(candidates, 1);
    results = cell(n, 1);
    run_idx = zeros(0, 1);

    for i = 1:n
        key = char(candidates(i,:) + '0');
        if eval_cache.isKey(key)
            cached = eval_cache(key);
            cached_is_full = isfield(cached, 'is_full') && cached.is_full;
            if ~full_eval || cached_is_full
                results{i} = result_from_cache(cached, size_train(1), tau, lambda_balance);
                continue;
            end
        end
        run_idx(end+1, 1) = i; %#ok<AGROW>
    end

    if ~isempty(run_idx)
        run_results = cell(numel(run_idx), 1);
        run_candidates = candidates(run_idx, :);
        parfor ri = 1:numel(run_idx)
            run_results{ri} = worker_eval_particle(lum_workers.Value, run_candidates(ri,:)', ... %#ok<PFBNS>
                train_data, train_target, size_train, size_target, tau, lambda_balance, full_eval);
        end

        for ri = 1:numel(run_idx)
            results{run_idx(ri)} = run_results{ri};
        end
    end
end

function result = result_from_cache(cached, n_logic, tau, lambda_balance)
    if isfield(cached, 'CR_each') && numel(cached.CR_each) == n_logic
        CR_each = cached.CR_each(:);
    else
        CR_each = nan(n_logic, 1);
    end
    if isfield(cached, 'F_soft')
        F_soft = cached.F_soft;
    else
        F_soft = softmin_score(CR_each, tau, lambda_balance);
    end
    if isfield(cached, 'worst_idx')
        worst_idx = cached.worst_idx;
    else
        [~, worst_idx] = min(CR_each);
    end
    is_full = isfield(cached, 'is_full') && cached.is_full;
    result = make_eval_result(cached.n_right, cached.CR_worst, cached.loss_mse, ...
        CR_each, F_soft, worst_idx, is_full, true, false, 0);
end

function eval_cache = store_eval_cache(eval_cache, bits, result)
    ce = struct();
    ce.p = [];
    ce.n_right = result.n_right;
    ce.CR_worst = result.CR_worst;
    ce.loss_mse = result.loss_mse;
    ce.CR_each = result.CR_each(:);
    ce.F_soft = result.F_soft;
    ce.worst_idx = result.worst_idx;
    ce.is_full = result.is_full;
    eval_cache(char(double(bits(:)') + '0')) = ce;
end

function cleanup_lumerical_constant(lum_workers)
    if ~isempty(lum_workers)
        try
            delete(lum_workers);
        catch
        end
    end
end

function selected_local = targeted_local_candidates(ym, surrogate, d, K1, K2_TOP_BITS, K2, stall_gen)
    if nargin < 7 || isempty(stall_gen)
        stall_gen = 0;
    end

    nei1 = repmat(ym, d, 1);
    for b = 1:d
        nei1(b,b) = 1 - nei1(b,b);
    end
    pred1 = predict_surrogate(surrogate, nei1);
    [~, ord1] = sort(pred1, 'descend');
    take1 = min(K1, numel(ord1));
    eval_1bit = nei1(ord1(1:take1), :);

    extra_top_bits = min(max(stall_gen - 4, 0), 10);
    top_bits = ord1(1:min(K2_TOP_BITS + extra_top_bits, numel(ord1)));
    if numel(top_bits) >= 2
        pairs = nchoosek(top_bits, 2);
        nei2 = repmat(ym, size(pairs, 1), 1);
        for i = 1:size(pairs, 1)
            nei2(i,pairs(i,1)) = 1 - nei2(i,pairs(i,1));
            nei2(i,pairs(i,2)) = 1 - nei2(i,pairs(i,2));
        end
        pred2 = predict_surrogate(surrogate, nei2);
        [~, ord2] = sort(pred2, 'descend');
        K2_eff = K2 + min(max(stall_gen - 4, 0), 4);
        eval_2bit = nei2(ord2(1:min(K2_eff, numel(ord2))), :);
    else
        eval_2bit = zeros(0, d);
    end

    if stall_gen >= 5 && numel(top_bits) >= 3
        top3_count = min(numel(top_bits), K2_TOP_BITS + min(stall_gen, 6));
        triples = nchoosek(top_bits(1:top3_count), 3);
        nei3 = repmat(ym, size(triples, 1), 1);
        for i = 1:size(triples, 1)
            nei3(i,triples(i,1)) = 1 - nei3(i,triples(i,1));
            nei3(i,triples(i,2)) = 1 - nei3(i,triples(i,2));
            nei3(i,triples(i,3)) = 1 - nei3(i,triples(i,3));
        end
        pred3 = predict_surrogate(surrogate, nei3);
        [~, ord3] = sort(pred3, 'descend');
        K3 = min(6, max(3, stall_gen - 2));
        eval_3bit = nei3(ord3(1:min(K3, numel(ord3))), :);
    else
        eval_3bit = zeros(0, d);
    end

    selected_local = unique([eval_1bit; eval_2bit; eval_3bit], 'rows', 'stable');
end

function save_checkpoint(save_file)
% 把所有断点状态从 caller workspace 收集到一个 struct 后落盘。
% 新增/移除字段时只需改 checkpoint_var_names.m，避免 save 列表漂移。
    var_names = checkpoint_var_names();
    S = struct();
    S.metric_version = evalin('caller', 'METRIC_VERSION');
    for k = 1:numel(var_names)
        S.(var_names{k}) = evalin('caller', var_names{k});
    end
    save(save_file, '-struct', 'S', '-v7.3');
end
