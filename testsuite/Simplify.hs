module Simplify where

import Prelude(Bool(..),error,(&&))
import Contracts

data Formula v
    = And (Formula v) (Formula v)
    | Or  (Formula v) (Formula v)
    | Implies (Formula v) (Formula v)
    | Not (Formula v)
    | Var v

isSimplified :: Formula v -> Bool
isSimplified f = case f of
    And lhs rhs -> isSimplified lhs && isSimplified rhs
    Or lhs rhs  -> isSimplified lhs && isSimplified rhs
    Implies _ _ -> False
    Not f       -> isSimplified f
    Var _       -> True

simplify :: Formula v -> Formula v
simplify f = case f of
    And lhs rhs     -> And (simplify lhs) (simplify rhs)
    Or lhs rhs      -> Or (simplify lhs) (simplify rhs)
    Implies lhs rhs -> Or (Not (simplify lhs)) (simplify rhs)
    Not f           -> Not (simplify f)
    Var _           -> f

simplify_simplifies = simplify ::: CF --> CF :&: Pred isSimplified

isSimplified_cf = isSimplified ::: CF --> CF

simplify_simplifies_stronger = simplify ::: CF --> CF :&: Pred isSimplified
  `Using` isSimplified_cf
