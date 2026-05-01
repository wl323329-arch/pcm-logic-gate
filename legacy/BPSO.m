clear all; close all; clc;

LUM_BIN  = 'D:\Program Files\Lumerical\v231\bin';
LUM_API  = 'D:\Program Files\Lumerical\v231\api\matlab';
SIM_FILE = 'D:\science\Sb2Se3\1.structure\logic_mode.lms';

setenv('PATH',[getenv('PATH') ';' LUM_BIN]);
addpath(LUM_API);

%% 加载数据集及初始化
load train_data;
load train_target;

size_train  = size(train_data);
size_target = size(train_target);

% 规定数据如何加载
train_data = train_data * pi;   % 将训练集数据加载到相位上

%% 设置PSO算法参数（改成二进制材料状态）
N = 50;               % 种群规模
d = 49;                 % 49个孔洞，每个孔洞一个二进制材料变量
ger = 1;                % 最大迭代次数

xlimit = [0, 1];        % 二进制变量范围
vlimit = [-6, 6];       % BPSO里速度一般取一个适中的范围即可
ws = 0.9;               % 惯性权重
we = 0.4;               % 惯性权重
c1 = 1.5;               % 自我学习因子
c2 = 1.5;               % 群体学习因子

SAVE_FILE = 'record.mat';

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% 断点续跑 / 首次运行初始化
resume_ok = false;

if exist(SAVE_FILE, 'file')
    try
        S = load(SAVE_FILE);

        % 必须保证这些变量都存在，且尺寸匹配，才能续跑
        needed_vars = {'x','v','xm','ym','fxm','fym','n_right','CR_worst','loss_mse',...
                       'record','record_time','iter','num','particle_time_sec'};
        has_all = true;
        for ii = 1:length(needed_vars)
            if ~isfield(S, needed_vars{ii})
                has_all = false;
                break;
            end
        end

        if has_all ...
                && isequal(size(S.x), [N,d]) ...
                && isequal(size(S.v), [N,d]) ...
                && isequal(size(S.xm), [N,d]) ...
                && isequal(size(S.ym), [1,d]) ...
                && isequal(size(S.fxm), [N,1]) ...
                && isscalar(S.fym) ...
                && isequal(size(S.n_right), [N,1]) ...
                && isequal(size(S.CR_worst), [N,1]) ...
                && isequal(size(S.loss_mse), [N,1]) ...
                && isequal(size(S.record,1), N)

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

            resume_ok = true;
            fprintf('[INFO] 检测到 record.mat，继续运行。\n');
            fprintf('[INFO] 当前续跑位置：iter = %d, num = %d\n', iter, num);
        end
    catch
        resume_ok = false;
    end
end

if ~resume_ok
    %%%% 首次运行：二进制初始化
    x = double(rand(N,d) > 0.5);    % 初始种群：0/1，分别代表两种材料状态
    v = randn(N,d);                 % 初始速度
    xm = x;                         % 个体历史最佳
    ym = zeros(1,d);                % 群体历史最佳
    fxm = -inf(N,1);                % 个体历史最佳适应度
    fym = -inf;                     % 群体历史最佳适应度
    n_right = zeros(N,1);           % 作对个数
    CR_worst = zeros(N,1);          % 四种逻辑输入下的最差对比度
    loss_mse = zeros(N,1);          % MSE

    % 每个粒子耗时记录（额外保存，不改变record格式）
    particle_time_sec = nan(N,1);

    % record: [x, v, xm, ym, fxm, fym, n_right, CR_worst, loss_mse]
    record = [x, ...
              v, ...
              xm, ...
              repmat(ym,N,1), ...
              fxm, ...
              repmat(fym,N,1), ...
              n_right, ...
              CR_worst, ...
              loss_mse];

    record_time = repmat(string(datetime),N,1);

    iter = 1;       % 代数记录
    num = 1;        % 每代中的第num个粒子
end

%% 添加程序接口路径
path(path, LUM_API);

[sim_file_path, sim_file_name, ~] = fileparts(SIM_FILE);

h = [];
h = appopen('mode');
assert(~isempty(h), 'Failed to open MODE.');

% 下面是将路径变量传给Lumerical
appputvar(h, 'sim_file_path', sim_file_path);
appputvar(h, 'sim_file_name', sim_file_name);

code = strcat('cd(sim_file_path);', ...
              'load(sim_file_name);');
appevalscript(h, code);

%% 群体更新
num_train = 1;  % 第几个训练样本

try
    while iter <= ger

        while num <= N

            t_particle = tic;   % ===== 单个粒子计时开始 =====

            L = x(num,:)';         % 当前粒子的49维二进制材料状态
            set_slot(h, L);        % 修改49个孔洞的材料状态

            p = zeros(size_target);    % 记录各个端口功率

            while num_train <= size_train(1)
                phs = train_data(num_train,:);
                phs = phs * 180/pi;                % 弧度转角度
                p(num_train,:) = train_out(h, phs);
                num_train = num_train + 1;
            end

            % 统计四次逻辑中做对了多少个
            n_right(num,1) = sum(double((p(:,1) > p(:,2))) == ...
                                 (train_target(:,1) > train_target(:,2)));

            % 计算最差对比度：只有四种逻辑全对时才计算，否则置0
            if n_right(num,1) == 4
                CR_each = zeros(4,1);
                eps_val = 1e-30;

                for kk = 1:4
                    if train_target(kk,1) > train_target(kk,2)
                        P_right = abs(p(kk,1));
                        P_wrong = abs(p(kk,2));
                    else
                        P_right = abs(p(kk,2));
                        P_wrong = abs(p(kk,1));
                    end

                    CR_each(kk) = 2 * log10(abs(P_right / (P_wrong + eps_val)));
                end

                CR_worst(num,1) = min(CR_each);
            else
                CR_worst(num,1) = 0;
            end

            % 归一化后计算MSE
            p = p / (max(p,[],"all") + 1e-30);
            loss_mse(num,1) = sumsqr(p - train_target);

            % 适应度：尽量不大改原框架，这里仍以“正确数优先，MSE次之”为原则
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

            % ===== 单个粒子计时结束 =====
            dt_particle = toc(t_particle);
            particle_time_sec(num,1) = dt_particle;

            % ===== 每跑一个粒子就更新record并保存 =====
            record = [x, ...
                      v, ...
                      xm, ...
                      repmat(ym,N,1), ...
                      fxm, ...
                      repmat(fym,N,1), ...
                      n_right, ...
                      CR_worst, ...
                      loss_mse];

            record_time(num,1) = string(datetime);

            % ===== 输出当前进度、平均耗时、预计完成时间 =====
            done_idx = find(~isnan(particle_time_sec));
            done_num = length(done_idx);
            avg_dt = mean(particle_time_sec(done_idx));

            remain_num = N - num;
            eta_sec = remain_num * avg_dt;
            finish_time = datetime('now') + seconds(eta_sec);

            % 当前已经找到多少个 n_right = 4 的结构
            num_right4 = sum(n_right(1:num) == 4);

            fprintf('[进度] 已完成粒子 %d / %d\n', num, N);
            fprintf('[耗时] 当前粒子耗时 = %.2f 秒 | 平均每粒子耗时 = %.2f 秒\n', ...
        dt_particle, avg_dt);
            fprintf('[预计完成时间] 剩余粒子 = %d | 预计完成时间：%s\n', ...
        remain_num, datestr(finish_time,'yyyy-mm-dd HH:MM:SS'));
            fprintf('[统计] 对的结构有 %d 个\n', num_right4);

            % ===== 每跑一个粒子保存一次，支持闪退/中断恢复 =====
            save(SAVE_FILE, ...
                'record', 'record_time', ...
                'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
                'n_right', 'CR_worst', 'loss_mse', ...
                'particle_time_sec', 'iter', 'num', ...
                '-v7.3');

            % 下一个粒子
            num_train = 1;
            num = num + 1;

        end

        % BPSO更新：尽量少改，保留PSO整体框架，只把连续位置更新换成二进制更新
        if iter < ger
            if ger == 1
                w = ws;
            else
                w = ws - (ws - we) * (iter - 1) / (ger - 1);
            end

            r1 = rand(N,d);
            r2 = rand(N,d);

            v = w * v ...
                + c1 * r1 .* (xm - x) ...
                + c2 * r2 .* (repmat(ym,N,1) - x);

            v(v > vlimit(2)) = vlimit(2);
            v(v < vlimit(1)) = vlimit(1);

            % sigmoid映射到翻转概率
            s = 1 ./ (1 + exp(-v));

            % 二进制采样
            x = double(rand(N,d) < s);
        end

        iter = iter + 1;
        num = 1;

        % 代结束后也保存一次
        record = [x, ...
                  v, ...
                  xm, ...
                  repmat(ym,N,1), ...
                  fxm, ...
                  repmat(fym,N,1), ...
                  n_right, ...
                  CR_worst, ...
                  loss_mse];

        save(SAVE_FILE, ...
            'record', 'record_time', ...
            'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
            'n_right', 'CR_worst', 'loss_mse', ...
            'particle_time_sec', 'iter', 'num', ...
            '-v7.3');

    end

catch ME
    % 出错时也尽量保存一次
    try
        record = [x, ...
                  v, ...
                  xm, ...
                  repmat(ym,N,1), ...
                  fxm, ...
                  repmat(fym,N,1), ...
                  n_right, ...
                  CR_worst, ...
                  loss_mse];

        save(SAVE_FILE, ...
            'record', 'record_time', ...
            'x', 'v', 'xm', 'ym', 'fxm', 'fym', ...
            'n_right', 'CR_worst', 'loss_mse', ...
            'particle_time_sec', 'iter', 'num', ...
            '-v7.3');
    catch
    end

    if ~isempty(h)
        try
            appclose(h);
        catch
        end
    end
    rethrow(ME);
end

if ~isempty(h)
    appclose(h);
end