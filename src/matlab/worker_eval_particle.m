function result = worker_eval_particle(session, L, train_data, train_target, size_train, size_target, tau, lambda_balance, full_eval)
result = session.evalParticle(L, train_data, train_target, size_train, size_target, tau, lambda_balance, full_eval);
end
