function p = train_out(h, phs)
% 设置源相位并运行仿真，直接获取监视器透过率 T
code = strcat('switchtolayout;', ...
              'select("source1");', ...
              'set("phase",', num2str(phs(1),16), ');', ...
              'select("source2");', ...
              'set("phase",', num2str(phs(2),16), ');', ...
              'select("source3");', ...
              'set("phase",', num2str(phs(3),16), ');', ...
              'run;');
appevalscript(h, code);

% 直接获取透过率（无文件 I/O）
code2 = strcat('T1 = transmission("output1");', ...
               'T2 = transmission("output2");');
appevalscript(h, code2);

T1 = appgetvar(h, 'T1');
T2 = appgetvar(h, 'T2');

% 错误检查：仿真失败可能返回空或 NaN
assert(~isempty(T1) && ~isempty(T2), ...
    'transmission() 返回空值，仿真可能失败。');
if any(isnan(T1)) || any(isnan(T2))
    warning('train_out:NaN', 'transmission() 返回 NaN，输出置零。');
    p = [0, 0];
    return;
end

% transmission() 可能返回向量（多频率），取第一个频率点
if numel(T1) > 1, T1 = T1(1); end
if numel(T2) > 1, T2 = T2(1); end

% 负透过率警告（反向传播）
if T1 < 0 || T2 < 0
    warning('train_out:NegT', ...
        '检测到负透过率 (T1=%.4e, T2=%.4e)，可能存在反向传播。', T1, T2);
end

p = [abs(T1), abs(T2)];
end
