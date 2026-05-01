clear all; close all; clc;

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

setenv('PATH', [getenv('PATH') ';' LUM_BIN]);
addpath(LUM_API);
addpath(SCRIPT_DIR);

%% 加载最优结构和训练数据
S = load(fullfile(RESULTS_DIR, 'record_unified.mat'), 'ym');
load(fullfile(DATA_DIR, 'train_data.mat'));
train_data = train_data * pi;

ym = S.ym;
fprintf('最优结构: %s\n', char(ym + '0'));

%% 选择要画的逻辑态（修改此处切换输入组合）
% train_data 每行对应一个逻辑态，选第几行就画哪个态
logic_idx = 2;   % 例如第3行可能是 '1','1' 输入
phs = train_data(logic_idx, :) * 180/pi;
fprintf('绘制逻辑态 %d, 相位 = [%.1f, %.1f, %.1f] deg\n', logic_idx, phs);

%% 打开 Lumerical MODE
h = appopen('mode');
[sim_file_path, sim_file_name, ~] = fileparts(SIM_FILE);
appputvar(h, 'sim_file_path', sim_file_path);
appputvar(h, 'sim_file_name', sim_file_name);
appevalscript(h, strcat('cd(sim_file_path);', 'load(sim_file_name);'));

%% 设置最优结构材料
set_slot(h, ym');

%% 设置 source 相位并运行
code = strcat('switchtolayout;', ...
    'select("source1");', 'set("phase",', num2str(phs(1),16), ');', ...
    'select("source2");', 'set("phase",', num2str(phs(2),16), ');', ...
    'select("source3");', 'set("phase",', num2str(phs(3),16), ');', ...
    'run;');
appevalscript(h, code);

%% 从 field profile monitor 提取场数据
% 注意：需要你的 .lms 文件中有一个覆盖全结构的 field profile monitor
% 常见名称如 "profile", "field", "monitor" 等，请根据实际名称修改
monitor_name = 'monitor';

code = strcat(...
    'A = getresult("', monitor_name, '","E");', ...
    'matlabsave("field_data", A);');
appevalscript(h, code);

%% 加载场数据并绘图
load(fullfile(STRUCTURE_DIR, 'field_data.mat'));

% A.E 是展平的 [N, 3]，3列分别是 Ex, Ey, Ez
% 需要用 A.x, A.y 重建二维网格
xu = unique(A.x);
yu = unique(A.y);
nx = length(xu);
ny = length(yu);
fprintf('网格: nx=%d, ny=%d, 总点数=%d\n', nx, ny, nx*ny);

% 计算 |E|^2 = |Ex|^2 + |Ey|^2 + |Ez|^2
E2 = sum(abs(A.E).^2, 2);

% 重塑为二维矩阵 [nx, ny]
E_intensity = reshape(E2, nx, ny);
E_intensity = E_intensity / max(E_intensity(:));

%% 确定输入/输出的逻辑标签
% source1, source2 是逻辑输入；根据相位判断 '0'/'1'
input_labels = cell(1, 3);
for si = 1:3
    if phs(si) >= 90
        input_labels{si} = '''1''';
    else
        input_labels{si} = '''0''';
    end
end

% 输出标签：根据 train_target 判断哪个输出是 '1'
load(fullfile(DATA_DIR, 'train_target.mat'));
if train_target(logic_idx, 1) > train_target(logic_idx, 2)
    out_label = '''1''';   % output1 更强
else
    out_label = '''1''';   % output2 更强
end

%% 找输入/输出波导的 y 位置（多列平均 + 自适应阈值）
y_um = yu * 1e6;
x_um = xu * 1e6;

% 左侧取前 20 列平均
n_avg = min(20, nx);
left_profile = mean(E_intensity(1:n_avg, :), 1);
left_profile = left_profile / max(left_profile);
[~, peak_locs] = findpeaks(left_profile, 'MinPeakHeight', 0.3, 'MinPeakDistance', 10);
input_y = sort(y_um(peak_locs), 'descend');
fprintf('检测到 %d 个输入波导, y = %s um\n', length(input_y), mat2str(input_y, 3));

% 右侧取后 20 列平均
right_profile = mean(E_intensity(end-n_avg+1:end, :), 1);
right_profile = right_profile / max(right_profile);
[~, peak_locs_r] = findpeaks(right_profile, 'MinPeakHeight', 0.15, 'MinPeakDistance', 10);
output_y = sort(y_um(peak_locs_r));
fprintf('检测到 %d 个输出波导, y = %s um\n', length(output_y), mat2str(output_y, 3));

%% 画图 — 仿论文风格
figure('Position', [100 100 800 400]);
imagesc(x_um, y_um, E_intensity');
set(gca, 'YDir', 'normal');
colormap('jet');
cb = colorbar;
clim([0 1]);
set(gca, 'XTick', [], 'YTick', []);   % 去掉坐标刻度
set(gca, 'XColor', 'none', 'YColor', 'none');  % 去掉坐标轴线

% 添加输入标签（左侧）
for si = 1:min(length(input_y), 3)
    text(x_um(1) - 0.3, input_y(si), input_labels{si}, ...
        'FontSize', 14, 'FontWeight', 'bold', 'Color', 'w', ...
        'HorizontalAlignment', 'right', 'VerticalAlignment', 'middle');
end

% 添加输出标签（右侧）
if ~isempty(output_y)
    % 找功率更大的输出端
    if train_target(logic_idx, 1) > train_target(logic_idx, 2)
        out_y_pos = max(output_y);
    else
        out_y_pos = min(output_y);
    end
    text(x_um(end) + 0.3, out_y_pos, out_label, ...
        'FontSize', 14, 'FontWeight', 'bold', 'Color', 'w', ...
        'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
end

axis equal tight;

%% 关闭 Lumerical
appclose(h);
fprintf('绘图完成。\n');
