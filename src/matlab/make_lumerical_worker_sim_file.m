function [worker_sim_file, worker_sim_dir] = make_lumerical_worker_sim_file(sim_file)
%MAKE_LUMERICAL_WORKER_SIM_FILE Create a private simulation file copy.
assert(exist(sim_file, 'file') == 2, ...
    'Worker simulation source file not found: %s', sim_file);

[~, sim_name, sim_ext] = fileparts(sim_file);
assert(~isempty(sim_name) && ~isempty(sim_ext), ...
    'Simulation file must include a file name and extension: %s', sim_file);

worker_sim_dir = tempname;
[ok, msg] = mkdir(worker_sim_dir);
assert(ok, 'Failed to create worker simulation temp directory: %s', msg);

worker_sim_file = fullfile(worker_sim_dir, [sim_name sim_ext]);
try
    [ok, msg] = copyfile(sim_file, worker_sim_file, 'f');
    assert(ok, 'Failed to copy simulation file for worker: %s', msg);

    [ok, msg] = fileattrib(worker_sim_file, '+w');
    assert(ok, 'Failed to make worker simulation file writable: %s', msg);
catch ME
    if exist(worker_sim_dir, 'dir') == 7
        rmdir(worker_sim_dir, 's');
    end
    rethrow(ME);
end
end
