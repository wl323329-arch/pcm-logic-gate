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

%% 加载最优结构和训练数据
S = load(fullfile(SCRIPT_DIR, 'record_unified.mat'), 'ym', 'fym', 'seed_pool', 'seed_pool_cr');
load(fullfile(SCRIPT_DIR, 'train_data.mat'));
load(fullfile(SCRIPT_DIR, 'train_target.mat'));

train_data = train_data * pi;   % 与 BPSO_unified 一致

ym  = S.ym;     % 1x49 全局最优二进制结构
fym = S.fym;    % 全局最优适应度

fprintf('最优结构 ym: %s\n', char(ym + '0'));
fprintf('记录的 fym = %.6f dB\n\n', fym);

%% 打印种子池信息
fprintf('===== 种子池 (%d 个全对结构) =====\n', size(S.seed_pool, 1));
for si = 1:size(S.seed_pool, 1)
    fprintf('  种子 %d: CR_worst = %.4f dB\n', si, S.seed_pool_cr(si));
end
fprintf('\n');

%% 打开 Lumerical MODE
h = appopen('mode');
assert(~isempty(h), 'Failed to open MODE.');

[sim_file_path, sim_file_name, ~] = fileparts(SIM_FILE);
appputvar(h, 'sim_file_path', sim_file_path);
appputvar(h, 'sim_file_name', sim_file_name);
appevalscript(h, strcat('cd(sim_file_path);', 'load(sim_file_name);'));

%% 设置最优结构材料
L = ym';
set_slot(h, L);

%% 逐逻辑态仿真
size_train  = size(train_data);
size_target = size(train_target);

p_final = zeros(size_target);
for tt = 1:size_train(1)
    phs = train_data(tt,:) * 180/pi;   % 弧度 -> 度
    p_final(tt,:) = train_out(h, phs);
    fprintf('逻辑态 %d: P1 = %.6e, P2 = %.6e\n', tt, p_final(tt,1), p_final(tt,2));
end

%% 计算对比度 CR
eps_val = 1e-30;
CR_each = zeros(size_train(1), 1);

fprintf('\n===== 光学对比度 =====\n');
for kk = 1:size_train(1)
    if train_target(kk,1) > train_target(kk,2)
        P_right = abs(p_final(kk,1));
        P_wrong = abs(p_final(kk,2));
    else
        P_right = abs(p_final(kk,2));
        P_wrong = abs(p_final(kk,1));
    end
    CR_each(kk) = 10 * log10(abs(P_right / (P_wrong + eps_val)));
    fprintf('  逻辑态 %d: P_right = %.6e, P_wrong = %.6e, CR = %.4f dB\n', ...
        kk, P_right, P_wrong, CR_each(kk));
end

fprintf('\nCR_worst = %.4f dB\n', min(CR_each));
fprintf('CR_best  = %.4f dB\n', max(CR_each));
fprintf('CR_mean  = %.4f dB\n', mean(CR_each));

%% 关闭 Lumerical
appclose(h);
fprintf('\n验证完成。\n');
