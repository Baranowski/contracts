{-# LANGUAGE DeriveDataTypeable #-}
module Contracts.Params where

import System.Console.CmdArgs

data Params = Params
    { files                :: [FilePath]

    , no_min               :: Bool
    , min_as_not_unr       :: Bool

    , cnf                  :: Bool
    , core_optimise        :: Bool
    , no_comments          :: Bool
    , squishy_booleans     :: Bool
    , or_discr             :: Bool

    , db_float_out         :: Bool
    , db_lift              :: Bool
    , db_halo              :: Bool
    , db_collect_contracts :: Bool
    , db_trans_contracts   :: Bool

    , dump_init_core       :: Bool
    , dump_float_out       :: Bool
    , dump_core            :: Bool
    , dump_fpi_core        :: Bool
    , dump_tptp            :: Bool
    , dump_contracts       :: Bool
    }
  deriving (Show,Data,Typeable)

defParams :: Params
defParams = Params
    { files                 = []    &= args   &= typFile

    , no_min                = False &= groupname "\nSettings for generated theories"
                                    &= name "m" &= help "Remove all occurences of min in generated theories (default off)"
    , min_as_not_unr        = False &= name "u" &= help "Replace all occurences of min in generated theories with not.unr (default off)"

    , cnf                   = False &= help "Generate theories in CNF rather than fof when possible"
    , core_optimise         = False &= help "Run the core2core optimising pass"
    , no_comments           = False &= help "Don't print comments in TPTP file (current default is on for debugging purposes)"
    , squishy_booleans      = False &= help "Don't force true /= false, put min antecedent there"

    , or_discr              = False &= help "Use Or instead of And in the assumptions of discrimination axioms"

    , db_float_out          = False &= groupname "\nDebugging output"
                                    &= help "Debug floating out (sets Opt_D_dump_simpl_stats and Opt_D_verbose_core2core)"

    , db_lift               = False &= help "Debug the let-/case-lifter"
    , db_halo               = False &= help "Debug the Haskell to Logic translator"
    , db_collect_contracts  = False &= help "Debug collecting contracts (Core -> internal repr)"
    , db_trans_contracts    = False &= help "Debug translating contracts (internal repr -> FOL)"

    , dump_init_core        = False &= help "Dump initial core we get from GHC"
    , dump_float_out        = False &= help "Dump core after lambda-lifting"
    , dump_core             = False &= help "Dump final core after let-/case-lifting"
    , dump_fpi_core         = False &= help "Dump core after fixpoint generation"
    , dump_tptp             = False &= help "Dump all generated tptp"
    , dump_contracts        = False &= help "Dump the internal representation of contracts"

    }
    &= summary "Haskell Contracts Checker v0.1 Dan Rosén danr@student.gu.se"
    &= program "hcc"
