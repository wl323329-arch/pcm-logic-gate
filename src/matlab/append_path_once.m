function path_value = append_path_once(path_value, folder)
%APPEND_PATH_ONCE Append a folder to a path-like string if it is absent.
if isempty(folder)
    return;
end

parts = split(string(path_value), pathsep);
if any(strcmpi(parts, string(folder)))
    return;
end

if isempty(path_value)
    path_value = folder;
else
    path_value = [path_value pathsep folder];
end
end
