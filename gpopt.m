% Copyright (c) 2017 Zi Wang
% This function is partially adapted from the code for the paper
% Hernández-Lobato J. M., Hoffman M. W. and Ghahramani Z.
% Predictive Entropy Search for Efficient Global Optimization of Black-box
% Functions, In NIPS, 2014.
% https://bitbucket.org/jmh233/codepesnips2014
function results = gpopt(objective, xmin, xmax, T, initx, inity, options)
% This function maximizes the function objective via BO and returns results
% as a cell of size 7, including the inferred argmax points (guesses),
% the function values of the inferred argmax points (guessvals), the
% evaluated points (xx), the function values of the evaluated points
% (yy), the runtime to choose the points (choose_time) and extra time of
% inferring the argmax (extra_time).
% objective is a function handle;
% xmin is a column vector indicating the lower bound of the search space;
% xmax is a column vector indicating the upper bound of the search space;
% T is the number of sequential evaluations of the function;
% initx, inity are the initialization of observed inputs and their values.

if nargin <= 6
    options = struct();
end

if ~isfield(options, 'bo_method'); options.bo_method = 'JES'; end
% When testing synthetic functions, one can add noise to the output.

% Number of hyper parameter settings to be sampled.
if isfield(options, 'nM'); nM = options.nM; else nM = 10; end
% Number of maximums to be sampled.
if isfield(options, 'nK'); nK = options.nK; else nK = 10; end
if isfield(options, 'epsilon'); epsilon = options.epsilon; else epsilon = 0.1; end
if isfield(options, 'nFeatures')
    nFeatures = options.nFeatures;
else
    nFeatures = 1000;
end
if ~isfield(options, 'seed'); options.seed = 42; end
if ~isfield(options, 'learn_interval'); options.learn_interval = 10; end
if ~isfield(options, 'normalize'); options.normalize = 0; end

if ~isfield(options, 'InferObjective')
     disp('No infer objetive')
     infer_objective = objective;
else
    infer_objective = options.InferObjective
end
infer_objective = infer_objective 

% Set random seed
s = RandStream('mcg16807','Seed', options.seed);
RandStream.setGlobalStream(s);

if isempty(initx)
        % initialize xx,yy with at least one pair of intx, inty
    for d = 1:options.n_init
        x_doe = rand_sample_interval(xmin, xmax, 1)
        initx = [initx; x_doe]
        inity = [inity; objective(x_doe)]
    end       

    guesses = initx;    
    guessvals = inity;
    choose_time = []; % elapsed time to choose where to evaluate
    extra_time = []; % elapsed time to optimize mean funcKernelMatrixInvtion, hyper-parameters
    tstart = 0;
end
xx = initx;
    
if options.normalize
    yy = normalize(inity);
    unnorm_yy = inity;
else
    yy = inity;
    unnorm_yy = inity;
end
% We sample from the posterior distribution of the hyper-parameters
% No, we set them beforehand
[ l, sigma, sigma0 ] = sampleHypers(xx, yy, nM, options);

KernelMatrixInv = cell(1, nM);
for j = 1 : nM
    KernelMatrix = computeKmm(xx, l(j,:)', sigma(j), sigma0(j));
    KernelMatrixInv{ j } = chol2invchol(KernelMatrix);
end

results = cell(1,7);
for t = tstart+1 : T
    
    tic
    
    if strcmp(options.bo_method, 'JES')
        [optimum, acqval] = jes_choose(nM, nK, xx, yy, KernelMatrixInv, ...
        guesses, sigma0, sigma, l, xmin, xmax, nFeatures, epsilon);
    elseif strcmp(options.bo_method, 'MES-R')
        optimum = mesr_choose(nM, nK, xx, yy, KernelMatrixInv, ...
            guesses, sigma0, sigma, l, xmin, xmax, nFeatures);
    elseif strcmp(options.bo_method, 'MES')
        optimum = mesg_choose(nM, nK, xx, yy, KernelMatrixInv, ...
        guesses, sigma0, sigma, l, xmin, xmax);
    elseif strcmp(options.bo_method, 'PES')
        [optimum, acqval] = pes_choose(nM, nK, xx, -yy, KernelMatrixInv, ...
        guesses, sigma0, sigma, l, xmin, xmax, nFeatures, epsilon);
    elseif strcmp(options.bo_method, 'FITBO')
        optimum = fitbo_choose(nM, nK, xx, yy, KernelMatrixInv, ...
            guesses, sigma0, sigma, l, xmin, xmax);
    elseif strcmp(options.bo_method, 'EI')
        optimum = ei_choose(xx, yy, KernelMatrixInv, guesses, ...
            sigma0, sigma, l, xmin, xmax);
    elseif strcmp(options.bo_method, 'PI')
        optimum = pi_choose(xx, yy, KernelMatrixInv, guesses, ...
            sigma0, sigma, l, xmin, xmax);
    elseif strcmp(options.bo_method, 'UCB')
        alpha = 1;
        beta = (2*log(t^2*2*pi^2/(3*0.01)) + 2*length(xmin)*log(t^2*...
            length(xmin)*max(xmax-xmin)*(log(4*length(xmin)/0.01))^0.5))^0.5;
        optimum = ucb_choose(xx, yy, KernelMatrixInv, guesses, ...
            sigma0, sigma, l, xmin, xmax, alpha, beta);
    elseif strcmp(options.bo_method, 'EST')
        optimum = est_choose(nM, xx, yy, KernelMatrixInv, guesses, ...
            sigma0, sigma, l, xmin, xmax);
    else
        disp('No such BO method.')
        return;
    end
    ra = rand();
    if  (ra < epsilon)
        % We optimize the posterior mean of the GP
        f = @(x) -posteriorMean(x, xx, yy, KernelMatrixInv, l, sigma);
        gf = @(x) -gradientPosteriorMean(x, xx, yy, KernelMatrixInv, l, sigma);
        [optimum, guessval] = globalOptimization(f, gf, xmin, xmax, guesses);
    end
        % We optimize the posterior mean of the GP
        
        
    xx = [ xx ; optimum ];
    
    unnorm_yy = [ unnorm_yy ; objective(optimum)];
    if options.normalize
        yy = normalize(unnorm_yy);
    else
        yy = unnorm_yy;
    end
    
    if mod(t, options.learn_interval) == 0
        % We sample from the posterior distribution of the hyper-parameters
        [ l, sigma, sigma0 ] = sampleHypers(xx, yy, nM, options);
    end
    % We update the inverse of the gram matrix on the samples
    
    KernelMatrixInv = cell(1, nM);
    for j = 1 : nM
        KernelMatrix = computeKmm(xx, l(j,:)', sigma(j), sigma0(j));
        KernelMatrixInv{ j } = chol2invchol(KernelMatrix);
    end
    
    choose_time = [choose_time; toc];
    
    tic

    % We optimize the posterior mean of the GP
	f = @(x) -posteriorMean(x, xx, yy, KernelMatrixInv, l, sigma);
	gf = @(x) -gradientPosteriorMean(x, xx, yy, KernelMatrixInv, l, sigma);

	% We optimize the posterior mean of the GP
	
	[optimum, guessval] = globalOptimization(f, gf, xmin, xmax, guesses);
    
	% We optimize the posterior mean of the GP
	extra_time = [extra_time; toc];
    
    guesses = [ guesses ; optimum ];

    disp([num2str(t) ': tested ' num2str(xx(end,:)) '; val=' num2str(yy(end,:)) ...
        '; guess ' num2str(optimum) '; guessval ' num2str(-guessval)])
    

end
for i = 1:size(guesses, 1)
    infer_objective(guesses(i, :));
end
