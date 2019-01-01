classdef OCPHandler < handle
  properties (Access = public)
    pathCostsFun
    arrivalCostsFun
    boundaryConditionsFun
    pathConstraintsFun
    discreteCostsFun
  end
  
  properties(Access = private)
    ocp    
    system
    nlpVarsStruct
  end

  methods
    
    function self = OCPHandler(ocp,system,nlpVarsStruct)
      self.ocp = ocp;
      self.system = system;
      
      % variable sizes
      sx = system.statesStruct.size();
      sz = system.algVarsStruct.size();
      su = system.controlsStruct.size();
      sp = system.parametersStruct.size();
      st = [1,1];
      sv = nlpVarsStruct.size;

      fhPC = @(self,varargin) self.getPathCosts(varargin{:});
      self.pathCostsFun = OclFunction(self, fhPC, {sx,sz,su,scalar,st,sp}, 1);
      
      fhAC = @(self,varargin) self.getArrivalCosts(varargin{:});
      self.arrivalCostsFun = OclFunction(self, fhAC, {sx,st,sp}, 1);
      
      fhBC = @(self,varargin)ocp.getBoundaryConditions(varargin{:});
      self.boundaryConditionsFun = OclFunction(self, fhBC, {sx,sx,sp}, 3);
      
      fhPConst = @(ocp,varargin)ocp.getPathConstraints(varargin{:});
      self.pathConstraintsFun = OclFunction(ocp, fhPConst, {sx,sz,su,st,sp}, 3);
      
      fhDC = @(ocp,varargin)ocp.discreteCosts(varargin{:});
      self.discreteCostsFun = OclFunction(ocp, fhDC, {sv}, 3);
      
    end
    
    function r = getPathCosts(self,states,algVars,controls,time,endTime,parameters)
      self.ocp.thisPathCosts = 0;
      x = Variable.create(self.system.statesStruct,states);
      z = Variable.create(self.system.algVarsStruct,algVars);
      u = Variable.create(self.system.controlsStruct,controls);
      t = Variable.createMatrix(time);
      tF = Variable.createMatrix(endTime);
      p = Variable.create(self.system.parametersStruct,parameters);
      
      self.ocp.pathCosts(x,z,u,t,tF,p);
      r = self.ocp.thisPathCosts;
    end
    
    function r = getArrivalCosts(self,states,endTime,parameters)
      self.ocp.thisArrivalCosts = 0;
      x = Variable.create(self.system.statesStruct,states);
      tF = Variable.createMatrix(endTime);
      p = Variable.create(self.system.parametersStruct,parameters);
      
      self.ocp.arrivalCosts(x,tF,p);
      r = self.ocp.thisArrivalCosts;
    end
    
    function [val,lb,ub] = getPathConstraints(self,states,algVars,controls,time,parameters)
      self.ocp.thisPathConstraints = OclConstraint(states);
      x = Variable.create(self.system.statesStruct,states);
      z = Variable.create(self.system.algVarsStruct,algVars);
      u = Variable.create(self.system.controlsStruct,controls);
      t = Variable.createMatrix(time);
      p = Variable.create(self.system.parametersStruct,parameters);
      
      self.ocp.pathConstraints(x,z,u,t,p);
      val = self.ocp.thisPathConstraints.values;
      lb = self.ocp.thisPathConstraints.lowerBounds;
      ub = self.ocp.thisPathConstraints.upperBounds;
    end
    
    function [val,lb,ub] = getBoundaryConditions(self,initialStates,finalStates,parameters)
      self.ocp.thisBoundaryConditions = OclConstraint(initialStates);
      x0 = Variable.create(self.system.statesStruct,initialStates);
      xF = Variable.create(self.system.statesStruct,finalStates);
      p = Variable.create(self.system.parametersStruct,parameters);
      
      self.ocp.boundaryConditions(x0,xF,p);
      val = self.ocp.thisBoundaryConditions.values;
      lb = self.ocp.thisBoundaryConditions.lowerBounds;
      ub = self.ocp.thisBoundaryConditions.upperBounds;
    end
    
    function r = getDiscreteCosts(self,vars)
      self.ocp.discreteCosts = 0;
      v = Variable.create(self.nlpVarsStruct,vars);
      
      self.ocp.discreteCosts(v);
      r = self.ocp.discreteCosts;
    end

    function callbackFunction(self,nlpVars,variableValues)
      nlpVars.set(variableValues);
      self.ocp.iterationCallback(nlpVars);
    end

  end
  
end

