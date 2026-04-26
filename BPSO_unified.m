clear all; close all; clc;

%% 路径设置
LUM_BIN  = 'D:\Program Files\Lumerical\v231\bin';
LUM_API  = 'D:\Program Files\Lumerical\v231\api\matlab';
SCRIPT_DIR = fileparts(mfilename('fullpath'));
if isempty(SCRIPT_DIR)
    SCRIPT_DIR = pwd;
end
SIM_FILE = fullfile(SCRIPT_DIR, '1.structure', 'logic_mode.lms');

setenv('PATH', [getenv('PATH') ';' LUM_BIN]);
addpath(LUM_API);

assert(exist(SIM_FILE, 'file') == 2, 'Simulation file not found: %s', SIM_FILE);
assert(exist(fullfile(SCRIPT_DIR, 'train_data.mat'), 'file') == 2, 'Missing train_data.mat in %s', SCRIPT_DIR);
assert(exist(fullfile(SCRIPT_DIR, 'train_target.mat'), 'file') == 2, 'Missing train_target.mat in %s', SCRIPT_DIR);

%% 加载数据集及初始化
load(fullfile(SCRIPT_DIR, 'train_data.mat'));
load(fullfile(SCRIPT_DIR, 'train_target.mat'));

size_train  = size(train_data);
size_target = size(train_target);
RESULT_TAG = infer_logic_gate_name(train_data, train_target);

train_data = train_data * pi;   % 将训练集数据加载到相位上

%% 参数设置
N1  = 1000;              % 阶段1种群规模
N2  = 30;                % 阶段2种群规模
d   = 49;                % 49个孔洞的二进制材料变量
ger2 = 10;               % 首次运行阶段2基础代数
N_SEED_TARGET = 5;       % 阶段1需要找到的全对结构数

CONTINUE_FROM_EXISTING_RESULTS = true;  % 自动导入 record_unified*.mat 作为阶段2种子
START_STAGE2_WITH_IMPORTED_SEEDS = true;
STAGE2_EXTRA_GENERATIONS_ON_RESUME = 20;
MAX_IMPORTED_SEEDS = 200;
LOCAL_SEARCH_BITS_PER_GEN = d;
TWO_BIT_ELITE_TRIALS = 24;
DUPLICATE_RETRY_LIMIT = 80;

% 材料名（增量 set_slot 用）
matA = 'A_Sb2Se3';   % 非晶态
matB = 'B_Sb2Se3';   % 晶态

SAVE_FILE = fullfile(SCRIPT_DIR, 'record_unified.mat');
NAMED_SAVE_FILE = fullfile(SCRIPT_DIR, ['record_unified' RESULT_TAG '.mat']);
RESULT_PATTERNS = {SAVE_FILE, NAMED_SAVE_FILE, fullfile(SCRIPT_DIR, ['record_unified' RESULT_TAG '_*.mat'])};
METRIC_VERSION = 2;  % v1 = 伪功率+20*log10, v2 = 透过率T+10*log10

%% 共享优化基础设施
eval_cache = containers.Map('KeyType','char','ValueType','any');
last_bits  = nan(d, 1);
stat_cache_hit   = 0;
stat_cache_total = 0;
stat_early_stop  = 0;
cache_bits = zeros(0, d);
cache_n_right = zeros(0, 1);
cache_CR_worst = zeros(0, 1);
cache_loss_mse = zeros(0, 1);
stage2_target_iter = ger2;
stall_gen = 0;
fym_prev = -inf;

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
            if isfield(S, 'stage2_target_iter'), stage2_target_iter = S.stage2_target_iter; end
            if isfield(S, 'stall_gen'), stall_gen = S.stall_gen; end
            if isfield(S, 'fym_prev'), fym_prev = S.fym_prev; end
            eval_cache = rebuild_eval_cache(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse);

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

        record = [x, v, xm, repmat(ym,N1,1), fxm, repmat(fym,N1,1), ...
                  n_right, CR_worst, loss_mse];
        record_time = repmat(string(datetime), N1, 1);
    end

    iter = 1;
    num  = 1;
end

%% 打开 Lumerical（一次，两阶段共享）
path(path, LUM_API);
[sim_file_path, sim_file_name, ~] = fileparts(SIM_FILE);

h = [];
h = appopen('mode');
assert(~isempty(h), 'Failed to open MODE.');

appputvar(h, 'sim_file_path', sim_file_path);
appputvar(h, 'sim_file_name', sim_file_name);

code = strcat('cd(sim_file_path);', 'load(sim_file_name);');
appevalscript(h, code);

%% ==================== 阶段1: 发现 ====================
try

if phase == 1
    % 阶段1 是单遍随机扫描（ger=1），不做速度/位置迭代更新
    fprintf('========== 阶段1: 发现全对结构 (N=%d) ==========\n', N1);

    while num <= N1

        t_particle = tic;
        stat_cache_total = stat_cache_total + 1;

        L = x(num,:)';

        [nr, crw, lmse, ~, cache_hit, early_stopped, last_bits] = ...
            eval_particle(h, L, eval_cache, last_bits, ...
                          train_data, train_target, size_train, size_target, ...
                          matA, matB);

        n_right(num,1)  = nr;
        CR_worst(num,1) = crw;
        loss_mse(num,1) = lmse;

        if cache_hit
            stat_cache_hit = stat_cache_hit + 1;
        end
        if early_stopped
            stat_early_stop = stat_early_stop + 1;
        end
        if ~cache_hit
            [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse] = ...
                append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                    x(num,:), nr, crw, lmse);
        end

        % 适应度：n_right 优先，MSE 次之
        fit_now = n_right(num,1) - loss_mse(num,1);

        % 更新个体最优
        if fit_now > fxm(num,1)
            fxm(num,1) = fit_now;
            xm(num,:) = x(num,:);
        end

        % 更新群体最优
        if fit_now > fym
            fym = fit_now;
            ym = x(num,:);
        end

        % 全对结构 → 加入 seed_pool（去重）
        if nr == size_train(1)
            is_dup = false;
            for si = 1:size(seed_pool,1)
                if isequal(seed_pool(si,:), x(num,:))
                    is_dup = true;
                    break;
                end
            end
            if ~is_dup
                seed_pool = [seed_pool; x(num,:)];
                seed_pool_cr = [seed_pool_cr; crw];
                fprintf('[发现] 第 %d 个全对结构! 粒子 %d, CR_worst = %.4f dB\n', ...
                    size(seed_pool,1), num, crw);
            end
        end

        % 单粒子计时
        dt_particle = toc(t_particle);
        particle_time_sec(num,1) = dt_particle;

        % 进度输出
        done_idx = find(~isnan(particle_time_sec));
        avg_dt   = mean(particle_time_sec(done_idx));
        remain_num  = N1 - num;
        eta_sec     = remain_num * avg_dt;
        finish_time = datetime('now') + seconds(eta_sec);
        num_right4  = sum(n_right(1:num) == size_train(1));
        cache_rate  = stat_cache_hit / max(stat_cache_total, 1) * 100;
        estop_rate  = stat_early_stop / max(stat_cache_total - stat_cache_hit, 1) * 100;

        fprintf('[阶段1] 粒子 %d / %d | %.2f s | 均 %.2f s | 全对 %d | 种子 %d/%d\n', ...
            num, N1, dt_particle, avg_dt, num_right4, size(seed_pool,1), N_SEED_TARGET);
        fprintf('  缓存 %.1f%% (%d/%d) | 早停 %.1f%% | 预计 %s\n', ...
            cache_rate, stat_cache_hit, stat_cache_total, estop_rate, ...
            datestr(finish_time, 'yyyy-mm-dd HH:MM:SS'));

        % 保存断点
        record = [x, v, xm, repmat(ym,N1,1), fxm, repmat(fym,N1,1), ...
                  n_right, CR_worst, loss_mse];
        record_time(num,1) = string(datetime);

        metric_version = METRIC_VERSION;
        save(SAVE_FILE, ...
            'metric_version', 'phase', 'seed_pool', 'seed_pool_cr', ...
            'record', 'record_time', ...
            'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
            'n_right', 'CR_worst', 'loss_mse', ...
            'particle_time_sec', 'iter', 'num', ...
            'cache_bits', 'cache_n_right', 'cache_CR_worst', 'cache_loss_mse', ...
            'stage2_target_iter', 'stall_gen', 'fym_prev', ...
            '-v7.3');

        % 检查是否够种子了
        if size(seed_pool, 1) >= N_SEED_TARGET
            fprintf('\n[阶段切换] 已收集 %d 个全对结构，切换到优化阶段！\n\n', ...
                size(seed_pool, 1));
            break;
        end

        num = num + 1;
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

    iter = 1;
    num  = 1;
    last_bits = nan(d, 1);   % 重置增量状态

    metric_version = METRIC_VERSION;
    save(SAVE_FILE, ...
        'metric_version', 'phase', 'seed_pool', 'seed_pool_cr', ...
        'record', 'record_time', ...
        'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
        'n_right', 'CR_worst', 'loss_mse', ...
        'particle_time_sec', 'iter', 'num', ...
        'cache_bits', 'cache_n_right', 'cache_CR_worst', 'cache_loss_mse', ...
        'stage2_target_iter', 'stall_gen', 'fym_prev', ...
        '-v7.3');
end

%% ==================== 阶段2: 优化 ====================
if phase == 2
    fprintf('========== 阶段2: 种子继承 + Memetic 离散优化 (N=%d, target_iter=%d) ==========\n', ...
        N2, stage2_target_iter);

    while iter <= stage2_target_iter

        while num <= N2

            t_particle = tic;
            stat_cache_total = stat_cache_total + 1;

            L = x(num,:)';

            [nr, crw, lmse, ~, cache_hit, early_stopped, last_bits] = ...
                eval_particle(h, L, eval_cache, last_bits, ...
                              train_data, train_target, size_train, size_target, ...
                              matA, matB);

            n_right(num,1)  = nr;
            CR_worst(num,1) = crw;
            loss_mse(num,1) = lmse;

            if cache_hit
                stat_cache_hit = stat_cache_hit + 1;
            end
            if early_stopped
                stat_early_stop = stat_early_stop + 1;
            end
            if ~cache_hit
                [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse] = ...
                    append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                        x(num,:), nr, crw, lmse);
            end

            % 逐粒子更新个体最优和全局最优（以 CR_worst 为适应度）
            if nr == size_train(1) && crw > fxm(num)
                fxm(num) = crw;
                xm(num,:) = x(num,:);
                if fxm(num) > fym
                    fym = fxm(num);
                    ym = xm(num,:);
                end
            end
            if nr == size_train(1)
                [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, x(num,:), crw, MAX_IMPORTED_SEEDS);
            end

            dt_particle = toc(t_particle);
            particle_time_sec(num,1) = dt_particle;

            % 进度输出
            done_idx = find(~isnan(particle_time_sec));
            avg_dt   = mean(particle_time_sec(done_idx));
            remain_num  = N2 - num;
            eta_sec     = remain_num * avg_dt;
            finish_time = datetime('now') + seconds(eta_sec);
            num_right4  = sum(n_right(1:num) == size_train(1));
            cache_rate  = stat_cache_hit / max(stat_cache_total, 1) * 100;

            fprintf('[iter %d] 粒子 %d / %d | %.2f s | 均 %.2f s | 全对 %d | fym=%.4f dB\n', ...
                iter, num, N2, dt_particle, avg_dt, num_right4, fym);
            fprintf('  缓存 %.1f%% (%d/%d) | 预计 %s\n', ...
                cache_rate, stat_cache_hit, stat_cache_total, ...
                datestr(finish_time, 'yyyy-mm-dd HH:MM:SS'));

            % 保存断点
            record = [x, v, xm, repmat(ym,N2,1), fxm, repmat(fym,N2,1), ...
                      n_right, CR_worst, loss_mse];
            record_time(num,1) = string(datetime);

            metric_version = METRIC_VERSION;
            save(SAVE_FILE, ...
                'metric_version', 'phase', 'seed_pool', 'seed_pool_cr', ...
                'record', 'record_time', ...
                'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
                'n_right', 'CR_worst', 'loss_mse', ...
                'particle_time_sec', 'iter', 'num', ...
                'cache_bits', 'cache_n_right', 'cache_CR_worst', 'cache_loss_mse', ...
                'stage2_target_iter', 'stall_gen', 'fym_prev', ...
                '-v7.3');

            num = num + 1;
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

        %% 局部搜索：先扫 1-bit，停滞时增加 2-bit 扰动
        if iter < stage2_target_iter
            fprintf('[局部搜索] 1-bit 扫描 %d 个位置，停滞 %d 代。\n', LOCAL_SEARCH_BITS_PER_GEN, stall_gen);
            local_improved = 0;
            bit_order = randperm(d, min(LOCAL_SEARCH_BITS_PER_GEN, d));

            for bit_i = bit_order
                neighbor = ym;
                neighbor(bit_i) = 1 - neighbor(bit_i);

                stat_cache_total = stat_cache_total + 1;

                [nb_nr, nb_crw, nb_lmse, ~, nb_cache_hit, ~, last_bits] = ...
                    eval_particle(h, neighbor', eval_cache, last_bits, ...
                                  train_data, train_target, size_train, size_target, ...
                                  matA, matB);

                if nb_cache_hit
                    stat_cache_hit = stat_cache_hit + 1;
                end
                if ~nb_cache_hit
                    [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse] = ...
                        append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                            neighbor, nb_nr, nb_crw, nb_lmse);
                end

                if nb_nr == size_train(1) && nb_crw > fym
                    fym = nb_crw;
                    ym  = neighbor;
                    local_improved = local_improved + 1;
                    [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, neighbor, nb_crw, MAX_IMPORTED_SEEDS);
                    fprintf('  [局部搜索] bit %d 翻转改善! fym = %.6f dB\n', bit_i, fym);
                end
            end

            if stall_gen >= 2
                fprintf('[局部搜索] 2-bit 精英扰动 %d 次。\n', TWO_BIT_ELITE_TRIALS);
                for trial_i = 1:TWO_BIT_ELITE_TRIALS
                    neighbor = ym;
                    bit_pair = randperm(d, 2);
                    neighbor(bit_pair) = 1 - neighbor(bit_pair);

                    stat_cache_total = stat_cache_total + 1;
                    [nb_nr, nb_crw, nb_lmse, ~, nb_cache_hit, ~, last_bits] = ...
                        eval_particle(h, neighbor', eval_cache, last_bits, ...
                                      train_data, train_target, size_train, size_target, ...
                                      matA, matB);
                    if nb_cache_hit
                        stat_cache_hit = stat_cache_hit + 1;
                    else
                        [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse] = ...
                            append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, ...
                                                neighbor, nb_nr, nb_crw, nb_lmse);
                    end

                    if nb_nr == size_train(1) && nb_crw > fym
                        fym = nb_crw;
                        ym  = neighbor;
                        local_improved = local_improved + 1;
                        stall_gen = 0;
                        [seed_pool, seed_pool_cr] = upsert_seed(seed_pool, seed_pool_cr, neighbor, nb_crw, MAX_IMPORTED_SEEDS);
                        fprintf('  [2-bit] bits %d/%d 改善! fym = %.6f dB\n', bit_pair(1), bit_pair(2), fym);
                    end
                end
            end
            fprintf('[局部搜索] 完成，改善 %d 次，当前 fym = %.6f dB\n', local_improved, fym);
        end

        %% 候选生成：精英交叉 + 自适应变异 + 已评估结构去重
        if iter < stage2_target_iter
            x = build_next_population(ym, xm, fxm, N2, d, iter, stage2_target_iter, ...
                                      stall_gen, eval_cache, DUPLICATE_RETRY_LIMIT);
            xm(1,:) = ym;
            fxm(1) = fym;
        end

        % 重置每代指标
        n_right  = zeros(N2, 1);
        CR_worst = zeros(N2, 1);
        loss_mse = zeros(N2, 1);
        particle_time_sec = nan(N2, 1);
        last_bits = nan(d, 1);

        iter = iter + 1;
        num  = 1;

        % 代结束保存
        record = [x, v, xm, repmat(ym,N2,1), fxm, repmat(fym,N2,1), ...
                  n_right, CR_worst, loss_mse];

        metric_version = METRIC_VERSION;
        save(SAVE_FILE, ...
            'metric_version', 'phase', 'seed_pool', 'seed_pool_cr', ...
            'record', 'record_time', ...
            'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
            'n_right', 'CR_worst', 'loss_mse', ...
            'particle_time_sec', 'iter', 'num', ...
            'cache_bits', 'cache_n_right', 'cache_CR_worst', 'cache_loss_mse', ...
            'stage2_target_iter', 'stall_gen', 'fym_prev', ...
            '-v7.3');
    end
end

catch ME
    try
        if phase == 1
            N_cur = N1;
        else
            N_cur = N2;
        end
        record = [x, v, xm, repmat(ym,N_cur,1), fxm, repmat(fym,N_cur,1), ...
                  n_right, CR_worst, loss_mse];
        metric_version = METRIC_VERSION;
        save(SAVE_FILE, ...
            'metric_version', 'phase', 'seed_pool', 'seed_pool_cr', ...
            'record', 'record_time', ...
            'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
            'n_right', 'CR_worst', 'loss_mse', ...
            'particle_time_sec', 'iter', 'num', ...
            'cache_bits', 'cache_n_right', 'cache_CR_worst', 'cache_loss_mse', ...
            'stage2_target_iter', 'stall_gen', 'fym_prev', ...
            '-v7.3');
    catch
    end
    if ~isempty(h)
        try appclose(h); catch; end
    end
    rethrow(ME);
end

%% ==================== 输出最优结果 ====================
fprintf('\n===== 最优结构验证 =====\n');
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
    CR_verify(kk) = 10 * log10(abs(P_right / (P_wrong + eps_val)));
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

    if size(train_data_raw, 2) >= 3 && numel(unique(train_data_raw(:, 2))) == 1
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

        metric_ok = isfield(S, 'metric_version') && S.metric_version == 2;

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
    record = [x, v, xm, repmat(ym,N,1), fxm, repmat(fym,N,1), ...
              n_right, CR_worst, loss_mse];
    record_time = repmat(string(datetime), N, 1);
end

function eval_cache = rebuild_eval_cache(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse)
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
        eval_cache(char(bits + '0')) = ce;
    end
end

function [cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse] = ...
        append_cache_arrays(cache_bits, cache_n_right, cache_CR_worst, cache_loss_mse, bits, nr, crw, lmse)
    bits = double(bits(:)');
    key = char(bits + '0');
    for i = 1:size(cache_bits, 1)
        if strcmp(char(cache_bits(i,:) + '0'), key)
            cache_n_right(i) = nr;
            cache_CR_worst(i) = crw;
            cache_loss_mse(i) = lmse;
            return;
        end
    end
    cache_bits = [cache_bits; bits];
    cache_n_right = [cache_n_right; nr];
    cache_CR_worst = [cache_CR_worst; crw];
    cache_loss_mse = [cache_loss_mse; lmse];
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

function x_next = build_next_population(ym, xm, fxm, N, d, iter, target_iter, stall_gen, eval_cache, retry_limit)
    x_next = zeros(N, d);
    x_next(1,:) = ym;

    valid = find(isfinite(fxm));
    if isempty(valid)
        elites = ym;
    else
        [~, order] = sort(fxm(valid), 'descend');
        elite_idx = valid(order(1:min(length(order), max(3, ceil(0.25*N)))));
        elites = unique([ym; xm(elite_idx,:)], 'rows', 'stable');
    end

    progress = min(1, max(0, (iter - 1) / max(target_iter - 1, 1)));
    base_flip = (5/d) * (1 - progress) + (1/d) * progress;
    p_flip = min(10/d, base_flip + min(stall_gen, 6) / d);

    for i = 2:N
        candidate = [];
        for attempt = 1:retry_limit
            parent = elites(randi(size(elites, 1)), :);
            if size(elites, 1) > 1 && rand < 0.35
                parent2 = elites(randi(size(elites, 1)), :);
                mask_cross = rand(1, d) < 0.5;
                parent(mask_cross) = parent2(mask_cross);
            end

            flip_mask = rand(1, d) < p_flip;
            if ~any(flip_mask)
                flip_mask(randi(d)) = true;
            end
            trial = double(xor(parent, flip_mask));

            if ~eval_cache.isKey(char(trial + '0')) && ~row_exists(x_next(1:i-1,:), trial)
                candidate = trial;
                break;
            end
        end

        if isempty(candidate)
            parent = elites(randi(size(elites, 1)), :);
            flip_count = randi([1, min(d, 2 + stall_gen + ceil(4*(1-progress)))]);
            flip_idx = randperm(d, flip_count);
            parent(flip_idx) = 1 - parent(flip_idx);
            candidate = parent;
        end
        x_next(i,:) = candidate;
    end
end

function tf = row_exists(A, row)
    if isempty(A)
        tf = false;
    else
        tf = any(all(A == row, 2));
    end
end

function last_bits = do_incremental_set(h, L, last_bits, matA, matB)
% 增量 set_slot：只更新变化的孔洞材料，减少 Lumerical 脚本执行量
    cur_bits = L;
    if any(isnan(last_bits))
        set_slot(h, L);
    else
        changed_idx = find(cur_bits ~= last_bits);
        if ~isempty(changed_idx)
            inc_code = 'switchtolayout;';
            for ci = 1:length(changed_idx)
                idx_i = changed_idx(ci);
                name = ['gra', num2str(idx_i)];
                if cur_bits(idx_i) == 0
                    mat_name = matA;
                else
                    mat_name = matB;
                end
                inc_code = [inc_code, ...
                    'select("', name, '");', ...
                    'set("material","', mat_name, '");'];
            end
            appevalscript(h, inc_code);
        end
    end
    last_bits = cur_bits;
end

function [nr, crw, lmse, p, cache_hit, early_stopped, last_bits] = ...
        eval_particle(h, L, eval_cache, last_bits, ...
                      train_data, train_target, size_train, size_target, ...
                      matA, matB)
% 评估单个粒子：缓存 → 增量set_slot → 逐逻辑态仿真+早停 → CR计算
    cache_hit = false;
    early_stopped = false;
    cache_key = char(L' + '0');

    if eval_cache.isKey(cache_key)
        cached = eval_cache(cache_key);
        p    = cached.p;
        nr   = cached.n_right;
        crw  = cached.CR_worst;
        lmse = cached.loss_mse;
        cache_hit = true;
        return;
    end

    % 增量 set_slot
    last_bits = do_incremental_set(h, L, last_bits, matA, matB);

    p = zeros(size_target);
    eps_val = 1e-30;

    % 逐逻辑态仿真 + 早停
    for tt = 1:size_train(1)
        phs = train_data(tt,:) * 180/pi;
        p(tt,:) = train_out(h, phs);

        correct_so_far = sum(double((p(1:tt,1) > p(1:tt,2)) == ...
                                    (train_target(1:tt,1) > train_target(1:tt,2))));
        if tt - correct_so_far > 0
            early_stopped = true;
            nr   = correct_so_far;
            crw  = 0;
            p(tt+1:end,:) = NaN;  % 未仿真行标记为 NaN，避免误用
            p_clean = p;
            p_clean(isnan(p_clean)) = 0;
            p_norm = p_clean / (max(p_clean,[],"all") + eps_val);
            lmse = sumsqr(p_norm - train_target);
            % 写入缓存
            ce.p = p; ce.n_right = nr; ce.CR_worst = crw; ce.loss_mse = lmse;
            eval_cache(cache_key) = ce;
            return;
        end
    end

    % 全部正确
    nr = size_train(1);
    CR_each = zeros(size_train(1), 1);
    for kk = 1:size_train(1)
        if train_target(kk,1) > train_target(kk,2)
            P_right = abs(p(kk,1));
            P_wrong = abs(p(kk,2));
        else
            P_right = abs(p(kk,2));
            P_wrong = abs(p(kk,1));
        end
        % 透过率 T 为功率比，使用 10*log10 计算 dB
        CR_each(kk) = 10 * log10(abs(P_right / (P_wrong + eps_val)));
    end
    crw = min(CR_each);

    p_norm = p / (max(p,[],"all") + eps_val);
    lmse = sumsqr(p_norm - train_target);

    % 写入缓存
    ce.p = p; ce.n_right = nr; ce.CR_worst = crw; ce.loss_mse = lmse;
    eval_cache(cache_key) = ce;
end
