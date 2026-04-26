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

%% 加载最优结构
S = load(fullfile(SCRIPT_DIR, 'record_unified.mat'), 'ym', 'fym');
ym = S.ym;
fprintf('最优结构: %s\n', char(ym + '0'));
fprintf('fym = %.4f dB\n', S.fym);

%% 打开 Lumerical MODE 并加载仿真文件
h = appopen('mode');
[sim_file_path, sim_file_name, ~] = fileparts(SIM_FILE);
appputvar(h, 'sim_file_path', sim_file_path);
appputvar(h, 'sim_file_name', sim_file_name);
appevalscript(h, strcat('cd(sim_file_path);', 'load(sim_file_name);'));

%% 设置最优结构材料
set_slot(h, ym');

%% 加载训练数据
load(fullfile(SCRIPT_DIR, 'train_data.mat'));
load(fullfile(SCRIPT_DIR, 'train_target.mat'));
train_data = train_data * pi;

fprintf('已将最优结构导入 Lumerical。\n\n');
fprintf('逻辑态列表:\n');
for i = 1:size(train_data, 1)
    phs = train_data(i,:) * 180/pi;
    fprintf('  %d: source1=%.0f° source2=%.0f° source3=%.0f°\n', i, phs);
end
fprintf('\n');

%% 选择逻辑态并设置相位
logic_idx = input('请输入逻辑态编号 (1~4): ');

while ~isempty(logic_idx)
    if logic_idx < 1 || logic_idx > size(train_data, 1)
        fprintf('无效编号，请输入 1~%d\n', size(train_data, 1));
    else
        phs = train_data(logic_idx, :) * 180/pi;
        code = strcat('switchtolayout;', ...
            'select("source1");', 'set("phase",', num2str(phs(1),16), ');', ...
            'select("source2");', 'set("phase",', num2str(phs(2),16), ');', ...
            'select("source3");', 'set("phase",', num2str(phs(3),16), ');');
        appevalscript(h, code);
        fprintf('逻辑态 %d 相位已设置: [%.0f°, %.0f°, %.0f°]\n', logic_idx, phs);
        fprintf('请在 Lumerical GUI 中运行仿真并查看结果。\n\n');
    end
    logic_idx = input('请输入下一个逻辑态编号 (1~4，直接回车退出): ');
end

fprintf('退出。\n');
