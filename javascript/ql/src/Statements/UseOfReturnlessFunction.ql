/**
 * @name Use of returnless function
 * @description Using the return value of a function that does not return an expression is indicative of a mistake.
 * @kind problem
 * @problem.severity warning
 * @id js/use-of-returnless-function
 * @tags maintainability
 *       correctness
 * @precision high
 */

import javascript
import Declarations.UnusedVariable
import Expressions.ExprHasNoEffect
import Statements.UselessConditional

predicate returnsVoid(Function f) {
  not f.isGenerator() and
  not f.isAsync() and
  not exists(f.getAReturnedExpr())
}

predicate isStub(Function f) {
    f.getBody().(BlockStmt).getNumChild() = 0 
    or
    f instanceof ExternalDecl
}

/**
 * Holds if `e` is in a syntactic context where it likely is fine that the value of `e` comes from a call to a returnless function.
 */
predicate benignContext(Expr e) {
  inVoidContext(e) or 
  
  // A return statement is often used to just end the function.
  e = any(Function f).getAReturnedExpr()
  or 
  exists(ConditionalExpr cond | cond.getABranch() = e and benignContext(cond)) 
  or 
  exists(LogicalBinaryExpr bin | bin.getAnOperand() = e and benignContext(bin)) 
  or
  exists(Expr parent | parent.getUnderlyingValue() = e and benignContext(parent))
  or 
  any(VoidExpr voidExpr).getOperand() = e

  or
  // weeds out calls inside HTML-attributes.
  e.getParent().(ExprStmt).getParent() instanceof CodeInAttribute or
  // and JSX-attributes.
  e = any(JSXAttribute attr).getValue() or 
  
  exists(AwaitExpr await | await.getOperand() = e and benignContext(await)) 
  or
  // Avoid double reporting with js/trivial-conditional
  isExplicitConditional(_, e)
  or 
  // Avoid double reporting with js/comparison-between-incompatible-types
  any(Comparison binOp).getAnOperand() = e
  or
  // Avoid double reporting with js/property-access-on-non-object
  any(PropAccess ac).getBase() = e
  or
  // Avoid double-reporting with js/unused-local-variable
  exists(VariableDeclarator v | v.getInit() = e and v.getBindingPattern().getVariable() instanceof UnusedLocal)
  or
  // Avoid double reporting with js/call-to-non-callable
  any(InvokeExpr invoke).getCallee() = e
  or
  // arguments to Promise.resolve (and promise library variants) are benign. 
  e = any(ResolvedPromiseDefinition promise).getValue().asExpr()
}

predicate oneshotClosure(InvokeExpr call) {
  call.getCallee().getUnderlyingValue() instanceof ImmediatelyInvokedFunctionExpr
}

predicate alwaysThrows(Function f) {
  exists(ReachableBasicBlock entry, DataFlow::Node throwNode |
    entry = f.getEntryBB() and
    throwNode.asExpr() = any(ThrowStmt t).getExpr() and
    entry.dominates(throwNode.getBasicBlock())
  )
}

/**
 * Holds if the last statement in the function is flagged by the js/useless-expression query.
 */
predicate lastStatementHasNoEffect(Function f) {
  hasNoEffect(f.getExit().getAPredecessor())
}

/**
 * Holds if `func` is a callee of `call`, and all possible callees of `call` never return a value.
 */
predicate callToVoidFunction(DataFlow::CallNode call, Function func) {
  not call.isIncomplete() and 
  func = call.getACallee() and
  forall(Function f | f = call.getACallee() |
    returnsVoid(f) and not isStub(f) and not alwaysThrows(f)
  )
}

/**
 * Holds if `name` is the name of a method from `Array.prototype` or Lodash,
 * where that method takes a callback as parameter,
 * and the callback is expected to return a value.
 */
predicate hasNonVoidCallbackMethod(string name) {
  name = "every" or
  name = "filter" or
  name = "find" or
  name = "findIndex" or
  name = "flatMap" or
  name = "map" or
  name = "reduce" or
  name = "reduceRight" or
  name = "some" or
  name = "sort"
}

DataFlow::SourceNode array(DataFlow::TypeTracker t) {
  t.start() and result instanceof DataFlow::ArrayCreationNode
  or
  exists (DataFlow::TypeTracker t2 |
    result = array(t2).track(t2, t)
  )
}

DataFlow::SourceNode array() { result = array(DataFlow::TypeTracker::end()) }

/**
 * Holds if `call` is an Array or Lodash method accepting a callback `func`,
 * where the `call` expects a callback that returns an expression, 
 * but `func` does not return a value. 
 */
predicate voidArrayCallback(DataFlow::CallNode call, Function func) {
  hasNonVoidCallbackMethod(call.getCalleeName()) and
  exists(int index | 
    index = min(int i | exists(call.getCallback(i))) and 
    func = call.getCallback(index).getFunction()
  ) and
  returnsVoid(func) and
  not isStub(func) and
  not alwaysThrows(func) and
  (
    call.getReceiver().getALocalSource() = array()
    or
    call.getCalleeNode().getALocalSource() instanceof LodashUnderscore::Member
  )
}


/**
 * Provides classes for working with various Deferred implementations. 
 * It is a heuristic. The heuristic assume that a class is a promise defintion 
 * if the class is called "Deferred" and the method `resolve` is called on an instance.
 *  
 * Removes some false positives in the js/use-of-returnless-function query.  
 */
module Deferred {
  /**
   * An instance of a `Deferred` class. 
   * For example the result from `new Deferred()` or `new $.Deferred()`.
   */
  class DeferredInstance extends DataFlow::NewNode {
  	// Describes both `new Deferred()`, `new $.Deferred` and other variants. 
    DeferredInstance() { this.getCalleeName() = "Deferred" }

    private DataFlow::SourceNode ref(DataFlow::TypeTracker t) {
      t.start() and
      result = this
      or
      exists(DataFlow::TypeTracker t2 | result = ref(t2).track(t2, t))
    }
    
    DataFlow::SourceNode ref() { result = ref(DataFlow::TypeTracker::end()) }
  }

  /**
   * A promise object created by a Deferred constructor
   */
  private class DeferredPromiseDefinition extends PromiseDefinition, DeferredInstance {
    DeferredPromiseDefinition() {
      // hardening of the "Deferred" heuristic: a method call to `resolve`. 
      exists(ref().getAMethodCall("resolve"))
    }

    override DataFlow::FunctionNode getExecutor() { result = getCallback(0) }
  }

  /**
   * A resolved promise created by a `new Deferred().resolve()` call.
   */
  class ResolvedDeferredPromiseDefinition extends ResolvedPromiseDefinition {
    ResolvedDeferredPromiseDefinition() {
      this = any(DeferredPromiseDefinition def).ref().getAMethodCall("resolve")
    }

    override DataFlow::Node getValue() { result = getArgument(0) }
  }
}

from DataFlow::CallNode call, Function func, string name, string msg
where
  (
    callToVoidFunction(call, func) and 
    msg = "the $@ does not return anything, yet the return value is used." and
    name = func.describe()
    or
    voidArrayCallback(call, func) and 
    msg = "the $@ does not return anything, yet the return value from the call to " + call.getCalleeName() + " is used." and
    name = "callback function"
  ) and
  not benignContext(call.asExpr()) and
  not lastStatementHasNoEffect(func) and
  // anonymous one-shot closure. Those are used in weird ways and we ignore them.
  not oneshotClosure(call.asExpr())
select
  call, msg, func, name
