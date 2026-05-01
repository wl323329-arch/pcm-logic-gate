function value = get_env_int(name, default_value)
%GET_ENV_INT Read a positive integer from an environment variable.
raw = strtrim(getenv(name));
if isempty(raw)
    value = default_value;
    return;
end

value = str2double(raw);
if ~isfinite(value) || value ~= floor(value) || value < 1
    error('get_env_int:InvalidInteger', ...
        'Environment variable %s must be a positive integer, got "%s".', ...
        name, raw);
end
end
