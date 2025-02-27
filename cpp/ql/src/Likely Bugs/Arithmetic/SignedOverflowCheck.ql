/**
 * @name Undefined result of signed test for overflow
 * @description Testing for overflow by adding a value to a variable
 *              to see if it "wraps around" works only for
 *              unsigned integer values.
 * @kind problem
 * @problem.severity warning
 * @precision high
 * @id cpp/signed-overflow-check
 * @tags reliability
 *       security
 */

import cpp
private import semmle.code.cpp.valuenumbering.GlobalValueNumbering
private import semmle.code.cpp.rangeanalysis.SimpleRangeAnalysis

from RelationalOperation ro, AddExpr add, Expr expr1, Expr expr2
where
  ro.getAnOperand() = add and
  add.getAnOperand() = expr1 and
  ro.getAnOperand() = expr2 and
  globalValueNumber(expr1) = globalValueNumber(expr2) and
  add.getUnspecifiedType().(IntegralType).isSigned() and
  not exists(MacroInvocation mi | mi.getAnAffectedElement() = add) and
  exprMightOverflowPositively(add) and
  exists(Compilation c | c.getAFileCompiled() = ro.getFile() |
    not c.getAnArgument() = "-fwrapv" and
    not c.getAnArgument() = "-fno-strict-overflow"
  )
select ro, "Testing for signed overflow may produce undefined results."
