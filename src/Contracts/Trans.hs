{-# LANGUAGE RecordWildCards #-}
{-

    Translates contracts in the datatypes in Contracts.Types to FOL

-}
module Contracts.Trans where

import CoreSyn
import Var

import Contracts.Types
import Contracts.FixpointInduction
import Contracts.Params
import Contracts.Theory

import Halo.Binds
import Halo.ExprTrans
import Halo.FOL.Abstract
import Halo.FOL.Operations
import Halo.Monad
import Halo.PrimCon
import Halo.Shared
import Halo.Subtheory
import Halo.Util

import Control.Monad.Reader

import qualified Data.Map as M
import Data.List
import Data.Maybe

data Variance = Pos | Neg deriving (Eq,Show)

opposite :: Variance -> Variance
opposite Pos = Neg
opposite Neg = Pos

-- | We want to access the params and the fix info while doing this
type TransM = ReaderT TrEnv HaloM

data TrEnv = TrEnv
    { env_params   :: Params
    , env_fix_info :: FixInfo
    , env_bind_map :: HCCBinds
    }

getParams :: TransM Params
getParams = asks env_params

getFixInfo :: TransM FixInfo
getFixInfo = asks env_fix_info

getBindParts :: Var -> TransM [HCCBindPart]
getBindParts x = asks (fromMaybe err . M.lookup x . env_bind_map)
  where
    err = error $ "Contracts.Trans.getBindParts: no bind parts for " ++ show x

data Skolem = Skolemise | Quantify
  deriving (Eq,Ord,Show)

trTopStmt :: TopStmt -> TransM [Conjecture]
trTopStmt (TopStmt _name stmt deps) = trStatement deps (stripTreeUsings stmt)

trStatement :: [HCCContent] -> Statement -> TransM [Conjecture]
trStatement deps stmt@Statement{..} = do

    Params{..} <- getParams

    fpi_content <- trFPI deps stmt
    plain_content <- trPlain deps stmt

    let conjectures
            | fpi_no_plain && not (null fpi_content) = fpi_content
            | otherwise = plain_content : fpi_content

    (using_clauses,using_deps) <-
        local' (addSkolems statement_args) $ mapAndUnzipM trUsing statement_using

    let extender = extendConj (concat using_clauses) (concat using_deps)

    return $ map extender conjectures

trPlain :: [HCCContent] -> Statement -> TransM Conjecture
trPlain deps (Statement e c as _) = do

    (clauses,ptrs) <- capturePtrs' (local' (addSkolems as) (trGoal e c))

    return $ Conjecture
        { conj_clauses      = comment "Plain contract":clauses
        , conj_dependencies = deps ++ pointers ptrs
        , conj_kind         = Plain
        }

trUsing :: Statement -> TransM ([Clause'],[HCCContent])
trUsing stmt@(Statement e c as _) = post <$> capturePtrs' (trAssum e c)
  where
    post = ((comment ("Using\n" ++ show stmt) :)
         . map (clauseMapFormula (forall' as)))
         *** pointers

-- | The top variable, suitable for fixed point induction
topVar :: CoreExpr -> Maybe Var
topVar (Var v)    = Just v
topVar (App e _)  = topVar e
topVar (Lam _ e)  = topVar e
topVar (Cast e _) = topVar e
topVar (Tick _ e) = topVar e
topVar _          = Nothing

-- | Try to translate this statement using FPI
trFPI :: [HCCContent] -> Statement -> TransM [Conjecture]
trFPI deps st@(Statement e _ _ _) = do
    fix_info <- getFixInfo
    case topVar e of
        Just f | fpiApplicable fix_info f -> trFixated deps st f
        _ -> return []

-- | Translate this statement with this fixpoint function
trFixated :: [HCCContent] -> Statement -> Var -> TransM [Conjecture]
trFixated deps (Statement e c as _) f = local' (addSkolems as) $ do
    Params{..} <- getParams
    fix_info <- getFixInfo

    let -- Get the focused names
        [f_base,f_concl] = map (fpiFocusName fix_info f) [ConstantUNR,Concl]

        -- Change dependencies from f to f_base or f_concl
        rename_f Base v | v == f = f_base
        rename_f Step v | v == f = f_concl
        rename_f _    v = v

        -- We use the original dependencies, but rename f to
        -- f_base or f_concl in dependencies
        [orig_deps_base,orig_deps_step]
            = [ map (mapFunctionContent
                     ( fpiFriendName fix_info f friend_case
                     . rename_f friend_case
                     )) deps
              | friend_case <- [Base,Step]
              ]

        -- How to rename an entire contract
        rename_c = substContractList c . fpiGetSubstList fix_info f


    -- Translate the contract for the base, hyp and conclusion focus,
    -- registering pointers and calculating the final dependencies
    [(tr_base,deps_base),(tr_hyp,deps_hyp),(tr_concl,deps_concl)] <-
        sequence
            [ do let f_version = fpiFocusName fix_info f focused
                     e' = subst e f f_version
                     f' = rename_c focused

                 (tr,ptrs) <- capturePtrs' $ tr_contr_fun e' f'

                 return (comment desc : tr,pointers ptrs ++ orig_deps)

            | (desc,tr_contr_fun,focused,orig_deps)

                <- [("Base case",           trGoal ,ConstantUNR,orig_deps_base)
                   ,("Induction hypothesis",trAssum,Hyp,        []            )
                   ,("Induction conclusion",trGoal ,Concl,      orig_deps_step)
                   ]
            ]

    let tr_step   = tr_hyp ++ tr_concl
        deps_step = deps_hyp `union` deps_concl

    -- Also split the goal if possible
    splits <- trSplit (subst e f f_concl) (rename_c Concl)

    return $
        [ Conjecture tr_base  deps_base  FixpointBase | not fpi_no_base ] ++
        [ Conjecture tr_step  deps_step  FixpointStep ] ++
        [ Conjecture tr_split deps_split (FixpointStepSplit split_num)
        | Split{..} <- splits
        , let -- Add the induction hypothesis
              tr_split = tr_hyp ++ split_clauses
              -- We take the dependencies in the contrcat using f_concl
              deps_split = split_deps `union` delete (Function f_concl) deps_concl
        ]

data Split = Split
    { split_clauses :: [Clause']
    , split_deps    :: [HCCContent]
    , split_num     :: Int
    }

-- Chop this contract up in several parts, enables us to "cursor" through the
-- definition of the function instead of trying it in one go
trSplit :: CoreExpr -> Contract -> TransM [Split]
trSplit expr contract = do
    let f = fromMaybe (error "trSplit: topVar returned Nothing") (topVar expr)

    bind_parts <- getBindParts f

    -- We throw away the parts with min rhs, and look at the min-sets
    -- stored in bind_mins instead
    let decl_parts = filter (not . minRhs . bind_rhs) bind_parts

    -- We will equate the result of the function to the arguments to
    -- the contract
    let contract_args :: [Var]
        contract_args = (map fst . fst . telescope) contract

    -- The contract only needs to be translated once
    (tr_contr,contr_deps) <- (axioms . splitFormula *** pointers)
        <$> capturePtrs' (trContract Neg Skolemise expr contract)

    -- The rest of the work is carried out by the bindToSplit function,
    -- by iterating over the (non-min) BindParts.
    zipWithM (bindToSplit f contract_args tr_contr contr_deps) decl_parts [0..]

bindToSplit :: Var -> [Var] -> [Clause'] -> [HCCContent]
            -> HCCBindPart -> Int -> TransM Split
bindToSplit f contract_args tr_contr contr_deps decl_part@BindPart{..} num = do

    (tr_part,part_ptrs) <- lift $ capturePtrs $ do

        -- Translate just this bind part
        tr_decl <- definitions . splitFormula <$> trBindPart decl_part

        -- Foreach argument e, match up the variable v
        -- introduce e's arguments as skolems and make them equal
        let sks :: [Var]
            sks = concatMap exprFVs bind_args

        -- Everything under here considers the otherwise quantified
        -- vars in the arguments as skolem variables, now quantified
        -- over the whole theory instead
        tr_goal <- local (addSkolems (nub $ sks ++ contract_args)) $ do

            -- Make the arguments to the function equal to the
            -- contract variables from the telescope
            tr_eqs <- axioms .:
                zipWith (===) <$> mapM (trExpr . Var) contract_args
                              <*> mapM trExpr bind_args

            -- Translate the constraints, but instead of having them
            -- as an antecedents, they are now asserted
            tr_constrs <- axioms <$> trConstraints bind_constrs

            -- Translate the relevant mins
            tr_min <- axioms <$> mapM (liftM (foralls . min') . trExpr) bind_mins

            return $ [comment "Imposed min"] ++ tr_min
                  ++ [comment "Equalities from arguments"] ++ tr_eqs
                  ++ [comment "Imposed constraints"] ++ tr_constrs

        return ([comment $ "Bind part for " ++ show f] ++ tr_decl ++ tr_goal)

    -- Use the dependencies defined in the BindPart, but don't add the
    -- dependency to f, or else the full original definition is added
    -- to the theory as well.
    let dep = delete (Function f) $ contr_deps ++ bind_deps ++ pointers part_ptrs

    return $ Split
        { split_clauses = tr_part ++ [comment "Contract"] ++ tr_contr
        , split_deps    = dep
        , split_num     = num
        }

trGoal :: CoreExpr -> Contract -> TransM [Clause']
trGoal e f = clauseSplit axiom <$> trContract Neg Skolemise e f

trAssum :: CoreExpr -> Contract -> TransM [Clause']
trAssum e f = clauseSplit hypothesis <$> trContract Pos Quantify e f

trContract :: Variance -> Skolem -> CoreExpr -> Contract -> TransM Formula'
trContract variance skolemise e_init contract = do

    -- We obtain all arguments (to the right of the last arrow), and
    -- bind them under the same quantifier. This makes somewhat
    -- simpler theories.
    let (arguments,result) = telescope contract
        vars     = map fst arguments
        e_result = foldl (@@) e_init (map Var vars)

    lift $ write $ "trContract (" ++ show skolemise ++ ")" ++ " " ++ show variance
                ++ "\n    e_init    :" ++ showExpr e_init
                ++ "\n    e_result  :" ++ showExpr e_result
                ++ "\n    contract  :" ++ show contract
                ++ "\n    result    :" ++ show result
                ++ "\n    arguments :" ++ show arguments
                ++ "\n    vars      :" ++ show vars

    tr_contract <- local' (skolemise == Skolemise ? addSkolems vars) $ do

        lift $ write $ "Translating arguments of " ++ showExpr e_result

        let tr_argument :: (Var,Contract) -> TransM Formula'
            tr_argument = uncurry (trContract (opposite variance) Quantify . Var)

        tr_arguments <- mapM tr_argument arguments

        lift $ write $ "Translating result of " ++ showExpr e_result

        tr_result <- case result of

            Pred p -> do
                ex <- lift $ trExpr e_result
                px <- lift $ trExpr p
                return $ case variance of
                    Neg -> min' ex /\ min' px /\ ex =/= unr /\ (px === false \/ px === bad)
                    Pos -> min' ex ==> (min' px /\ (ex === unr \/ px === unr \/ px === true))

            CF -> do
                e_tr <- lift $ trExpr e_result
                return $ case variance of
                    Neg -> min' e_tr /\ neg (cf e_tr)
                    Pos -> min' e_tr ==> cf e_tr

            And c1 c2 -> case variance of { Neg -> ors ; Pos -> ands }
                <$> mapM (trContract variance skolemise e_result) [c1,c2]

            Arrow{} -> error "trContract : telescope didn't catch arrow (impossible)"

        return $ tr_arguments ++ [tr_result]

    return $ case variance of
        Neg -> (skolemise == Quantify ? exists' vars) (ands tr_contract)
        Pos -> forall' vars (ors tr_contract)

local' :: (HaloEnv -> HaloEnv) -> TransM a -> TransM a
local' k m = do
    e <- ask
    lift $ (local k) (runReaderT m e)

capturePtrs' :: TransM a -> TransM (a,[Var])
capturePtrs' m = do
    e <- ask
    lift $ capturePtrs (runReaderT m e)
