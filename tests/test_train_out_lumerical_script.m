function tests = test_train_out_lumerical_script()
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
project_dir = fileparts(fileparts(mfilename('fullpath')));
src_dir = fullfile(project_dir, 'src', 'matlab');
addpath(src_dir);
testCase.TestData.src_dir = src_dir;
end

function testTrainOutReadsOutputPowerData(testCase)
old_path = path;
cleanup_path = onCleanup(@() path(old_path));

mock_dir = tempname;
mkdir(mock_dir);
cleanup_dir = onCleanup(@() cleanup_mock_dir(mock_dir));

write_text_file(fullfile(mock_dir, 'appevalscript.m'), {
    'function appevalscript(~, code)'
    'global PCM_TEST_LUM_SCRIPT PCM_TEST_LUM_VARS'
    'PCM_TEST_LUM_SCRIPT{end+1} = code;'
    'if contains(code, ''transmission('')'
    '    error(''MockLumerical:TransmissionUnsupported'', ''Failed to evaluate script'');'
    'end'
    'if contains(code, ''getdata("output1","power")'')'
    '    PCM_TEST_LUM_VARS.T1 = [2, 20];'
    'end'
    'if contains(code, ''getdata("output2","power")'')'
    '    PCM_TEST_LUM_VARS.T2 = [3, 30];'
    'end'
    'end'
    });

write_text_file(fullfile(mock_dir, 'appgetvar.m'), {
    'function value = appgetvar(~, name)'
    'global PCM_TEST_LUM_VARS'
    'if ~isfield(PCM_TEST_LUM_VARS, name)'
    '    error(''MockLumerical:MissingVariable'', ''Missing variable: %s'', name);'
    'end'
    'value = PCM_TEST_LUM_VARS.(name);'
    'end'
    });

addpath(mock_dir, '-begin');
addpath(testCase.TestData.src_dir, '-end');
clear appevalscript appgetvar train_out

global PCM_TEST_LUM_SCRIPT PCM_TEST_LUM_VARS
PCM_TEST_LUM_SCRIPT = {};
PCM_TEST_LUM_VARS = struct();

p = train_out(42, [0, 90, 180]);

verifyEqual(testCase, p, [2, 3]);
verifyTrue(testCase, any(contains(PCM_TEST_LUM_SCRIPT, 'getdata("output1","power")')));
verifyTrue(testCase, any(contains(PCM_TEST_LUM_SCRIPT, 'getdata("output2","power")')));
verifyFalse(testCase, any(contains(PCM_TEST_LUM_SCRIPT, 'transmission(')));

cleanup_path.delete();
cleanup_dir.delete();
clear appevalscript appgetvar train_out
end

function write_text_file(file_path, lines)
fid = fopen(file_path, 'w');
assert(fid > 0, 'Failed to open %s for writing.', file_path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s\n', lines{:});
cleanup.delete();
end

function cleanup_mock_dir(mock_dir)
if exist(mock_dir, 'dir')
    rmdir(mock_dir, 's');
end
end
