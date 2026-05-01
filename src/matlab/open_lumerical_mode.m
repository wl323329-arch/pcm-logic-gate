function h = open_lumerical_mode(sim_file)
%OPEN_LUMERICAL_MODE Open MODE and load the requested simulation file.
[sim_file_path, sim_file_name, ~] = fileparts(sim_file);
h = appopen('mode');
assert(~isempty(h), 'Failed to open MODE.');

appputvar(h, 'sim_file_path', sim_file_path);
appputvar(h, 'sim_file_name', sim_file_name);
appevalscript(h, strcat('cd(sim_file_path);', 'load(sim_file_name);'));
end
