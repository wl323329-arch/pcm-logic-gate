function set_slot(h, L)

N = 49;                 % 孔洞个数
c = zeros(N,1);
c = round(L(1:N));      % 取二进制材料状态，0/1

matA = 'A_Sb2Se3';      % 非晶态
matB = 'B_Sb2Se3';      % 晶态

% 构建脚本：不再修改x/y，只修改每个gra的material
code = 'switchtolayout;';

for i = 1:N
    name = ['gra', num2str(i)];

    if c(i) == 0
        mat_name = matA;
    else
        mat_name = matB;
    end

    code = [code, ...
            'select("', name, '");', ...
            'set("material","', mat_name, '");'];
end

appevalscript(h, code);
end