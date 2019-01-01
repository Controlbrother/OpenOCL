classdef CasadiNLPSolver < Solver
  
  properties (Access = private)
    timeMeasures
    nlpData
    nlp
    options
  end
  
  methods
    
    function self = CasadiNLPSolver(nlp,options)
      
      [self.nlpData,self.timeMeasures] = self.construct(nlp,options);
      
      self.nlp = nlp;
      self.options = options;
    end
    
    function [nlpData,timeMeasures] = construct(self,nlp,options)
      
      constructTotalTic = tic;
      
      % create variables as casadi symbolics
      varsStruct = nlp.varsStruct;
      vars = cell(length(varsStruct),1);
      for k=1:length(varsStruct);
        vars = casadi.MX.sym('v',varsStruct{k}.size); % TODO
      end
      vars = vertcat(vars{:});
      
      % apply scaling to variables
      if options.nlp.scaling
        
        [scalingMin,scalingMax] = nlp.getScaling();
        
        % see if scaling information is available for all variables
        % either from bounds or setScaling
        nlp.checkScaling();
        
        % do not scale parameters and variables zero range scaling
        zeroRange = find((scalingMax-scalingMin)==0);
        scalingMin(zeroRange) = 0;
        scalingMax(zeroRange) = 1;
        
        % get unscaled symbolic vars
        vars = self.unscale(vars',scalingMin,scalingMax);
      end

      % call nlp function with scaled variables
      [costs,constraints,constraints_LB,constraints_UB] = nlp.nlpFun.evaluate(vars);
      
      % get struct with nlp for casadi
      casadiNLP = struct;
      casadiNLP.x = vars;
      casadiNLP.f = costs;
      casadiNLP.g = constraints;
      casadiNLP.p = casadi.MX.sym('p',[0,1]);
      
      opts = options.nlp.casadi;
      
      if isfield(options.nlp,self.options.nlp.solver)
        opts.(options.nlp.solver) = options.nlp.(self.options.nlp.solver);
      end
      
      if options.iterationCallback
        callbackFun = IterationCallback('itCbFun', ...
          numel(vars), numel(constraints), numel(psym), ...
          @(values)self.callBackHandle(values,initialGuess,varIndizes,paramIndizes,params,...
                                       scalingMin,scalingMax) );
        opts.iteration_callback = callbackFun;
      end

      nlpData = struct;
      nlpData.casadiNLP = casadiNLP;
      nlpData.constraints_LB = constraints_LB;
      nlpData.constraints_UB = constraints_UB;
      timeMeasures.constructTotal = toc(constructTotalTic);
    end
    
    function [outVars,times,objective,constraints] = solve(self,initialGuess)
      % solve(initialGuess)
      
      solveTotalTic = tic;
      
      % detect variables as parameters if they are constant (lb==ub)
      nv = nlpFun.inputSizes{1};
      [lbv,ubv] = self.nlp.getBounds(self);
      paramIndizes = [];
      params = [];
      varIndizes = 1:nv;
      if (self.options.nlp.detectParameters)
        % find parameters
        paramIndizes = find((lbv-ubv)==0);
        % get parameter values
        params = lbv(paramIndizes);
        % get indizes of variables (in constrast to parameters)
        varIndizes(paramIndizes) = [];
        % bounds after removing parameters
        lbv = lbv(varIndizes);
        ubv = ubv(varIndizes);
      end
      self.nlpData.casadiNLP.p = casadi.MX.sym('p',size(params));
      self.nlpData.parameters = self.nlpData.casadiNLP.x(paramIndizes);
      
      v0 = initialGuess.value;
      
      % scale initial guess and bounds
      if self.options.nlp.scaling
        [scalingMin,scalingMax] = self.nlp.getScaling();
        
        scalingMinVars = scalingMin(self.indizes.vars);
        scalingMaxVars = scalingMax(self.indizes.vars);
        scalingMinParams = scalingMin(self.indizes.param);
        scalingMaxParams = scalingMax(self.indizes.param);
        
        v0 = self.scale(v0,scalingMinVars,scalingMaxVars);
        lbv = self.scale(lbv,scalingMinVars,scalingMaxVars);
        ubv = self.scale(ubv,scalingMinVars,scalingMaxVars);
        params = self.scale(params,scalingMinParams,scalingMaxParams);
      end
      
      constructSolverTic = tic;
      self.casadiSolver = casadi.nlpsol('my_solver', self.options.nlp.solver,... 
                                        self.nlpData.casadiNLP, opts);
      constructSolverTime = toc(constructSolverTic);
      
      args = struct;
      args.lbg = self.nlpData.constraints_LB;
      args.ubg = self.nlpData.constraints_UB;
      args.p = params;
      args.lbx = lbv;
      args.ubx = ubv;
      args.x0 = v0;
      
      % execute solver
      solveCasadiTic = tic;
      sol = self.casadiSolver.call(args);
      solveCasadiTime = toc(solveCasadiTic);
      
      if strcmp(self.options.nlp.solver,'ipopt') && strcmp(self.casadiSolver.stats().return_status,'NonIpopt_Exception_Thrown')
        error('Solver was interrupted by user.');
      end
      
      solution = sol.x.full();
      
      %remove scaling from solution
      if self.options.nlp.scaling
        solution = self.unscale(solution,scalingMinVars,scalingMaxVars);
      end
      
      initialGuess(varIndizes) = solution;
      initialGuess(paramIndizes) = params;
      
      nlpFunEvalTic = tic;
      if nargout > 1
        [objective,constraints,~,~,times] = self.nlp.nlpFun.evaluate(initialGuess);
      end
      nlpFunEvalTime = toc(nlpFunEvalTic);

      outVars = initialGuess;
      
      self.timeMeasures.solveTotal      = toc(solveTotalTic);
      self.timeMeasures.solveCasadi     = solveCasadiTime;
      self.timeMeasures.constructSolver = constructSolverTime;
      self.timeMeasures.nlpFunEval      = nlpFunEvalTime;
    end
  end
  
  methods(Access = private)
    
    function callBackHandle(self,values,vars,varIndizes,paramIndizes,params,options,scalingMin,scalingMax)
      
      v = vars.value;
      v(varIndizes) = values;
      
      %remove scaling from decision variables
      if options.nlp.scaling
        v = self.unscale(v,scalingMin,scalingMax);
      end
      % replace parameters
      if options.nlp.detectParameters
        v(paramIndizes) = params;
      end
      self.nlp.getCallback(vars,v);
    end
    
    function xscaled = scale(~,x,xmin,xmax)
      xscaled = (x - xmin) ./ (xmax-xmin);
    end
    
    function x = unscale(~,xscaled,xmin,xmax)
      x = xscaled.*(xmax-xmin)+xmin;
    end
    
  end
  
end
