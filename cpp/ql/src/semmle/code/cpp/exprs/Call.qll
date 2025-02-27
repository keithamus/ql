import semmle.code.cpp.exprs.Expr
import semmle.code.cpp.Function
private import semmle.code.cpp.dataflow.EscapesTree

/**
 * A C/C++ call.
 */
abstract class Call extends Expr, NameQualifiableElement {
  /**
   * Gets the number of actual parameters in this call; use
   * `getArgument(i)` with `i` between `0` and `result - 1` to
   * retrieve actuals.
   */
  int getNumberOfArguments() { result = count(this.getAnArgument()) }

  /**
   * Holds if this call has a qualifier.
   *
   * For example, `ptr->f()` has a qualifier, whereas plain `f()` does not.
   */
  predicate hasQualifier() { exists(Expr e | this.getChild(-1) = e) }

  /**
   * Gets the expression to the left of the function name or function pointer variable name.
   *
   * As a few examples:
   *  For the call to `f` in `ptr->f()`, this gives `ptr`.
   *  For the call to `f` in `(*ptr).f()`, this gives `(*ptr)`.
   */
  Expr getQualifier() { result = this.getChild(-1) }

  /**
   * Gets an argument for this call.
   */
  Expr getAnArgument() { exists(int i | result = this.getChild(i) and i >= 0) }

  /**
   * Gets the nth argument for this call.
   *
   * The range of `n` is from `0` to `getNumberOfArguments() - 1`.
   */
  Expr getArgument(int n) { result = this.getChild(n) and n >= 0 }

  /**
   * Gets a sub expression of the argument at position `index`. If the
   * argument itself contains calls, such calls will be considered
   * leafs in the expression tree.
   *
   * Example: the call `f(2, 3 + 4, g(4 + 5))` has sub expression(s)
   * `2` at index 0; `3`, `4`, and `3 + 4` at index 1; and `g(4 + 5)`
   * at index 2, respectively.
   */
  Expr getAnArgumentSubExpr(int index) {
    result = getArgument(index)
    or
    exists(Expr mid |
      mid = getAnArgumentSubExpr(index) and
      not mid instanceof Call and
      not mid instanceof SizeofOperator and
      result = mid.getAChild()
    )
  }

  /**
   * Gets the target of the call, as best as makes sense for this kind of call.
   * The precise meaning depends on the kind of call it is:
   * - For a call to a function, it's the function being called.
   * - For a C++ method call, it's the statically resolved method.
   * - For an Objective C message expression, it's the statically resolved
   *   method, and it might not exist.
   * - For a variable call, it never exists.
   */
  abstract Function getTarget();

  override int getPrecedence() { result = 16 }

  override string toString() { none() }

  /**
   * Holds if this call passes the variable accessed by `va` by
   * reference as the `i`th argument.
   *
   * A variable is passed by reference if the `i`th parameter of the function
   * receives an address that points within the object denoted by `va`. For a
   * variable named `x`, passing by reference includes both explicit pointers
   * (`&x`) and implicit conversion to a C++ reference (`x`), but it also
   * includes deeper expressions such as `&x[0] + length` or `&*&*&x`.
   *
   * When `Field`s are involved, an argument `i` may pass more than one
   * variable by reference simultaneously. For example, the call `f(&x.m1.m2)`
   * counts as passing both `x`, `m1` and `m2` to argument 0 of `f`.
   *
   * This predicate holds for variables passed by reference even if they are
   * passed as references to `const` and thus cannot be changed through that
   * reference. See `passesByNonConstReference` for a predicate that only holds
   * for variables passed by reference to non-const.
   */
  predicate passesByReference(int i, VariableAccess va) {
    variableAddressEscapesTree(va, this.getArgument(i).getFullyConverted())
  }

  /**
   * Holds if this call passes the variable accessed by `va` by
   * reference to non-const data as the `i`th argument.
   *
   * A variable is passed by reference if the `i`th parameter of the function
   * receives an address that points within the object denoted by `va`. For a
   * variable named `x`, passing by reference includes both explicit pointers
   * (`&x`) and implicit conversion to a C++ reference (`x`), but it also
   * includes deeper expressions such as `&x[0] + length` or `&*&*&x`.
   *
   * When `Field`s are involved, an argument `i` may pass more than one
   * variable by reference simultaneously. For example, the call `f(&x.m1.m2)`
   * counts as passing both `x`, `m1` and `m2` to argument 0 of `f`.
   *
   * This predicate only holds for variables passed by reference to non-const
   * data and thus can be changed through that reference. See
   * `passesByReference` for a predicate that also holds for variables passed
   * by reference to const.
   */
  predicate passesByReferenceNonConst(int i, VariableAccess va) {
    variableAddressEscapesTreeNonConst(va, this.getArgument(i).getFullyConverted())
  }
}

/**
 * A C/C++ function call where the name of the target function is known at compile-time.
 *
 * This includes various kinds of call:
 *  1. Calls such as `f(x)` where `f` is the name of a function.
 *  2. Calls such as `ptr->f()` where `f` is the name of a (possibly virtual) member function.
 *  3. Constructor calls for stack-allocated objects.
 *  4. Implicit and explicit calls to user-defined operators.
 *  5. Base class initializers in constructors.
 */
class FunctionCall extends Call, @funbindexpr {
  FunctionCall() { iscall(underlyingElement(this), _) }

  override string getCanonicalQLClass() { result = "FunctionCall" }

  /** Gets an explicit template argument for this call. */
  Locatable getAnExplicitTemplateArgument() { result = getExplicitTemplateArgument(_) }

  /** Gets an explicit template argument value for this call. */
  Locatable getAnExplicitTemplateArgumentKind() { result = getExplicitTemplateArgumentKind(_) }

  /** Gets a template argument for this call. */
  Locatable getATemplateArgument() { result = getTarget().getATemplateArgument() }

  /** Gets a template argument value for this call. */
  Locatable getATemplateArgumentKind() { result = getTarget().getATemplateArgumentKind() }

  /** Gets the nth explicit template argument for this call. */
  Locatable getExplicitTemplateArgument(int n) {
    n < getNumberOfExplicitTemplateArguments() and
    result = getTemplateArgument(n)
  }

  /** Gets the nth explicit template argument value for this call. */
  Locatable getExplicitTemplateArgumentKind(int n) {
    n < getNumberOfExplicitTemplateArguments() and
    result = getTemplateArgumentKind(n)
  }

  /** Gets the number of explicit template arguments for this call. */
  int getNumberOfExplicitTemplateArguments() {
    if numtemplatearguments(underlyingElement(this), _)
    then numtemplatearguments(underlyingElement(this), result)
    else result = 0
  }

  /** Gets the number of template arguments for this call. */
  int getNumberOfTemplateArguments() { result = count(int i | exists(getTemplateArgument(i))) }

  /** Gets the nth template argument for this call (indexed from 0). */
  Locatable getTemplateArgument(int n) { result = getTarget().getTemplateArgument(n) }

  /** Gets the nth template argument value for this call (indexed from 0). */
  Locatable getTemplateArgumentKind(int n) { result = getTarget().getTemplateArgumentKind(n) }

  /** Holds if any template arguments for this call are implicit / deduced. */
  predicate hasImplicitTemplateArguments() {
    exists(int i |
      exists(getTemplateArgument(i)) and
      not exists(getExplicitTemplateArgument(i))
    )
  }

  /** Holds if a template argument list was provided for this call. */
  predicate hasTemplateArgumentList() { numtemplatearguments(underlyingElement(this), _) }

  /**
   * Gets the `RoutineType` of the call target as visible at the call site.  For
   * constructor calls, this predicate instead gets the `Class` of the constructor
   * being called.
   */
  private Type getTargetType() { result = Call.super.getType().stripType() }

  /**
   * Gets the expected return type of the function called by this call.
   *
   * In most cases, the expected return type will be the return type of the function being called.
   * It is only different when the function being called is ambiguously declared, at which point
   * the expected return type is the return type of the (unambiguous) function declaration that was
   * visible at the call site.
   */
  Type getExpectedReturnType() {
    if getTargetType() instanceof RoutineType
    then result = getTargetType().(RoutineType).getReturnType()
    else result = getTarget().getType()
  }

  /**
   * Gets the expected type of the nth parameter of the function called by this call.
   *
   * In most cases, the expected parameter types match the parameter types of the function being called.
   * They are only different when the function being called is ambiguously declared, at which point
   * the expected parameter types are the parameter types of the (unambiguous) function declaration that
   * was visible at the call site.
   */
  Type getExpectedParameterType(int n) {
    if getTargetType() instanceof RoutineType
    then result = getTargetType().(RoutineType).getParameterType(n)
    else result = getTarget().getParameter(n).getType()
  }

  /**
   * Gets the function called by this call.
   *
   * In the case of virtual function calls, the result is the most-specific function in the override tree (as
   * determined by the compiler) such that the target at runtime will be one of result.getAnOverridingFunction*().
   */
  override Function getTarget() { funbind(underlyingElement(this), unresolveElement(result)) }

  /**
   * Gets the type of this expression, that is, the return type of the function being called.
   */
  override Type getType() { result = getExpectedReturnType() }

  /**
   * Holds if this is a call to a virtual function.
   *
   * Note that this holds even in cases where a sufficiently clever compiler could perform static dispatch.
   */
  predicate isVirtual() { iscall(underlyingElement(this), 1) }

  /**
   * Holds if the target of this function call was found by argument-dependent lookup and wouldn't have been
   * found by any other means.
   */
  predicate isOnlyFoundByADL() { iscall(underlyingElement(this), 2) }

  /** Gets a textual representation of this function call. */
  override string toString() {
    if exists(getTarget())
    then result = "call to " + this.getTarget().getName()
    else result = "call to unknown function"
  }

  override predicate mayBeImpure() {
    this.getChild(_).mayBeImpure() or
    this.getTarget().mayHaveSideEffects() or
    isVirtual() or
    getTarget().getAnAttribute().getName() = "weak"
  }

  override predicate mayBeGloballyImpure() {
    this.getChild(_).mayBeGloballyImpure() or
    this.getTarget().mayHaveSideEffects() or
    isVirtual() or
    getTarget().getAnAttribute().getName() = "weak"
  }
}

/**
 * An instance of unary operator * applied to a user-defined type.
 */
class OverloadedPointerDereferenceExpr extends FunctionCall {
  OverloadedPointerDereferenceExpr() {
    getTarget().hasName("operator*") and
    getTarget().getEffectiveNumberOfParameters() = 1
  }

  /**
   * Gets the expression this operator * applies to.
   */
  Expr getExpr() {
    result = this.getChild(0) or
    result = this.getQualifier()
  }

  override predicate mayBeImpure() {
    FunctionCall.super.mayBeImpure() and
    (
      this.getExpr().mayBeImpure()
      or
      not exists(Class declaring |
        this.getTarget().getDeclaringType().isConstructedFrom*(declaring)
      |
        declaring.getNamespace() instanceof StdNamespace
      )
    )
  }

  override predicate mayBeGloballyImpure() {
    FunctionCall.super.mayBeGloballyImpure() and
    (
      this.getExpr().mayBeGloballyImpure()
      or
      not exists(Class declaring |
        this.getTarget().getDeclaringType().isConstructedFrom*(declaring)
      |
        declaring.getNamespace() instanceof StdNamespace
      )
    )
  }
}

/**
 * An instance of operator [] applied to a user-defined type.
 */
class OverloadedArrayExpr extends FunctionCall {
  OverloadedArrayExpr() { getTarget().hasName("operator[]") }

  /**
   * Gets the expression being subscripted.
   */
  Expr getArrayBase() {
    if exists(this.getQualifier()) then result = this.getQualifier() else result = this.getChild(0)
  }

  /**
   * Gets the expression giving the index.
   */
  Expr getArrayOffset() {
    if exists(this.getQualifier()) then result = this.getChild(0) else result = this.getChild(1)
  }
}

/**
 * A C/C++ call which is performed through a function pointer.
 */
class ExprCall extends Call, @callexpr {
  /**
   * Gets the expression which yields the function pointer to call.
   */
  Expr getExpr() { result = this.getChild(0) }

  override string getCanonicalQLClass() { result = "ExprCall" }

  override Expr getAnArgument() { exists(int i | result = this.getChild(i) and i >= 1) }

  override Expr getArgument(int index) {
    result = this.getChild(index + 1) and index in [0 .. this.getNumChild() - 2]
  }

  override string toString() { result = "call to expression" }

  override Function getTarget() { none() }
}

/**
 * A C/C++ call which is performed through a variable of function pointer type.
 */
class VariableCall extends ExprCall {
  VariableCall() { this.getExpr() instanceof VariableAccess }

  override string getCanonicalQLClass() { result = "VariableCall" }

  /**
   * Gets the variable which yields the function pointer to call.
   */
  Variable getVariable() { this.getExpr().(VariableAccess).getTarget() = result }
}

/**
 * A call to a constructor.
 */
class ConstructorCall extends FunctionCall {
  ConstructorCall() { super.getTarget() instanceof Constructor }

  override string getCanonicalQLClass() { result = "ConstructorCall" }

  /** Gets the constructor being called. */
  override Constructor getTarget() { result = super.getTarget() }
}

/**
 * A C++ `throw` expression.
 */
class ThrowExpr extends Expr, @throw_expr {
  /**
   * Gets the expression that will be thrown, if any. There is no result if
   * `this` is a `ReThrowExpr`.
   */
  Expr getExpr() { result = this.getChild(0) }

  override string getCanonicalQLClass() { result = "ThrowExpr" }

  override string toString() { result = "throw ..." }

  override int getPrecedence() { result = 1 }
}

/**
 * A C++ `throw` expression with no argument (which causes the current exception to be re-thrown).
 */
class ReThrowExpr extends ThrowExpr {
  ReThrowExpr() { this.getType() instanceof VoidType }

  override string getCanonicalQLClass() { result = "ReThrowExpr" }

  override string toString() { result = "re-throw exception " }
}

/**
 * A call to a destructor.
 */
class DestructorCall extends FunctionCall {
  DestructorCall() { super.getTarget() instanceof Destructor }

  override string getCanonicalQLClass() { result = "DestructorCall" }

  /** Gets the destructor being called. */
  override Destructor getTarget() { result = super.getTarget() }
}

/**
 * An expression that looks like a destructor call, but has no effect.
 *
 * For example, given a plain old data type `pod_t`, the syntax `ptr->~pod_t()` is
 * a vacuous destructor call, as `~pod_t` isn't actually a function. This can also
 * occur in instantiated templates, as `ptr->~T()` becomes vacuous when `T` is `int`.
 */
class VacuousDestructorCall extends Expr, @vacuous_destructor_call {
  /**
   * Gets the expression for the object whose destructor would be called.
   */
  Expr getQualifier() { result = this.getChild(0) }

  override string getCanonicalQLClass() { result = "VacuousDestructorCall" }

  override string toString() { result = "(vacuous destructor call)" }
}

/**
 * An initialization of a base class or member variable performed as part
 * of a constructor's explicit initializer list or implicit actions.
 */
class ConstructorInit extends Expr, @ctorinit {
  override string getCanonicalQLClass() { result = "ConstructorInit" }
}

/**
 * A call to a constructor of a base class as part of a constructor's
 * initializer list or compiler-generated actions.
 */
class ConstructorBaseInit extends ConstructorInit, ConstructorCall {
  override string getCanonicalQLClass() { result = "ConstructorBaseInit" }
}

/**
 * A call to a constructor of a direct non-virtual base class as part of a
 * constructor's initializer list or compiler-generated actions.
 */
class ConstructorDirectInit extends ConstructorBaseInit, @ctordirectinit {
  override string getCanonicalQLClass() { result = "ConstructorDirectInit" }
}

/**
 * A call to a constructor of a virtual base class as part of a
 * constructor's initializer list or compiler-generated actions.
 *
 * If the virtual base class has already been initialized, then this
 * call won't be performed.
 */
class ConstructorVirtualInit extends ConstructorBaseInit, @ctorvirtualinit {
  override string getCanonicalQLClass() { result = "ConstructorVirtualInit" }
}

/**
 * A call to a constructor of the same class as part of a constructor's
 * initializer list, which delegates object construction (C++11 only).
 */
class ConstructorDelegationInit extends ConstructorBaseInit, @ctordelegatinginit {
  override string getCanonicalQLClass() { result = "ConstructorDelegationInit" }
}

/**
 * An initialization of a member variable performed as part of a
 * constructor's explicit initializer list or implicit actions.
 */
class ConstructorFieldInit extends ConstructorInit, @ctorfieldinit {
  /** Gets the field being initialized. */
  Field getTarget() { varbind(underlyingElement(this), unresolveElement(result)) }

  override string getCanonicalQLClass() { result = "ConstructorFieldInit" }

  /**
   * Gets the expression to which the field is initialized.
   *
   * This is typically either a Literal or a FunctionCall to a
   * constructor, but more complex expressions can also occur.
   */
  Expr getExpr() { result = this.getChild(0) }

  override string toString() { result = "constructor init of field " + getTarget().getName() }

  override predicate mayBeImpure() { this.getExpr().mayBeImpure() }

  override predicate mayBeGloballyImpure() { this.getExpr().mayBeGloballyImpure() }
}

/**
 * A call to a destructor of a base class or field as part of a destructor's
 * compiler-generated actions.
 */
class DestructorDestruction extends Expr, @dtordestruct {
  override string getCanonicalQLClass() { result = "DestructorDestruction" }
}

/**
 * A call to a destructor of a base class as part of a destructor's
 * compiler-generated actions.
 */
class DestructorBaseDestruction extends DestructorCall, DestructorDestruction {
  override string getCanonicalQLClass() { result = "DestructorBaseDestruction" }
}

/**
 * A call to a destructor of a direct non-virtual base class as part of a
 * destructor's compiler-generated actions.
 */
class DestructorDirectDestruction extends DestructorBaseDestruction, @dtordirectdestruct {
  override string getCanonicalQLClass() { result = "DestructorDirectDestruction" }
}

/**
 * A call to a destructor of a direct virtual base class as part of a
 * destructor's compiler-generated actions.
 *
 * If the virtual base class wasn't initialized by the ConstructorVirtualInit
 * in the corresponding constructor, then this call won't be performed.
 */
class DestructorVirtualDestruction extends DestructorBaseDestruction, @dtorvirtualdestruct {
  override string getCanonicalQLClass() { result = "DestructorVirtualDestruction" }
}

/**
 * A destruction of a member variable performed as part of a
 * destructor's compiler-generated actions.
 */
class DestructorFieldDestruction extends DestructorDestruction, @dtorfielddestruct {
  /** Gets the field being destructed. */
  Field getTarget() { varbind(underlyingElement(this), unresolveElement(result)) }

  override string getCanonicalQLClass() { result = "DestructorFieldDestruction" }

  /** Gets the compiler-generated call to the variable's destructor. */
  DestructorCall getExpr() { result = this.getChild(0) }

  override string toString() {
    result = "destructor field destruction of " + this.getTarget().getName()
  }
}
