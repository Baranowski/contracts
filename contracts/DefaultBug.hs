module DefaultBug where

import Contracts
import Prelude(Bool(..))

data Ok = Ok

mini :: Bool -> Bool -> Ok
mini True  y    = Ok
mini x     True = Ok
mini False y    = Ok

-- Bug
mini_cf = mini ::: CF --> CF --> CF
