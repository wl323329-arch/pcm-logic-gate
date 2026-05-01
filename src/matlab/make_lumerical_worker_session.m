function session = make_lumerical_worker_session(sim_file, lum_bin, lum_api, matA, matB, d)
session = LumericalWorkerSession(sim_file, lum_bin, lum_api, matA, matB, d);
end
