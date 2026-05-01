function close_lumerical_worker_session(session)
if ~isempty(session)
    delete(session);
end
end
