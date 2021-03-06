{-# OPTIONS_GHC -XNoBangPatterns #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.Map
-- Copyright   :  (c) Daan Leijen 2002
--                (c) Andriy Palamarchuk 2008
-- License     :  BSD-style
-- Maintainer  :  libraries@haskell.org
-- Stability   :  provisional
-- Portability :  portable
--
-- An efficient implementation of maps from keys to values (dictionaries).
--
-- Since many function names (but not the type name) clash with
-- "Prelude" names, this module is usually imported @qualified@, e.g.
--
-- >  import Data.Map (Map)
-- >  import qualified Data.Map as Map
--
-- The implementation of 'Map' is based on /size balanced/ binary trees (or
-- trees of /bounded balance/) as described by:
--
--    * Stephen Adams, \"/Efficient sets: a balancing act/\",
--	Journal of Functional Programming 3(4):553-562, October 1993,
--	<http://www.swiss.ai.mit.edu/~adams/BB/>.
--
--    * J. Nievergelt and E.M. Reingold,
--	\"/Binary search trees of bounded balance/\",
--	SIAM journal of computing 2(1), March 1973.
--
-- Note that the implementation is /left-biased/ -- the elements of a
-- first argument are always preferred to the second, for example in
-- 'union' or 'insert'.
--
-- Operation comments contain the operation time complexity in
-- the Big-O notation <http://en.wikipedia.org/wiki/Big_O_notation>.
-----------------------------------------------------------------------------

module Map where

import Contracts
import Prelude (Bool(..),(&&),(||),Maybe(..),Either(..),fst,snd,Ordering(..))
import GHC.Base hiding (Ord(..),(==),(/=))


infixl 7  *
infixl 6  +, -

infix 4 ==, /=, <, <=, >=, >

(+)  = plusInt
(*)  = timesInt
(-)  = minusInt
(==) = eqInt
(/=) = neInt
(<)  = ltInt
(<=) = leInt
(>=) = geInt
(>)  = gtInt
div  = divInt
compare x y = if x == y then EQ
              -- NB: must be '<=' not '<' to validate the
              -- above claim about the minimal things that
              -- can be defined for an instance of Ord:
              else if x <= y then LT
              else GT

{--------------------------------------------------------------------
  Operators
--------------------------------------------------------------------}
infixl 9 !,\\ --

-- | /O(log n)/. Find the value at a key.
-- Calls 'error' when the element can not be found.
--
-- > fromList [(5,'a'), (3,'b')] ! 1    Error: element not in the map
-- > fromList [(5,'a'), (3,'b')] ! 5 == 'a'

(!) :: Map a -> Int -> a
m ! k    = find k m

-- | Same as 'difference'.
(\\) :: Map a -> Map b -> Map a
m1 \\ m2 = difference m1 m2

{--------------------------------------------------------------------
  Size balanced trees.
--------------------------------------------------------------------}
-- | A Map from keys @k@ to values @a@.
data Map a  = Tip
            | Bin {-# UNPACK #-} !Size !Int a !(Map a) !(Map a)

type Size     = Int

{--------------------------------------------------------------------
  Query
--------------------------------------------------------------------}
-- | /O(1)/. Is the map empty?
--
-- > Data.Map.null (empty)           == True
-- > Data.Map.null (singleton 1 'a') == False

null :: Map a -> Bool
null t
  = case t of
      Tip    -> True
      Bin {} -> False

-- | /O(1)/. The number of elements in the map.
--
-- > size empty                                   == 0
-- > size (singleton 1 'a')                       == 1
-- > size (fromList([(1,'a'), (2,'c'), (3,'b')])) == 3

size :: Map a -> Int
size t
  = case t of
      Tip             -> 0
      Bin sz _ _ _ _  -> sz


-- | /O(log n)/. Lookup the value at a key in the map.
--
-- The function will return the corresponding value as @('Just' value)@,
-- or 'Nothing' if the key isn't in the map.
--
-- An example of using @lookup@:
--
-- > import Prelude hiding (lookup)
-- > import Data.Map
-- >
-- > employeeDept = fromList([("John","Sales"), ("Bob","IT")])
-- > deptCountry = fromList([("IT","USA"), ("Sales","France")])
-- > countryCurrency = fromList([("USA", "Dollar"), ("France", "Euro")])
-- >
-- > employeeCurrency :: String -> Maybe String
-- > employeeCurrency name = do
-- >     dept <- lookup name employeeDept
-- >     country <- lookup dept deptCountry
-- >     lookup country countryCurrency
-- >
-- > main = do
-- >     putStrLn $ "John's currency: " ++ (show (employeeCurrency "John"))
-- >     putStrLn $ "Pete's currency: " ++ (show (employeeCurrency "Pete"))
--
-- The output of this program:
--
-- >   John's currency: Just "Euro"
-- >   Pete's currency: Nothing

lookup :: Int -> Map a -> Maybe a
lookup k t
  = case t of
      Tip -> Nothing
      Bin _ kx x l r
          -> case compare k kx of
               LT -> lookup k l
               GT -> lookup k r
               EQ -> Just x

lookup_cf = lookup ::: CF --> CF --> CF

lookupAssoc :: Int -> Map a -> Maybe (Int,a)
lookupAssoc  k t
  = case t of
      Tip -> Nothing
      Bin _ kx x l r
          -> case compare k kx of
               LT -> lookupAssoc k l
               GT -> lookupAssoc k r
               EQ -> Just (kx,x)

-- | /O(log n)/. Is the key a member of the map? See also 'notMember'.
--
-- > member 5 (fromList [(5,'a'), (3,'b')]) == True
-- > member 1 (fromList [(5,'a'), (3,'b')]) == False

member :: Int -> Map a -> Bool
member k m
  = case lookup k m of
      Nothing -> False
      Just _  -> True

-- | /O(log n)/. Is the key not a member of the map? See also 'member'.
--
-- > notMember 5 (fromList [(5,'a'), (3,'b')]) == False
-- > notMember 1 (fromList [(5,'a'), (3,'b')]) == True

notMember :: Int -> Map a -> Bool
notMember k m = not $ member k m

-- | /O(log n)/. Find the value at a key.
-- Calls 'error' when the element can not be found.
find :: Int -> Map a -> a
find k m
  = case lookup k m of
      Nothing -> error "Map.find: element not in the map"
      Just x  -> x

-- | /O(log n)/. The expression @('findWithDefault' def k map)@ returns
-- the value at key @k@ or returns default value @def@
-- when the key is not in the map.
--
-- > findWithDefault 'x' 1 (fromList [(5,'a'), (3,'b')]) == 'x'
-- > findWithDefault 'x' 5 (fromList [(5,'a'), (3,'b')]) == 'a'

findWithDefault :: a -> Int -> Map a -> a
findWithDefault def k m
  = case lookup k m of
      Nothing -> def
      Just x  -> x



{--------------------------------------------------------------------
  Construction
--------------------------------------------------------------------}
-- | /O(1)/. The empty map.
--
-- > empty      == fromList []
-- > size empty == 0

empty :: Map a
empty
  = Tip

-- | /O(1)/. A map with a single element.
--
-- > singleton 1 'a'        == fromList [(1, 'a')]
-- > size (singleton 1 'a') == 1

singleton :: Int -> a -> Map a
singleton k x
  = Bin 1 k x Tip Tip

{--------------------------------------------------------------------
  Insertion
--------------------------------------------------------------------}
-- | /O(log n)/. Insert a new key and value in the map.
-- If the key is already present in the map, the associated value is
-- replaced with the supplied value. 'insert' is equivalent to
-- @'insertWith' 'const'@.
--
-- > insert 5 'x' (fromList [(5,'a'), (3,'b')]) == fromList [(3, 'b'), (5, 'x')]
-- > insert 7 'x' (fromList [(5,'a'), (3,'b')]) == fromList [(3, 'b'), (5, 'a'), (7, 'x')]
-- > insert 5 'x' empty                         == singleton 5 'x'

insert :: Int -> a -> Map a -> Map a
insert kx x t
  = case t of
      Tip -> singleton kx x
      Bin sz ky y l r
          -> case compare kx ky of
               LT -> balance ky y (insert kx x l) r
               GT -> balance ky y l (insert kx x r)
               EQ -> Bin sz kx x l r

-- | /O(log n)/. Insert with a function, combining new value and old value.
-- @'insertWith' f key value mp@
-- will insert the pair (key, value) into @mp@ if key does
-- not exist in the map. If the key does exist, the function will
-- insert the pair @(key, f new_value old_value)@.
--
-- > insertWith (++) 5 "xxx" (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "xxxa")]
-- > insertWith (++) 7 "xxx" (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a"), (7, "xxx")]
-- > insertWith (++) 5 "xxx" empty                         == singleton 5 "xxx"

insertWith :: (a -> a -> a) -> Int -> a -> Map a -> Map a
insertWith f k x m
  = insertWithKey (\_ x' y' -> f x' y') k x m

-- | Same as 'insertWith', but the combining function is applied strictly.
insertWith' :: (a -> a -> a) -> Int -> a -> Map a -> Map a
insertWith' f k x m
  = insertWithKey' (\_ x' y' -> f x' y') k x m


-- | /O(log n)/. Insert with a function, combining key, new value and old value.
-- @'insertWithKey' f key value mp@
-- will insert the pair (key, value) into @mp@ if key does
-- not exist in the map. If the key does exist, the function will
-- insert the pair @(key,f key new_value old_value)@.
-- Note that the key passed to f is the same key passed to 'insertWithKey'.
--
-- > let f key new_value old_value = (show key) ++ ":" ++ new_value ++ "|" ++ old_value
-- > insertWithKey f 5 "xxx" (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "5:xxx|a")]
-- > insertWithKey f 7 "xxx" (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a"), (7, "xxx")]
-- > insertWithKey f 5 "xxx" empty                         == singleton 5 "xxx"

insertWithKey :: (Int -> a -> a -> a) -> Int -> a -> Map a -> Map a
insertWithKey f kx x t
  = case t of
      Tip -> singleton kx x
      Bin sy ky y l r
          -> case compare kx ky of
               LT -> balance ky y (insertWithKey f kx x l) r
               GT -> balance ky y l (insertWithKey f kx x r)
               EQ -> Bin sy kx (f kx x y) l r

-- | Same as 'insertWithKey', but the combining function is applied strictly.
insertWithKey' :: (Int -> a -> a -> a) -> Int -> a -> Map a -> Map a
insertWithKey' f kx x t
  = case t of
      Tip -> singleton kx x
      Bin sy ky y l r
          -> case compare kx ky of
               LT -> balance ky y (insertWithKey' f kx x l) r
               GT -> balance ky y l (insertWithKey' f kx x r)
               EQ -> let x' = f kx x y in seq x' (Bin sy kx x' l r)


-- | /O(log n)/. Combines insert operation with old value retrieval.
-- The expression (@'insertLookupWithKey' f k x map@)
-- is a pair where the first element is equal to (@'lookup' k map@)
-- and the second element equal to (@'insertWithKey' f k x map@).
--
-- > let f key new_value old_value = (show key) ++ ":" ++ new_value ++ "|" ++ old_value
-- > insertLookupWithKey f 5 "xxx" (fromList [(5,"a"), (3,"b")]) == (Just "a", fromList [(3, "b"), (5, "5:xxx|a")])
-- > insertLookupWithKey f 7 "xxx" (fromList [(5,"a"), (3,"b")]) == (Nothing,  fromList [(3, "b"), (5, "a"), (7, "xxx")])
-- > insertLookupWithKey f 5 "xxx" empty                         == (Nothing,  singleton 5 "xxx")
--
-- This is how to define @insertLookup@ using @insertLookupWithKey@:
--
-- > let insertLookup kx x t = insertLookupWithKey (\_ a _ -> a) kx x t
-- > insertLookup 5 "x" (fromList [(5,"a"), (3,"b")]) == (Just "a", fromList [(3, "b"), (5, "x")])
-- > insertLookup 7 "x" (fromList [(5,"a"), (3,"b")]) == (Nothing,  fromList [(3, "b"), (5, "a"), (7, "x")])

insertLookupWithKey :: (Int -> a -> a -> a) -> Int -> a -> Map a -> (Maybe a,Map a)
insertLookupWithKey f kx x t
  = case t of
      Tip -> (Nothing, singleton kx x)
      Bin sy ky y l r
          -> case compare kx ky of
               LT -> let (found,l') = insertLookupWithKey f kx x l in (found,balance ky y l' r)
               GT -> let (found,r') = insertLookupWithKey f kx x r in (found,balance ky y l r')
               EQ -> (Just y, Bin sy kx (f kx x y) l r)

{--------------------------------------------------------------------
  Deletion
  [delete] is the inlined version of [deleteWith (\k x -> Nothing)]
--------------------------------------------------------------------}
-- | /O(log n)/. Delete a key and its value from the map. When the key is not
-- a member of the map, the original map is returned.
--
-- > delete 5 (fromList [(5,"a"), (3,"b")]) == singleton 3 "b"
-- > delete 7 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a")]
-- > delete 5 empty                         == empty

delete :: Int -> Map a -> Map a
delete k t
  = case t of
      Tip -> Tip
      Bin _ kx x l r
          -> case compare k kx of
               LT -> balance kx x (delete k l) r
               GT -> balance kx x l (delete k r)
               EQ -> glue l r

-- | /O(log n)/. Update a value at a specific key with the result of the provided function.
-- When the key is not
-- a member of the map, the original map is returned.
--
-- > adjust ("new " ++) 5 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "new a")]
-- > adjust ("new " ++) 7 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a")]
-- > adjust ("new " ++) 7 empty                         == empty

adjust :: (a -> a) -> Int -> Map a -> Map a
adjust f k m
  = adjustWithKey (\_ x -> f x) k m

-- | /O(log n)/. Adjust a value at a specific key. When the key is not
-- a member of the map, the original map is returned.
--
-- > let f key x = (show key) ++ ":new " ++ x
-- > adjustWithKey f 5 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "5:new a")]
-- > adjustWithKey f 7 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a")]
-- > adjustWithKey f 7 empty                         == empty

adjustWithKey :: (Int -> a -> a) -> Int -> Map a -> Map a
adjustWithKey f k m
  = updateWithKey (\k' x' -> Just (f k' x')) k m

-- | /O(log n)/. The expression (@'update' f k map@) updates the value @x@
-- at @k@ (if it is in the map). If (@f x@) is 'Nothing', the element is
-- deleted. If it is (@'Just' y@), the key @k@ is bound to the new value @y@.
--
-- > let f x = if x == "a" then Just "new a" else Nothing
-- > update f 5 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "new a")]
-- > update f 7 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a")]
-- > update f 3 (fromList [(5,"a"), (3,"b")]) == singleton 5 "a"

update :: (a -> Maybe a) -> Int -> Map a -> Map a
update f k m
  = updateWithKey (\_ x -> f x) k m

-- | /O(log n)/. The expression (@'updateWithKey' f k map@) updates the
-- value @x@ at @k@ (if it is in the map). If (@f k x@) is 'Nothing',
-- the element is deleted. If it is (@'Just' y@), the key @k@ is bound
-- to the new value @y@.
--
-- > let f k x = if x == "a" then Just ((show k) ++ ":new a") else Nothing
-- > updateWithKey f 5 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "5:new a")]
-- > updateWithKey f 7 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a")]
-- > updateWithKey f 3 (fromList [(5,"a"), (3,"b")]) == singleton 5 "a"

updateWithKey :: (Int -> a -> Maybe a) -> Int -> Map a -> Map a
updateWithKey f k t
  = case t of
      Tip -> Tip
      Bin sx kx x l r
          -> case compare k kx of
               LT -> balance kx x (updateWithKey f k l) r
               GT -> balance kx x l (updateWithKey f k r)
               EQ -> case f kx x of
                       Just x' -> Bin sx kx x' l r
                       Nothing -> glue l r

-- | /O(log n)/. Lookup and update. See also 'updateWithKey'.
-- The function returns changed value, if it is updated.
-- Returns the original key value if the map entry is deleted.
--
-- > let f k x = if x == "a" then Just ((show k) ++ ":new a") else Nothing
-- > updateLookupWithKey f 5 (fromList [(5,"a"), (3,"b")]) == (Just "5:new a", fromList [(3, "b"), (5, "5:new a")])
-- > updateLookupWithKey f 7 (fromList [(5,"a"), (3,"b")]) == (Nothing,  fromList [(3, "b"), (5, "a")])
-- > updateLookupWithKey f 3 (fromList [(5,"a"), (3,"b")]) == (Just "b", singleton 5 "a")

updateLookupWithKey :: (Int -> a -> Maybe a) -> Int -> Map a -> (Maybe a,Map a)
updateLookupWithKey f k t
  = case t of
      Tip -> (Nothing,Tip)
      Bin sx kx x l r
          -> case compare k kx of
               LT -> let (found,l') = updateLookupWithKey f k l in (found,balance kx x l' r)
               GT -> let (found,r') = updateLookupWithKey f k r in (found,balance kx x l r')
               EQ -> case f kx x of
                       Just x' -> (Just x',Bin sx kx x' l r)
                       Nothing -> (Just x,glue l r)

-- | /O(log n)/. The expression (@'alter' f k map@) alters the value @x@ at @k@, or absence thereof.
-- 'alter' can be used to insert, delete, or update a value in a 'Map'.
-- In short : @'lookup' k ('alter' f k m) = f ('lookup' k m)@.
--
-- > let f _ = Nothing
-- > alter f 7 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a")]
-- > alter f 5 (fromList [(5,"a"), (3,"b")]) == singleton 3 "b"
-- >
-- > let f _ = Just "c"
-- > alter f 7 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "a"), (7, "c")]
-- > alter f 5 (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "c")]

alter :: (Maybe a -> Maybe a) -> Int -> Map a -> Map a
alter f k t
  = case t of
      Tip -> case f Nothing of
               Nothing -> Tip
               Just x -> singleton k x
      Bin sx kx x l r
          -> case compare k kx of
               LT -> balance kx x (alter f k l) r
               GT -> balance kx x l (alter f k r)
               EQ -> case f (Just x) of
                       Just x' -> Bin sx kx x' l r
                       Nothing -> glue l r

{--------------------------------------------------------------------
  Indexing
--------------------------------------------------------------------}
-- | /O(log n)/. Return the /index/ of a key. The index is a number from
-- /0/ up to, but not including, the 'size' of the map. Calls 'error' when
-- the key is not a 'member' of the map.
--
-- > findIndex 2 (fromList [(5,"a"), (3,"b")])    Error: element is not in the map
-- > findIndex 3 (fromList [(5,"a"), (3,"b")]) == 0
-- > findIndex 5 (fromList [(5,"a"), (3,"b")]) == 1
-- > findIndex 6 (fromList [(5,"a"), (3,"b")])    Error: element is not in the map

findIndex :: Int -> Map a -> Int
findIndex k t
  = case lookupIndex k t of
      Nothing  -> error "Map.findIndex: element is not in the map"
      Just idx -> idx

-- | /O(log n)/. Lookup the /index/ of a key. The index is a number from
-- /0/ up to, but not including, the 'size' of the map.
--
-- > isJust (lookupIndex 2 (fromList [(5,"a"), (3,"b")]))   == False
-- > fromJust (lookupIndex 3 (fromList [(5,"a"), (3,"b")])) == 0
-- > fromJust (lookupIndex 5 (fromList [(5,"a"), (3,"b")])) == 1
-- > isJust (lookupIndex 6 (fromList [(5,"a"), (3,"b")]))   == False

lookupIndex :: Int -> Map a -> Maybe Int
lookupIndex k t = f 0 t
  where
    f _   Tip  = Nothing
    f idx (Bin _ kx _ l r)
      = case compare k kx of
          LT -> f idx l
          GT -> f (idx + size l + 1) r
          EQ -> Just (idx + size l)

-- | /O(log n)/. Retrieve an element by /index/. Calls 'error' when an
-- invalid index is used.
--
-- > elemAt 0 (fromList [(5,"a"), (3,"b")]) == (3,"b")
-- > elemAt 1 (fromList [(5,"a"), (3,"b")]) == (5, "a")
-- > elemAt 2 (fromList [(5,"a"), (3,"b")])    Error: index out of range

elemAt :: Int -> Map a -> (Int,a)
elemAt _ Tip = error "Map.elemAt: index out of range"
elemAt i (Bin _ kx x l r)
  = case compare i sizeL of
      LT -> elemAt i l
      GT -> elemAt (i-sizeL-1) r
      EQ -> (kx,x)
  where
    sizeL = size l

-- | /O(log n)/. Update the element at /index/. Calls 'error' when an
-- invalid index is used.
--
-- > updateAt (\ _ _ -> Just "x") 0    (fromList [(5,"a"), (3,"b")]) == fromList [(3, "x"), (5, "a")]
-- > updateAt (\ _ _ -> Just "x") 1    (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "x")]
-- > updateAt (\ _ _ -> Just "x") 2    (fromList [(5,"a"), (3,"b")])    Error: index out of range
-- > updateAt (\ _ _ -> Just "x") (-1) (fromList [(5,"a"), (3,"b")])    Error: index out of range
-- > updateAt (\_ _  -> Nothing)  0    (fromList [(5,"a"), (3,"b")]) == singleton 5 "a"
-- > updateAt (\_ _  -> Nothing)  1    (fromList [(5,"a"), (3,"b")]) == singleton 3 "b"
-- > updateAt (\_ _  -> Nothing)  2    (fromList [(5,"a"), (3,"b")])    Error: index out of range
-- > updateAt (\_ _  -> Nothing)  (-1) (fromList [(5,"a"), (3,"b")])    Error: index out of range

updateAt :: (Int -> a -> Maybe a) -> Int -> Map a -> Map a
updateAt _ _ Tip  = error "Map.updateAt: index out of range"
updateAt f i (Bin sx kx x l r)
  = case compare i sizeL of
      LT -> balance kx x (updateAt f i l) r
      GT -> balance kx x l (updateAt f (i-sizeL-1) r)
      EQ -> case f kx x of
              Just x' -> Bin sx kx x' l r
              Nothing -> glue l r
  where
    sizeL = size l

-- | /O(log n)/. Delete the element at /index/.
-- Defined as (@'deleteAt' i map = 'updateAt' (\k x -> 'Nothing') i map@).
--
-- > deleteAt 0  (fromList [(5,"a"), (3,"b")]) == singleton 5 "a"
-- > deleteAt 1  (fromList [(5,"a"), (3,"b")]) == singleton 3 "b"
-- > deleteAt 2 (fromList [(5,"a"), (3,"b")])     Error: index out of range
-- > deleteAt (-1) (fromList [(5,"a"), (3,"b")])  Error: index out of range

deleteAt :: Int -> Map a -> Map a
deleteAt i m
  = updateAt (\_ _ -> Nothing) i m


{--------------------------------------------------------------------
  Minimal, Maximal
--------------------------------------------------------------------}
-- | /O(log n)/. The minimal key of the map. Calls 'error' is the map is empty.
--
-- > findMin (fromList [(5,"a"), (3,"b")]) == (3,"b")
-- > findMin empty                            Error: empty map has no minimal element

findMin :: Map a -> (Int,a)
findMin (Bin _ kx x Tip _)  = (kx,x)
findMin (Bin _ _  _ l _)    = findMin l
findMin Tip                 = error "Map.findMin: empty map has no minimal element"

-- | /O(log n)/. The maximal key of the map. Calls 'error' is the map is empty.
--
-- > findMax (fromList [(5,"a"), (3,"b")]) == (5,"a")
-- > findMax empty                            Error: empty map has no maximal element

findMax :: Map a -> (Int,a)
findMax (Bin _ kx x _ Tip)  = (kx,x)
findMax (Bin _ _  _ _ r)    = findMax r
findMax Tip                 = error "Map.findMax: empty map has no maximal element"

-- | /O(log n)/. Delete the minimal key. Returns an empty map if the map is empty.
--
-- > deleteMin (fromList [(5,"a"), (3,"b"), (7,"c")]) == fromList [(5,"a"), (7,"c")]
-- > deleteMin empty == empty

deleteMin :: Map a -> Map a
deleteMin (Bin _ _  _ Tip r)  = r
deleteMin (Bin _ kx x l r)    = balance kx x (deleteMin l) r
deleteMin Tip                 = Tip

-- | /O(log n)/. Delete the maximal key. Returns an empty map if the map is empty.
--
-- > deleteMax (fromList [(5,"a"), (3,"b"), (7,"c")]) == fromList [(3,"b"), (5,"a")]
-- > deleteMax empty == empty

deleteMax :: Map a -> Map a
deleteMax (Bin _ _  _ l Tip)  = l
deleteMax (Bin _ kx x l r)    = balance kx x l (deleteMax r)
deleteMax Tip                 = Tip

-- | /O(log n)/. Update the value at the minimal key.
--
-- > updateMin (\ a -> Just ("X" ++ a)) (fromList [(5,"a"), (3,"b")]) == fromList [(3, "Xb"), (5, "a")]
-- > updateMin (\ _ -> Nothing)         (fromList [(5,"a"), (3,"b")]) == singleton 5 "a"

updateMin :: (a -> Maybe a) -> Map a -> Map a
updateMin f m
  = updateMinWithKey (\_ x -> f x) m

-- | /O(log n)/. Update the value at the maximal key.
--
-- > updateMax (\ a -> Just ("X" ++ a)) (fromList [(5,"a"), (3,"b")]) == fromList [(3, "b"), (5, "Xa")]
-- > updateMax (\ _ -> Nothing)         (fromList [(5,"a"), (3,"b")]) == singleton 3 "b"

updateMax :: (a -> Maybe a) -> Map a -> Map a
updateMax f m
  = updateMaxWithKey (\_ x -> f x) m


-- | /O(log n)/. Update the value at the minimal key.
--
-- > updateMinWithKey (\ k a -> Just ((show k) ++ ":" ++ a)) (fromList [(5,"a"), (3,"b")]) == fromList [(3,"3:b"), (5,"a")]
-- > updateMinWithKey (\ _ _ -> Nothing)                     (fromList [(5,"a"), (3,"b")]) == singleton 5 "a"

updateMinWithKey :: (Int -> a -> Maybe a) -> Map a -> Map a
updateMinWithKey f t
  = case t of
      Bin sx kx x Tip r  -> case f kx x of
                              Nothing -> r
                              Just x' -> Bin sx kx x' Tip r
      Bin _ kx x l r     -> balance kx x (updateMinWithKey f l) r
      Tip                -> Tip

-- | /O(log n)/. Update the value at the maximal key.
--
-- > updateMaxWithKey (\ k a -> Just ((show k) ++ ":" ++ a)) (fromList [(5,"a"), (3,"b")]) == fromList [(3,"b"), (5,"5:a")]
-- > updateMaxWithKey (\ _ _ -> Nothing)                     (fromList [(5,"a"), (3,"b")]) == singleton 3 "b"

updateMaxWithKey :: (Int -> a -> Maybe a) -> Map a -> Map a
updateMaxWithKey f t
  = case t of
      Bin sx kx x l Tip  -> case f kx x of
                              Nothing -> l
                              Just x' -> Bin sx kx x' l Tip
      Bin _ kx x l r     -> balance kx x l (updateMaxWithKey f r)
      Tip                -> Tip

-- | /O(log n)/. Retrieves the minimal (key,value) pair of the map, and
-- the map stripped of that element, or 'Nothing' if passed an empty map.
--
-- > minViewWithKey (fromList [(5,"a"), (3,"b")]) == Just ((3,"b"), singleton 5 "a")
-- > minViewWithKey empty == Nothing

minViewWithKey :: Map a -> Maybe ((Int,a), Map a)
minViewWithKey Tip = Nothing
minViewWithKey x = Just (deleteFindMin x)

-- | /O(log n)/. Retrieves the maximal (key,value) pair of the map, and
-- the map stripped of that element, or 'Nothing' if passed an empty map.
--
-- > maxViewWithKey (fromList [(5,"a"), (3,"b")]) == Just ((5,"a"), singleton 3 "b")
-- > maxViewWithKey empty == Nothing

maxViewWithKey :: Map a -> Maybe ((Int,a), Map a)
maxViewWithKey Tip = Nothing
maxViewWithKey x = Just (deleteFindMax x)

-- | /O(log n)/. Retrieves the value associated with minimal key of the
-- map, and the map stripped of that element, or 'Nothing' if passed an
-- empty map.
--
-- > minView (fromList [(5,"a"), (3,"b")]) == Just ("b", singleton 5 "a")
-- > minView empty == Nothing

minView :: Map a -> Maybe (a, Map a)
minView Tip = Nothing
minView x = Just (first snd $ deleteFindMin x)

-- | /O(log n)/. Retrieves the value associated with maximal key of the
-- map, and the map stripped of that element, or 'Nothing' if passed an
--
-- > maxView (fromList [(5,"a"), (3,"b")]) == Just ("a", singleton 3 "b")
-- > maxView empty == Nothing

maxView :: Map a -> Maybe (a, Map a)
maxView Tip = Nothing
maxView x = Just (first snd $ deleteFindMax x)

-- Update the 1st component of a tuple (special case of Control.Arrow.first)
first :: (a -> b) -> (a,c) -> (b,c)
first f (x,y) = (f x, y)

{--------------------------------------------------------------------
  Union.
--------------------------------------------------------------------}
-- | The union of a list of maps:
--   (@'unions' == 'Prelude.foldl' 'union' 'empty'@).
--
-- > unions [(fromList [(5, "a"), (3, "b")]), (fromList [(5, "A"), (7, "C")]), (fromList [(5, "A3"), (3, "B3")])]
-- >     == fromList [(3, "b"), (5, "a"), (7, "C")]
-- > unions [(fromList [(5, "A3"), (3, "B3")]), (fromList [(5, "A"), (7, "C")]), (fromList [(5, "a"), (3, "b")])]
-- >     == fromList [(3, "B3"), (5, "A3"), (7, "C")]

unions :: [Map a] -> Map a
unions ts
  = foldlStrict union empty ts

-- | The union of a list of maps, with a combining operation:
--   (@'unionsWith' f == 'Prelude.foldl' ('unionWith' f) 'empty'@).
--
-- > unionsWith (++) [(fromList [(5, "a"), (3, "b")]), (fromList [(5, "A"), (7, "C")]), (fromList [(5, "A3"), (3, "B3")])]
-- >     == fromList [(3, "bB3"), (5, "aAA3"), (7, "C")]

unionsWith :: (a->a->a) -> [Map a] -> Map a
unionsWith f ts
  = foldlStrict (unionWith f) empty ts

-- | /O(n+m)/.
-- The expression (@'union' t1 t2@) takes the left-biased union of @t1@ and @t2@.
-- It prefers @t1@ when duplicate keys are encountered,
-- i.e. (@'union' == 'unionWith' 'const'@).
-- The implementation uses the efficient /hedge-union/ algorithm.
-- Hedge-union is more efficient on (bigset \``union`\` smallset).
--
-- > union (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (7, "C")]) == fromList [(3, "b"), (5, "a"), (7, "C")]

union :: Map a -> Map a -> Map a
union Tip t2  = t2
union t1 Tip  = t1
union t1 t2 = hedgeUnionL (const LT) (const GT) t1 t2

-- left-biased hedge union
hedgeUnionL :: (Int -> Ordering) -> (Int -> Ordering)
            -> Map a -> Map a -> Map a
hedgeUnionL _     _     t1 Tip
  = t1
hedgeUnionL cmplo cmphi Tip (Bin _ kx x l r)
  = join kx x (filterGt cmplo l) (filterLt cmphi r)
hedgeUnionL cmplo cmphi (Bin _ kx x l r) t2
  = join kx x (hedgeUnionL cmplo cmpkx l (trim cmplo cmpkx t2))
              (hedgeUnionL cmpkx cmphi r (trim cmpkx cmphi t2))
  where
    cmpkx k  = compare kx k

{-
XXX unused code

-- right-biased hedge union
hedgeUnionR :: Ord a
            => (a -> Ordering) -> (a -> Ordering) -> Map a b -> Map a b
            -> Map a b
hedgeUnionR _     _     t1 Tip
  = t1
hedgeUnionR cmplo cmphi Tip (Bin _ kx x l r)
  = join kx x (filterGt cmplo l) (filterLt cmphi r)
hedgeUnionR cmplo cmphi (Bin _ kx x l r) t2
  = join kx newx (hedgeUnionR cmplo cmpkx l lt)
                 (hedgeUnionR cmpkx cmphi r gt)
  where
    cmpkx k     = compare kx k
    lt          = trim cmplo cmpkx t2
    (found,gt)  = trimLookupLo kx cmphi t2
    newx        = case found of
                    Nothing -> x
                    Just (_,y) -> y
-}

{--------------------------------------------------------------------
  Union with a combining function
--------------------------------------------------------------------}
-- | /O(n+m)/. Union with a combining function. The implementation uses the efficient /hedge-union/ algorithm.
--
-- > unionWith (++) (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (7, "C")]) == fromList [(3, "b"), (5, "aA"), (7, "C")]

unionWith :: (a -> a -> a) -> Map a -> Map a -> Map a
unionWith f m1 m2
  = unionWithKey (\_ x y -> f x y) m1 m2

-- | /O(n+m)/.
-- Union with a combining function. The implementation uses the efficient /hedge-union/ algorithm.
-- Hedge-union is more efficient on (bigset \``union`\` smallset).
--
-- > let f key left_value right_value = (show key) ++ ":" ++ left_value ++ "|" ++ right_value
-- > unionWithKey f (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (7, "C")]) == fromList [(3, "b"), (5, "5:a|A"), (7, "C")]

unionWithKey :: (Int -> a -> a -> a) -> Map a -> Map a -> Map a
unionWithKey _ Tip t2  = t2
unionWithKey _ t1 Tip  = t1
unionWithKey f t1 t2 = hedgeUnionWithKey f (const LT) (const GT) t1 t2

hedgeUnionWithKey :: (Int -> b -> b -> b)
                  -> (Int -> Ordering) -> (Int -> Ordering)
                  -> Map b -> Map b
                  -> Map b
hedgeUnionWithKey _ _     _     t1 Tip
  = t1
hedgeUnionWithKey _ cmplo cmphi Tip (Bin _ kx x l r)
  = join kx x (filterGt cmplo l) (filterLt cmphi r)
hedgeUnionWithKey f cmplo cmphi (Bin _ kx x l r) t2
  = join kx newx (hedgeUnionWithKey f cmplo cmpkx l lt)
                 (hedgeUnionWithKey f cmpkx cmphi r gt)
  where
    cmpkx k     = compare kx k
    lt          = trim cmplo cmpkx t2
    (found,gt)  = trimLookupLo kx cmphi t2
    newx        = case found of
                    Nothing -> x
                    Just (_,y) -> f kx x y

{--------------------------------------------------------------------
  Difference
--------------------------------------------------------------------}
-- | /O(n+m)/. Difference of two maps.
-- Return elements of the first map not existing in the second map.
-- The implementation uses an efficient /hedge/ algorithm comparable with /hedge-union/.
--
-- > difference (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (7, "C")]) == singleton 3 "b"

difference :: Map a -> Map b -> Map a
difference Tip _   = Tip
difference t1 Tip  = t1
difference t1 t2   = hedgeDiff (const LT) (const GT) t1 t2

hedgeDiff :: (Int -> Ordering) -> (Int -> Ordering) -> Map b -> Map c
          -> Map b
hedgeDiff _     _     Tip _
  = Tip
hedgeDiff cmplo cmphi (Bin _ kx x l r) Tip
  = join kx x (filterGt cmplo l) (filterLt cmphi r)
hedgeDiff cmplo cmphi t (Bin _ kx _ l r)
  = merge (hedgeDiff cmplo cmpkx (trim cmplo cmpkx t) l)
          (hedgeDiff cmpkx cmphi (trim cmpkx cmphi t) r)
  where
    cmpkx k = compare kx k

-- | /O(n+m)/. Difference with a combining function.
-- When two equal keys are
-- encountered, the combining function is applied to the values of these keys.
-- If it returns 'Nothing', the element is discarded (proper set difference). If
-- it returns (@'Just' y@), the element is updated with a new value @y@.
-- The implementation uses an efficient /hedge/ algorithm comparable with /hedge-union/.
--
-- > let f al ar = if al == "b" then Just (al ++ ":" ++ ar) else Nothing
-- > differenceWith f (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (3, "B"), (7, "C")])
-- >     == singleton 3 "b:B"

differenceWith :: (a -> b -> Maybe a) -> Map a -> Map b -> Map a
differenceWith f m1 m2
  = differenceWithKey (\_ x y -> f x y) m1 m2

-- | /O(n+m)/. Difference with a combining function. When two equal keys are
-- encountered, the combining function is applied to the key and both values.
-- If it returns 'Nothing', the element is discarded (proper set difference). If
-- it returns (@'Just' y@), the element is updated with a new value @y@.
-- The implementation uses an efficient /hedge/ algorithm comparable with /hedge-union/.
--
-- > let f k al ar = if al == "b" then Just ((show k) ++ ":" ++ al ++ "|" ++ ar) else Nothing
-- > differenceWithKey f (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (3, "B"), (10, "C")])
-- >     == singleton 3 "3:b|B"

differenceWithKey :: (Int -> a -> b -> Maybe a) -> Map a -> Map b -> Map a
differenceWithKey _ Tip _   = Tip
differenceWithKey _ t1 Tip  = t1
differenceWithKey f t1 t2   = hedgeDiffWithKey f (const LT) (const GT) t1 t2

hedgeDiffWithKey :: (Int -> b -> c -> Maybe b)
                 -> (Int -> Ordering) -> (Int -> Ordering)
                 -> Map b -> Map c
                 -> Map b
hedgeDiffWithKey _ _     _     Tip _
  = Tip
hedgeDiffWithKey _ cmplo cmphi (Bin _ kx x l r) Tip
  = join kx x (filterGt cmplo l) (filterLt cmphi r)
hedgeDiffWithKey f cmplo cmphi t (Bin _ kx x l r)
  = case found of
      Nothing -> merge tl tr
      Just (ky,y) ->
          case f ky y x of
            Nothing -> merge tl tr
            Just z  -> join ky z tl tr
  where
    cmpkx k     = compare kx k
    lt          = trim cmplo cmpkx t
    (found,gt)  = trimLookupLo kx cmphi t
    tl          = hedgeDiffWithKey f cmplo cmpkx lt l
    tr          = hedgeDiffWithKey f cmpkx cmphi gt r



{--------------------------------------------------------------------
  Intersection
--------------------------------------------------------------------}
-- | /O(n+m)/. Intersection of two maps.
-- Return data in the first map for the keys existing in both maps.
-- (@'intersection' m1 m2 == 'intersectionWith' 'const' m1 m2@).
--
-- > intersection (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (7, "C")]) == singleton 5 "a"

intersection :: Map a -> Map b -> Map a
intersection m1 m2
  = intersectionWithKey (\_ x _ -> x) m1 m2

-- | /O(n+m)/. Intersection with a combining function.
--
-- > intersectionWith (++) (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (7, "C")]) == singleton 5 "aA"

intersectionWith :: (a -> b -> c) -> Map a -> Map b -> Map c
intersectionWith f m1 m2
  = intersectionWithKey (\_ x y -> f x y) m1 m2

-- | /O(n+m)/. Intersection with a combining function.
-- Intersection is more efficient on (bigset \``intersection`\` smallset).
--
-- > let f k al ar = (show k) ++ ":" ++ al ++ "|" ++ ar
-- > intersectionWithKey f (fromList [(5, "a"), (3, "b")]) (fromList [(5, "A"), (7, "C")]) == singleton 5 "5:a|A"

--intersectionWithKey :: (k -> a -> b -> c) -> Map a -> Map b -> Map c
--intersectionWithKey f Tip t = Tip
--intersectionWithKey f t Tip = Tip
--intersectionWithKey f t1 t2 = intersectWithKey f t1 t2
--
--intersectWithKey f Tip t = Tip
--intersectWithKey f t Tip = Tip
--intersectWithKey f t (Bin _ kx x l r)
--  = case found of
--      Nothing -> merge tl tr
--      Just y  -> join kx (f kx y x) tl tr
--  where
--    (lt,found,gt) = splitLookup kx t
--    tl            = intersectWithKey f lt l
--    tr            = intersectWithKey f gt r

intersectionWithKey :: (Int -> a -> b -> c) -> Map a -> Map b -> Map c
intersectionWithKey _ Tip _ = Tip
intersectionWithKey _ _ Tip = Tip
intersectionWithKey f t1@(Bin s1 k1 x1 l1 r1) t2@(Bin s2 k2 x2 l2 r2) =
   if s1 >= s2 then
      let (lt,found,gt) = splitLookupWithKey k2 t1
          tl            = intersectionWithKey f lt l2
          tr            = intersectionWithKey f gt r2
      in case found of
      Just (k,x) -> join k (f k x x2) tl tr
      Nothing -> merge tl tr
   else let (lt,found,gt) = splitLookup k1 t2
            tl            = intersectionWithKey f l1 lt
            tr            = intersectionWithKey f r1 gt
      in case found of
      Just x -> join k1 (f k1 x1 x) tl tr
      Nothing -> merge tl tr



{--------------------------------------------------------------------
  Submap
--------------------------------------------------------------------}

{- | /O(n+m)/.
 The expression (@'isSubmapOfBy' f t1 t2@) returns 'True' if
 all keys in @t1@ are in tree @t2@, and when @f@ returns 'True' when
 applied to their respective values. For example, the following
 expressions are all 'True':

 > isSubmapOfBy (==) (fromList [('a',1)]) (fromList [('a',1),('b',2)])
 > isSubmapOfBy (<=) (fromList [('a',1)]) (fromList [('a',1),('b',2)])
 > isSubmapOfBy (==) (fromList [('a',1),('b',2)]) (fromList [('a',1),('b',2)])

 But the following are all 'False':

 > isSubmapOfBy (==) (fromList [('a',2)]) (fromList [('a',1),('b',2)])
 > isSubmapOfBy (<)  (fromList [('a',1)]) (fromList [('a',1),('b',2)])
 > isSubmapOfBy (==) (fromList [('a',1),('b',2)]) (fromList [('a',1)])


-}
isSubmapOfBy :: (a->b->Bool) -> Map a -> Map b -> Bool
isSubmapOfBy f t1 t2
  = (size t1 <= size t2) && (submap' f t1 t2)

submap' :: (b -> c -> Bool) -> Map b -> Map c -> Bool
submap' _ Tip _ = True
submap' _ _ Tip = False
submap' f (Bin _ kx x l r) t
  = case found of
      Nothing -> False
      Just y  -> f x y && submap' f l lt && submap' f r gt
  where
    (lt,found,gt) = splitLookup kx t

{- | /O(n+m)/. Is this a proper submap? (ie. a submap but not equal).
 The expression (@'isProperSubmapOfBy' f m1 m2@) returns 'True' when
 @m1@ and @m2@ are not equal,
 all keys in @m1@ are in @m2@, and when @f@ returns 'True' when
 applied to their respective values. For example, the following
 expressions are all 'True':

  > isProperSubmapOfBy (==) (fromList [(1,1)]) (fromList [(1,1),(2,2)])
  > isProperSubmapOfBy (<=) (fromList [(1,1)]) (fromList [(1,1),(2,2)])

 But the following are all 'False':

  > isProperSubmapOfBy (==) (fromList [(1,1),(2,2)]) (fromList [(1,1),(2,2)])
  > isProperSubmapOfBy (==) (fromList [(1,1),(2,2)]) (fromList [(1,1)])
  > isProperSubmapOfBy (<)  (fromList [(1,1)])       (fromList [(1,1),(2,2)])


-}
isProperSubmapOfBy :: (a -> b -> Bool) -> Map a -> Map b -> Bool
isProperSubmapOfBy f t1 t2
  = (size t1 < size t2) && (submap' f t1 t2)

{--------------------------------------------------------------------
  Filter and partition
--------------------------------------------------------------------}
-- | /O(n)/. Filter all values that satisfy the predicate.
--
-- > filter (> "a") (fromList [(5,"a"), (3,"b")]) == singleton 3 "b"
-- > filter (> "x") (fromList [(5,"a"), (3,"b")]) == empty
-- > filter (< "a") (fromList [(5,"a"), (3,"b")]) == empty

filter :: (a -> Bool) -> Map a -> Map a
filter p m
  = filterWithKey (\_ x -> p x) m

-- | /O(n)/. Filter all keys\/values that satisfy the predicate.
--
-- > filterWithKey (\k _ -> k > 4) (fromList [(5,"a"), (3,"b")]) == singleton 5 "a"

filterWithKey :: (Int -> a -> Bool) -> Map a -> Map a
filterWithKey _ Tip = Tip
filterWithKey p (Bin _ kx x l r)
  | p kx x    = join kx x (filterWithKey p l) (filterWithKey p r)
  | otherwise = merge (filterWithKey p l) (filterWithKey p r)


-- | /O(n)/. Partition the map according to a predicate. The first
-- map contains all elements that satisfy the predicate, the second all
-- elements that fail the predicate. See also 'split'.
--
-- > partition (> "a") (fromList [(5,"a"), (3,"b")]) == (singleton 3 "b", singleton 5 "a")
-- > partition (< "x") (fromList [(5,"a"), (3,"b")]) == (fromList [(3, "b"), (5, "a")], empty)
-- > partition (> "x") (fromList [(5,"a"), (3,"b")]) == (empty, fromList [(3, "b"), (5, "a")])

partition :: (a -> Bool) -> Map a -> (Map a,Map a)
partition p m
  = partitionWithKey (\_ x -> p x) m

-- | /O(n)/. Partition the map according to a predicate. The first
-- map contains all elements that satisfy the predicate, the second all
-- elements that fail the predicate. See also 'split'.
--
-- > partitionWithKey (\ k _ -> k > 3) (fromList [(5,"a"), (3,"b")]) == (singleton 5 "a", singleton 3 "b")
-- > partitionWithKey (\ k _ -> k < 7) (fromList [(5,"a"), (3,"b")]) == (fromList [(3, "b"), (5, "a")], empty)
-- > partitionWithKey (\ k _ -> k > 7) (fromList [(5,"a"), (3,"b")]) == (empty, fromList [(3, "b"), (5, "a")])

partitionWithKey :: (Int -> a -> Bool) -> Map a -> (Map a,Map a)
partitionWithKey _ Tip = (Tip,Tip)
partitionWithKey p (Bin _ kx x l r)
  | p kx x    = (join kx x l1 r1,merge l2 r2)
  | otherwise = (merge l1 r1,join kx x l2 r2)
  where
    (l1,l2) = partitionWithKey p l
    (r1,r2) = partitionWithKey p r

-- | /O(n)/. Map values and collect the 'Just' results.
--
-- > let f x = if x == "a" then Just "new a" else Nothing
-- > mapMaybe f (fromList [(5,"a"), (3,"b")]) == singleton 5 "new a"

mapMaybe :: (a -> Maybe b) -> Map a -> Map b
mapMaybe f m
  = mapMaybeWithKey (\_ x -> f x) m

-- | /O(n)/. Mapeys\/values and collect the 'Just' results.
--
-- > let f k _ = if k < 5 then Just ("key : " ++ (show k)) else Nothing
-- > mapMaybeWithKey f (fromList [(5,"a"), (3,"b")]) == singleton 3 "key : 3"

mapMaybeWithKey :: (Int -> a -> Maybe b) -> Map a -> Map b
mapMaybeWithKey _ Tip = Tip
mapMaybeWithKey f (Bin _ kx x l r) = case f kx x of
  Just y  -> join kx y (mapMaybeWithKey f l) (mapMaybeWithKey f r)
  Nothing -> merge (mapMaybeWithKey f l) (mapMaybeWithKey f r)

-- | /O(n)/. Map values and separate the 'Left' and 'Right' results.
--
-- > let f a = if a < "c" then Left a else Right a
-- > mapEither f (fromList [(5,"a"), (3,"b"), (1,"x"), (7,"z")])
-- >     == (fromList [(3,"b"), (5,"a")], fromList [(1,"x"), (7,"z")])
-- >
-- > mapEither (\ a -> Right a) (fromList [(5,"a"), (3,"b"), (1,"x"), (7,"z")])
-- >     == (empty, fromList [(5,"a"), (3,"b"), (1,"x"), (7,"z")])

mapEither :: (a -> Either b c) -> Map a -> (Map b, Map c)
mapEither f m
  = mapEitherWithKey (\_ x -> f x) m

-- | /O(n)/. Mapeys\/values and separate the 'Left' and 'Right' results.
--
-- > let f k a = if k < 5 then Left (k * 2) else Right (a ++ a)
-- > mapEitherWithKey f (fromList [(5,"a"), (3,"b"), (1,"x"), (7,"z")])
-- >     == (fromList [(1,2), (3,6)], fromList [(5,"aa"), (7,"zz")])
-- >
-- > mapEitherWithKey (\_ a -> Right a) (fromList [(5,"a"), (3,"b"), (1,"x"), (7,"z")])
-- >     == (empty, fromList [(1,"x"), (3,"b"), (5,"a"), (7,"z")])

mapEitherWithKey ::
  (Int -> a -> Either b c) -> Map a -> (Map b, Map c)
mapEitherWithKey _ Tip = (Tip, Tip)
mapEitherWithKey f (Bin _ kx x l r) = case f kx x of
  Left y  -> (join kx y l1 r1, merge l2 r2)
  Right z -> (merge l1 r1, join kx z l2 r2)
  where
    (l1,l2) = mapEitherWithKey f l
    (r1,r2) = mapEitherWithKey f r

{--------------------------------------------------------------------
  Mapping
--------------------------------------------------------------------}
-- | /O(n)/. Map a function over all values in the map.
--
-- > map (++ "x") (fromList [(5,"a"), (3,"b")]) == fromList [(3, "bx"), (5, "ax")]

map :: (a -> b) -> Map a -> Map b
map f m
  = mapWithKey (\_ x -> f x) m

-- | /O(n)/. Map a function over all values in the map.
--
-- > let f key x = (show key) ++ ":" ++ x
-- > mapWithKey f (fromList [(5,"a"), (3,"b")]) == fromList [(3, "3:b"), (5, "5:a")]

mapWithKey :: (Int -> a -> b) -> Map a -> Map b
mapWithKey _ Tip = Tip
mapWithKey f (Bin sx kx x l r)
  = Bin sx kx (f kx x) (mapWithKey f l) (mapWithKey f r)

-- | /O(n)/. The function 'mapAccum' threads an accumulating
-- argument through the map in ascending order of keys.
--
-- > let f a b = (a ++ b, b ++ "X")
-- > mapAccum f "Everything: " (fromList [(5,"a"), (3,"b")]) == ("Everything: ba", fromList [(3, "bX"), (5, "aX")])

mapAccum :: (a -> b -> (a,c)) -> a -> Map b -> (a,Map c)
mapAccum f a m
  = mapAccumWithKey (\a' _ x' -> f a' x') a m

-- | /O(n)/. The function 'mapAccumWithKey' threads an accumulating
-- argument through the map in ascending order of keys.
--
-- > let f a k b = (a ++ " " ++ (show k) ++ "-" ++ b, b ++ "X")
-- > mapAccumWithKey f "Everything:" (fromList [(5,"a"), (3,"b")]) == ("Everything: 3-b 5-a", fromList [(3, "bX"), (5, "aX")])

mapAccumWithKey :: (a -> Int -> b -> (a,c)) -> a -> Map b -> (a,Map c)
mapAccumWithKey f a t
  = mapAccumL f a t

-- | /O(n)/. The function 'mapAccumL' threads an accumulating
-- argument throught the map in ascending order of keys.
mapAccumL :: (a -> Int -> b -> (a,c)) -> a -> Map b -> (a,Map c)
mapAccumL f a t
  = case t of
      Tip -> (a,Tip)
      Bin sx kx x l r
          -> let (a1,l') = mapAccumL f a l
                 (a2,x') = f a1 kx x
                 (a3,r') = mapAccumL f a2 r
             in (a3,Bin sx kx x' l' r')

-- | /O(n)/. The function 'mapAccumR' threads an accumulating
-- argument through the map in descending order of keys.
mapAccumRWithKey :: (a -> Int -> b -> (a,c)) -> a -> Map b -> (a,Map c)
mapAccumRWithKey f a t
  = case t of
      Tip -> (a,Tip)
      Bin sx kx x l r
          -> let (a1,r') = mapAccumRWithKey f a r
                 (a2,x') = f a1 kx x
                 (a3,l') = mapAccumRWithKey f a2 l
             in (a3,Bin sx kx x' l' r')


-- | /O(n)/.
-- @'mapKeysMonotonic' f s == 'mapKeys' f s@, but works only when @f@
-- is strictly monotonic.
-- That is, for any values @x@ and @y@, if @x@ < @y@ then @f x@ < @f y@.
-- /The precondition is not checked./
-- Semi-formally, we have:
--
-- > and [x < y ==> f x < f y | x <- ls, y <- ls]
-- >                     ==> mapKeysMonotonic f s == mapKeys f s
-- >     where ls = keys s
--
-- This means that @f@ maps distinct original keys to distinct resulting keys.
-- This function has better performance than 'mapKeys'.
--
-- > mapKeysMonotonic (\ k -> k * 2) (fromList [(5,"a"), (3,"b")]) == fromList [(6, "b"), (10, "a")]
-- > valid (mapKeysMonotonic (\ k -> k * 2) (fromList [(5,"a"), (3,"b")])) == True
-- > valid (mapKeysMonotonic (\ _ -> 1)     (fromList [(5,"a"), (3,"b")])) == False

mapKeysMonotonic :: (Int -> Int) -> Map a -> Map a
mapKeysMonotonic _ Tip = Tip
mapKeysMonotonic f (Bin sz k x l r) =
    Bin sz (f k) x (mapKeysMonotonic f l) (mapKeysMonotonic f r)

{--------------------------------------------------------------------
  Folds
--------------------------------------------------------------------}

-- | /O(n)/. Fold the values in the map, such that
-- @'fold' f z == 'Prelude.foldr' f z . 'elems'@.
-- For example,
--
-- > elems map = fold (:) [] map
--
-- > let f a len = len + (length a)
-- > fold f 0 (fromList [(5,"a"), (3,"bbb")]) == 4

fold :: (a -> b -> b) -> b -> Map a -> b
fold f z m
  = foldWithKey (\_ x' z' -> f x' z') z m

-- | /O(n)/. Fold the keys and values in the map, such that
-- @'foldWithKey' f z == 'Prelude.foldr' ('uncurry' f) z . 'toAscList'@.
-- For example,
--
-- > keys map = foldWithKey (\k x ks -> k:ks) [] map
--
-- > let f k a result = result ++ "(" ++ (show k) ++ ":" ++ a ++ ")"
-- > foldWithKey f "Map: " (fromList [(5,"a"), (3,"b")]) == "Map: (5:a)(3:b)"
--
-- This is identical to 'foldrWithKey', and you should use that one instead of
-- this one.  This name is kept for backward compatibility.

foldWithKey :: (Int -> a -> b -> b) -> b -> Map a -> b
foldWithKey f z t
  = foldrWithKey f z t

{-
XXX unused code

-- | /O(n)/. In-order fold.
foldi :: (k -> a -> b -> b -> b) -> b -> Map a -> b
foldi _ z Tip               = z
foldi f z (Bin _ kx x l r)  = f kx x (foldi f z l) (foldi f z r)
-}

-- | /O(n)/. Post-order fold.  The function will be applied from the lowest
-- value to the highest.
foldrWithKey :: (Int -> a -> b -> b) -> b -> Map a -> b
foldrWithKey _ z Tip              = z
foldrWithKey f z (Bin _ kx x l r) =
    foldrWithKey f (f kx x (foldrWithKey f z r)) l


-- | /O(n)/. Pre-order fold.  The function will be applied from the highest
-- value to the lowest.
foldlWithKey :: (b -> Int -> a -> b) -> b -> Map a -> b
foldlWithKey _ z Tip              = z
foldlWithKey f z (Bin _ kx x l r) =
    foldlWithKey f (f (foldlWithKey f z l) kx x) r

{--------------------------------------------------------------------
  List variations
--------------------------------------------------------------------}
-- | /O(n)/.
-- Return all elements of the map in the ascending order of their keys.
--
-- > elems (fromList [(5,"a"), (3,"b")]) == ["b","a"]
-- > elems empty == []

elems :: Map a -> [a]
elems m
  = [x | (_,x) <- assocs m]

-- | /O(n)/. Return all keys of the map in ascending order.
--
-- > keys (fromList [(5,"a"), (3,"b")]) == [3,5]
-- > keys empty == []

keys  :: Map a -> [Int]
keys m
  = [k | (k,_) <- assocs m]

-- | /O(n)/. Return all key\/value pairs in the map in ascending key order.
--
-- > assocs (fromList [(5,"a"), (3,"b")]) == [(3,"b"), (5,"a")]
-- > assocs empty == []

assocs :: Map a -> [(Int,a)]
assocs m
  = toList m

{--------------------------------------------------------------------
  Lists
  use [foldlStrict] to reduce demand on the control-stack
--------------------------------------------------------------------}
-- | /O(n*log n)/. Build a map from a list of key\/value pairs. See also 'fromAscList'.
-- If the list contains more than one value for the same key, the last value
-- for the key is retained.
--
-- > fromList [] == empty
-- > fromList [(5,"a"), (3,"b"), (5, "c")] == fromList [(5,"c"), (3,"b")]
-- > fromList [(5,"c"), (3,"b"), (5, "a")] == fromList [(5,"a"), (3,"b")]

fromList :: [(Int,a)] -> Map a
fromList xs
  = foldlStrict ins empty xs
  where
    ins t (k,x) = insert k x t

-- | /O(n*log n)/. Build a map from a list of key\/value pairs with a combining function. See also 'fromAscListWith'.
--
-- > fromListWith (++) [(5,"a"), (5,"b"), (3,"b"), (3,"a"), (5,"a")] == fromList [(3, "ab"), (5, "aba")]
-- > fromListWith (++) [] == empty

fromListWith :: (a -> a -> a) -> [(Int,a)] -> Map a
fromListWith f xs
  = fromListWithKey (\_ x y -> f x y) xs

-- | /O(n*log n)/. Build a map from a list of key\/value pairs with a combining function. See also 'fromAscListWithKey'.
--
-- > let f k a1 a2 = (show k) ++ a1 ++ a2
-- > fromListWithKey f [(5,"a"), (5,"b"), (3,"b"), (3,"a"), (5,"a")] == fromList [(3, "3ab"), (5, "5a5ba")]
-- > fromListWithKey f [] == empty

fromListWithKey :: (Int -> a -> a -> a) -> [(Int,a)] -> Map a
fromListWithKey f xs
  = foldlStrict ins empty xs
  where
    ins t (k,x) = insertWithKey f k x t

-- | /O(n)/. Convert to a list of key\/value pairs.
--
-- > toList (fromList [(5,"a"), (3,"b")]) == [(3,"b"), (5,"a")]
-- > toList empty == []

toList :: Map a -> [(Int,a)]
toList t      = toAscList t

-- | /O(n)/. Convert to an ascending list.
--
-- > toAscList (fromList [(5,"a"), (3,"b")]) == [(3,"b"), (5,"a")]

toAscList :: Map a -> [(Int,a)]
toAscList t   = foldrWithKey (\k x xs -> (k,x):xs) [] t

-- | /O(n)/. Convert to a descending list.
toDescList :: Map a -> [(Int,a)]
toDescList t  = foldlWithKey (\xs k x -> (k,x):xs) [] t

{--------------------------------------------------------------------
  Building trees from ascending/descending lists can be done in linear time.

  Note that if [xs] is ascending that:
    fromAscList xs       == fromList xs
    fromAscListWith f xs == fromListWith f xs
--------------------------------------------------------------------}
-- | /O(n)/. Build a map from an ascending list in linear time.
-- /The precondition (input list is ascending) is not checked./
--
-- > fromAscList [(3,"b"), (5,"a")]          == fromList [(3, "b"), (5, "a")]
-- > fromAscList [(3,"b"), (5,"a"), (5,"b")] == fromList [(3, "b"), (5, "b")]
-- > valid (fromAscList [(3,"b"), (5,"a"), (5,"b")]) == True
-- > valid (fromAscList [(5,"a"), (3,"b"), (5,"b")]) == False

fromAscList :: [(Int,a)] -> Map a
fromAscList xs
  = fromAscListWithKey (\_ x _ -> x) xs

-- | /O(n)/. Build a map from an ascending list in linear time with a combining function for equal keys.
-- /The precondition (input list is ascending) is not checked./
--
-- > fromAscListWith (++) [(3,"b"), (5,"a"), (5,"b")] == fromList [(3, "b"), (5, "ba")]
-- > valid (fromAscListWith (++) [(3,"b"), (5,"a"), (5,"b")]) == True
-- > valid (fromAscListWith (++) [(5,"a"), (3,"b"), (5,"b")]) == False

fromAscListWith :: (a -> a -> a) -> [(Int,a)] -> Map a
fromAscListWith f xs
  = fromAscListWithKey (\_ x y -> f x y) xs

-- | /O(n)/. Build a map from an ascending list in linear time with a
-- combining function for equal keys.
-- /The precondition (input list is ascending) is not checked./
--
-- > let f k a1 a2 = (show k) ++ ":" ++ a1 ++ a2
-- > fromAscListWithKey f [(3,"b"), (5,"a"), (5,"b"), (5,"b")] == fromList [(3, "b"), (5, "5:b5:ba")]
-- > valid (fromAscListWithKey f [(3,"b"), (5,"a"), (5,"b"), (5,"b")]) == True
-- > valid (fromAscListWithKey f [(5,"a"), (3,"b"), (5,"b"), (5,"b")]) == False

fromAscListWithKey :: (Int -> a -> a -> a) -> [(Int,a)] -> Map a
fromAscListWithKey f xs
  = fromDistinctAscList (combineEq f xs)
  where
  -- [combineEq f xs] combines equal elements with function [f] in an ordered list [xs]
  combineEq _ xs'
    = case xs' of
        []     -> []
        [x]    -> [x]
        (x:xx) -> combineEq' x xx

  combineEq' z [] = [z]
  combineEq' z@(kz,zz) (x@(kx,xx):xs')
    | kx==kz    = let yy = f kx xx zz in combineEq' (kx,yy) xs'
    | otherwise = z:combineEq' x xs'

-- | The length of a list
length :: [a] -> Int
length []     = 0
length (_:xs) = 1 + length xs

-- | /O(n)/. Build a map from an ascending list of distinct elements in linear time.
-- /The precondition is not checked./
--
-- > fromDistinctAscList [(3,"b"), (5,"a")] == fromList [(3, "b"), (5, "a")]
-- > valid (fromDistinctAscList [(3,"b"), (5,"a")])          == True
-- > valid (fromDistinctAscList [(3,"b"), (5,"a"), (5,"b")]) == False

fromDistinctAscList :: [(Int,a)] -> Map a
fromDistinctAscList xs
  = build const (length xs) xs
  where
    -- 1) use continutations so that we use heap space instead of stack space.
    -- 2) special case for n==5 to build bushier trees.
    build c 0 xs'  = c Tip xs'
    build c 5 xs'  = case xs' of
                       ((k1,x1):(k2,x2):(k3,x3):(k4,x4):(k5,x5):xx)
                            -> c (bin k4 x4 (bin k2 x2 (singleton k1 x1) (singleton k3 x3)) (singleton k5 x5)) xx
                       _ -> error "fromDistinctAscList build"
    build c n xs'  = seq nr $ build (buildR nr c) nl xs'
                   where
                     nl = n `div` 2
                     nr = n - nl - 1

    buildR n c l ((k,x):ys) = build (buildB l k x c) n ys
    buildR _ _ _ []         = error "fromDistinctAscList buildR []"
    buildB l k x c r zs     = c (bin k x l r) zs



{--------------------------------------------------------------------
  Utility functions that return sub-ranges of the original
  tree. Some functions take a comparison function as argument to
  allow comparisons against infinite values. A function [cmplo k]
  should be read as [compare lo k].

  [trim cmplo cmphi t]  A tree that is either empty or where [cmplo k == LT]
                        and [cmphi k == GT] for the key [k] of the root.
  [filterGt cmp t]      A tree where for all keys [k]. [cmp k == LT]
  [filterLt cmp t]      A tree where for all keys [k]. [cmp k == GT]

  [split k t]           Returns two trees [l] and [r] where all keys
                        in [l] are <[k] and all keys in [r] are >[k].
  [splitLookup k t]     Just like [split] but also returns whether [k]
                        was found in the tree.
--------------------------------------------------------------------}

{--------------------------------------------------------------------
  [trim lo hi t] trims away all subtrees that surely contain no
  values between the range [lo] to [hi]. The returned tree is either
  empty or the key of the root is between @lo@ and @hi@.
--------------------------------------------------------------------}
trim :: (Int -> Ordering) -> (Int -> Ordering) -> Map a -> Map a
trim _     _     Tip = Tip
trim cmplo cmphi t@(Bin _ kx _ l r)
  = case cmplo kx of
      LT -> case cmphi kx of
              GT -> t
              _  -> trim cmplo cmphi l
      _  -> trim cmplo cmphi r

trimLookupLo :: Int -> (Int -> Ordering) -> Map a -> (Maybe (Int,a), Map a)
trimLookupLo _  _     Tip = (Nothing,Tip)
trimLookupLo lo cmphi t@(Bin _ kx x l r)
  = case compare lo kx of
      LT -> case cmphi kx of
              GT -> (lookupAssoc lo t, t)
              _  -> trimLookupLo lo cmphi l
      GT -> trimLookupLo lo cmphi r
      EQ -> (Just (kx,x),trim (compare lo) cmphi r)


{--------------------------------------------------------------------
  [filterGt k t] filter all keys >[k] from tree [t]
  [filterLt k t] filter all keys <[k] from tree [t]
--------------------------------------------------------------------}
filterGt :: (Int -> Ordering) -> Map a -> Map a
filterGt _   Tip = Tip
filterGt cmp (Bin _ kx x l r)
  = case cmp kx of
      LT -> join kx x (filterGt cmp l) r
      GT -> filterGt cmp r
      EQ -> r

filterLt :: (Int -> Ordering) -> Map a -> Map a
filterLt _   Tip = Tip
filterLt cmp (Bin _ kx x l r)
  = case cmp kx of
      LT -> filterLt cmp l
      GT -> join kx x l (filterLt cmp r)
      EQ -> l

{--------------------------------------------------------------------
  Split
--------------------------------------------------------------------}
-- | /O(log n)/. The expression (@'split' k map@) is a pair @(map1,map2)@ where
-- the keys in @map1@ are smaller than @k@ and the keys in @map2@ larger than @k@.
-- Any key equal to @k@ is found in neither @map1@ nor @map2@.
--
-- > split 2 (fromList [(5,"a"), (3,"b")]) == (empty, fromList [(3,"b"), (5,"a")])
-- > split 3 (fromList [(5,"a"), (3,"b")]) == (empty, singleton 5 "a")
-- > split 4 (fromList [(5,"a"), (3,"b")]) == (singleton 3 "b", singleton 5 "a")
-- > split 5 (fromList [(5,"a"), (3,"b")]) == (singleton 3 "b", empty)
-- > split 6 (fromList [(5,"a"), (3,"b")]) == (fromList [(3,"b"), (5,"a")], empty)

split :: Int -> Map a -> (Map a,Map a)
split _ Tip = (Tip,Tip)
split k (Bin _ kx x l r)
  = case compare k kx of
      LT -> let (lt,gt) = split k l in (lt,join kx x gt r)
      GT -> let (lt,gt) = split k r in (join kx x l lt,gt)
      EQ -> (l,r)

-- | /O(log n)/. The expression (@'splitLookup' k map@) splits a map just
-- like 'split' but also returns @'lookup' k map@.
--
-- > splitLookup 2 (fromList [(5,"a"), (3,"b")]) == (empty, Nothing, fromList [(3,"b"), (5,"a")])
-- > splitLookup 3 (fromList [(5,"a"), (3,"b")]) == (empty, Just "b", singleton 5 "a")
-- > splitLookup 4 (fromList [(5,"a"), (3,"b")]) == (singleton 3 "b", Nothing, singleton 5 "a")
-- > splitLookup 5 (fromList [(5,"a"), (3,"b")]) == (singleton 3 "b", Just "a", empty)
-- > splitLookup 6 (fromList [(5,"a"), (3,"b")]) == (fromList [(3,"b"), (5,"a")], Nothing, empty)

splitLookup :: Int -> Map a -> (Map a,Maybe a,Map a)
splitLookup _ Tip = (Tip,Nothing,Tip)
splitLookup k (Bin _ kx x l r)
  = case compare k kx of
      LT -> let (lt,z,gt) = splitLookup k l in (lt,z,join kx x gt r)
      GT -> let (lt,z,gt) = splitLookup k r in (join kx x l lt,z,gt)
      EQ -> (l,Just x,r)

-- | /O(log n)/.
splitLookupWithKey :: Int -> Map a -> (Map a,Maybe (Int,a),Map a)
splitLookupWithKey _ Tip = (Tip,Nothing,Tip)
splitLookupWithKey k (Bin _ kx x l r)
  = case compare k kx of
      LT -> let (lt,z,gt) = splitLookupWithKey k l in (lt,z,join kx x gt r)
      GT -> let (lt,z,gt) = splitLookupWithKey k r in (join kx x l lt,z,gt)
      EQ -> (l,Just (kx, x),r)

{-
XXX unused code

-- | /O(log n)/. Performs a 'split' but also returns whether the pivot
-- element was found in the original set.
splitMember :: k -> Map a -> (Map a,Bool,Map a)
splitMember x t = let (l,m,r) = splitLookup x t in
     (l,maybe False (const True) m,r)
-}

{--------------------------------------------------------------------
  Utility functions that maintain the balance properties of the tree.
  All constructors assume that all values in [l] < [k] and all values
  in [r] > [k], and that [l] and [r] are valid trees.

  In order of sophistication:
    [Bin sz k x l r]  The type constructor.
    [bin k x l r]     Maintains the correct size, assumes that both [l]
                      and [r] are balanced with respect to each other.
    [balance k x l r] Restores the balance and size.
                      Assumes that the original tree was balanced and
                      that [l] or [r] has changed by at most one element.
    [join k x l r]    Restores balance and size.

  Furthermore, we can construct a new tree from two trees. Both operations
  assume that all values in [l] < all values in [r] and that [l] and [r]
  are valid:
    [glue l r]        Glues [l] and [r] together. Assumes that [l] and
                      [r] are already balanced with respect to each other.
    [merge l r]       Merges two trees and restores balance.

  Note: in contrast to Adam's paper, we use (<=) comparisons instead
  of (<) comparisons in [join], [merge] and [balance].
  Quickcheck (on [difference]) showed that this was necessary in order
  to maintain the invariants. It is quite unsatisfactory that I haven't
  been able to find out why this is actually the case! Fortunately, it
  doesn't hurt to be a bit more conservative.
--------------------------------------------------------------------}

{--------------------------------------------------------------------
  Join
--------------------------------------------------------------------}
join :: Int -> a -> Map a -> Map a -> Map a
join kx x Tip r  = insertMin kx x r
join kx x l Tip  = insertMax kx x l
join kx x l@(Bin sizeL ky y ly ry) r@(Bin sizeR kz z lz rz)
  | delta*sizeL <= sizeR  = balance kz z (join kx x l lz) rz
  | delta*sizeR <= sizeL  = balance ky y ly (join kx x ry r)
  | otherwise             = bin kx x l r


-- insertMin and insertMax don't perform potentially expensive comparisons.
insertMax,insertMin :: Int -> a -> Map a -> Map a
insertMax kx x t
  = case t of
      Tip -> singleton kx x
      Bin _ ky y l r
          -> balance ky y l (insertMax kx x r)

insertMin kx x t
  = case t of
      Tip -> singleton kx x
      Bin _ ky y l r
          -> balance ky y (insertMin kx x l) r

{--------------------------------------------------------------------
  [merge l r]: merges two trees.
--------------------------------------------------------------------}
merge :: Map a -> Map a -> Map a
merge Tip r   = r
merge l Tip   = l
merge l@(Bin sizeL kx x lx rx) r@(Bin sizeR ky y ly ry)
  | delta*sizeL <= sizeR = balance ky y (merge l ly) ry
  | delta*sizeR <= sizeL = balance kx x lx (merge rx r)
  | otherwise            = glue l r

{--------------------------------------------------------------------
  [glue l r]: glues two trees together.
  Assumes that [l] and [r] are already balanced with respect to each other.
--------------------------------------------------------------------}
glue :: Map a -> Map a -> Map a
glue Tip r = r
glue l Tip = l
glue l r
  | size l > size r = let ((km,m),l') = deleteFindMax l in balance km m l' r
  | otherwise       = let ((km,m),r') = deleteFindMin r in balance km m l r'


-- | /O(log n)/. Delete and find the minimal element.
--
-- > deleteFindMin (fromList [(5,"a"), (3,"b"), (10,"c")]) == ((3,"b"), fromList[(5,"a"), (10,"c")])
-- > deleteFindMin                                            Error: can not return the minimal element of an empty map

deleteFindMin :: Map a -> ((Int,a),Map a)
deleteFindMin t
  = case t of
      Bin _ k x Tip r -> ((k,x),r)
      Bin _ k x l r   -> let (km,l') = deleteFindMin l in (km,balance k x l' r)
      Tip             -> (error "Map.deleteFindMin: can not return the minimal element of an empty map", Tip)

-- | /O(log n)/. Delete and find the maximal element.
--
-- > deleteFindMax (fromList [(5,"a"), (3,"b"), (10,"c")]) == ((10,"c"), fromList [(3,"b"), (5,"a")])
-- > deleteFindMax empty                                      Error: can not return the maximal element of an empty map

deleteFindMax :: Map a -> ((Int,a),Map a)
deleteFindMax t
  = case t of
      Bin _ k x l Tip -> ((k,x),l)
      Bin _ k x l r   -> let (km,r') = deleteFindMax r in (km,balance k x l r')
      Tip             -> (error "Map.deleteFindMax: can not return the maximal element of an empty map", Tip)


{--------------------------------------------------------------------
  [balance l x r] balances two trees with value x.
  The sizes of the trees should balance after decreasing the
  size of one of them. (a rotation).

  [delta] is the maximal relative difference between the sizes of
          two trees, it corresponds with the [w] in Adams' paper.
  [ratio] is the ratio between an outer and inner sibling of the
          heavier subtree in an unbalanced setting. It determines
          whether a double or single rotation should be performed
          to restore balance. It is correspondes with the inverse
          of $\alpha$ in Adam's article.

  Note that:
  - [delta] should be larger than 4.646 with a [ratio] of 2.
  - [delta] should be larger than 3.745 with a [ratio] of 1.534.

  - A lower [delta] leads to a more 'perfectly' balanced tree.
  - A higher [delta] performs less rebalancing.

  - Balancing is automatic for random data and a balancing
    scheme is only necessary to avoid pathological worst cases.
    Almost any choice will do, and in practice, a rather large
    [delta] may perform better than smaller one.

  Note: in contrast to Adam's paper, we use a ratio of (at least) [2]
  to decide whether a single or double rotation is needed. Allthough
  he actually proves that this ratio is needed to maintain the
  invariants, his implementation uses an invalid ratio of [1].
--------------------------------------------------------------------}
delta,ratio :: Int
delta = 5
ratio = 2

balance :: Int -> a -> Map a -> Map a -> Map a
balance k x l r
  | sizeL + sizeR <= 1    = Bin sizeX k x l r
  | sizeR >= delta*sizeL  = rotateL k x l r
  | sizeL >= delta*sizeR  = rotateR k x l r
  | otherwise             = Bin sizeX k x l r
  where
    sizeL = size l
    sizeR = size r
    sizeX = sizeL + sizeR + 1

-- rotate
rotateL :: Int -> b -> Map b -> Map b -> Map b
rotateL k x l r@(Bin _ _ _ ly ry)
  | size ly < ratio*size ry = singleL k x l r
  | otherwise               = doubleL k x l r
rotateL _ _ _ Tip = error "rotateL Tip"

rotateR :: Int -> b -> Map b -> Map b -> Map b
rotateR k x l@(Bin _ _ _ ly ry) r
  | size ry < ratio*size ly = singleR k x l r
  | otherwise               = doubleR k x l r
rotateR _ _ Tip _ = error "rotateR Tip"

-- basic rotations
singleL, singleR :: Int -> b -> Map b -> Map b -> Map b
singleL k1 x1 t1 (Bin _ k2 x2 t2 t3)  = bin k2 x2 (bin k1 x1 t1 t2) t3
singleL _ _ _ Tip = error "singleL Tip"
singleR k1 x1 (Bin _ k2 x2 t1 t2) t3  = bin k2 x2 t1 (bin k1 x1 t2 t3)
singleR _ _ Tip _ = error "singleR Tip"

doubleL, doubleR :: Int -> b -> Map b -> Map b -> Map b
doubleL k1 x1 t1 (Bin _ k2 x2 (Bin _ k3 x3 t2 t3) t4) = bin k3 x3 (bin k1 x1 t1 t2) (bin k2 x2 t3 t4)
doubleL _ _ _ _ = error "doubleL"
doubleR k1 x1 (Bin _ k2 x2 t1 (Bin _ k3 x3 t2 t3)) t4 = bin k3 x3 (bin k2 x2 t1 t2) (bin k1 x1 t3 t4)
doubleR _ _ _ _ = error "doubleR"


{--------------------------------------------------------------------
  The bin constructor maintains the size of the tree
--------------------------------------------------------------------}
bin :: Int -> a -> Map a -> Map a -> Map a
bin k x l r
  = Bin (size l + size r + 1) k x l r


{--------------------------------------------------------------------
  Assertions
--------------------------------------------------------------------}
-- | /O(n)/. Test if the internal map structure is valid.
--
-- > valid (fromAscList [(3,"b"), (5,"a")]) == True
-- > valid (fromAscList [(5,"a"), (3,"b")]) == False

valid :: Map a -> Bool
valid t
  = balanced t && ordered t && validsize t

valid_cf = valid ::: CF --> CF
  `Using` ordered_cf
  `Using` balanced_cf
  `Using` validsize_cf

ordered :: Map b -> Bool
ordered t
  = bounded (const True) (const True) t
  where
    bounded lo hi t'
      = case t' of
          Tip             -> True
          Bin _ kx _ l r  -> (lo kx) && (hi kx) && bounded lo (<kx) l && bounded (>kx) hi r

ordered_cf = ordered ::: CF --> CF

-- | Exported only for "Debug.QuickCheck"
balanced :: Map a -> Bool
balanced t
  = case t of
      Tip            -> True
      Bin _ _ _ l r  -> (size l + size r <= 1 || (size l <= delta*size r && size r <= delta*size l)) &&
                        balanced l && balanced r

balanced_cf = balanced ::: CF --> CF

validsize :: Map b -> Bool
validsize t
  = case realsize t of
        Just u -> u == size t
        Nothing -> False

realsize t'
  = case t' of
      Tip            -> Just 0
      Bin sz _ _ l r -> case (realsize l,realsize r) of
                        (Just n,Just m)  | n+m+1 == sz  -> Just sz
                        _                               -> Nothing
realsize_cf = realsize ::: CF --> CF

validsize_cf = validsize ::: CF --> CF
  `Using` realsize_cf

{--------------------------------------------------------------------
  Utilities
--------------------------------------------------------------------}
foldlStrict :: (a -> b -> a) -> a -> [b] -> a
foldlStrict f z xs
  = case xs of
      []     -> z
      (x:xx) -> let z' = f z x in seq z' (foldlStrict f z' xx)


{-
{--------------------------------------------------------------------
  Testing
--------------------------------------------------------------------}
testTree xs   = fromList [(x,"*") | x <- xs]
test1 = testTree [1..20]
test2 = testTree [30,29..10]
test3 = testTree [1,4,6,89,2323,53,43,234,5,79,12,9,24,9,8,423,8,42,4,8,9,3]

{--------------------------------------------------------------------
  QuickCheck
--------------------------------------------------------------------}
qcheck prop
  = check config prop
  where
    config = Config
      { configMaxTest = 500
      , configMaxFail = 5000
      , configSize    = \n -> (div n 2 + 3)
      , configEvery   = \n args -> let s = show n in s ++ [ '\b' | _ <- s ]
      }


{--------------------------------------------------------------------
  Arbitrary, reasonably balanced trees
--------------------------------------------------------------------}
instance (Enum k,Arbitrary a) => Arbitrary (Map a) where
  arbitrary = sized (arbtree 0 maxkey)
            where maxkey  = 10000

arbtree :: (Enum k,Arbitrary a) => Int -> Int -> Int -> Gen (Map a)
arbtree lo hi n
  | n <= 0        = return Tip
  | lo >= hi      = return Tip
  | otherwise     = do{ x  <- arbitrary
                      ; i  <- choose (lo,hi)
                      ; m  <- choose (1,30)
                      ; let (ml,mr)  | m==(1::Int)= (1,2)
                                     | m==2       = (2,1)
                                     | m==3       = (1,1)
                                     | otherwise  = (2,2)
                      ; l  <- arbtree lo (i-1) (n `div` ml)
                      ; r  <- arbtree (i+1) hi (n `div` mr)
                      ; return (bin (toEnum i) x l r)
                      }


{--------------------------------------------------------------------
  Valid tree's
--------------------------------------------------------------------}
forValid :: (Show k,Enum k,Show a,Arbitrary a,Testable b) => (Map a -> b) -> Property
forValid f
  = forAll arbitrary $ \t ->
--    classify (balanced t) "balanced" $
    classify (size t == 0) "empty" $
    classify (size t > 0  && size t <= 10) "small" $
    classify (size t > 10 && size t <= 64) "medium" $
    classify (size t > 64) "large" $
    balanced t ==> f t

forValidIntTree :: Testable a => (Map Int Int -> a) -> Property
forValidIntTree f
  = forValid f

forValidUnitTree :: Testable a => (Map Int () -> a) -> Property
forValidUnitTree f
  = forValid f


prop_Valid
  = forValidUnitTree $ \t -> valid t

{--------------------------------------------------------------------
  Single, Insert, Delete
--------------------------------------------------------------------}
prop_Single :: Int -> Int -> Bool
prop_Single k x
  = (insert k x empty == singleton k x)

prop_InsertValid :: Int -> Property
prop_InsertValid k
  = forValidUnitTree $ \t -> valid (insert k () t)

prop_InsertDelete :: Int -> Map Int () -> Property
prop_InsertDelete k t
  = (lookup k t == Nothing) ==> delete k (insert k () t) == t

prop_DeleteValid :: Int -> Property
prop_DeleteValid k
  = forValidUnitTree $ \t ->
    valid (delete k (insert k () t))

{--------------------------------------------------------------------
  Balance
--------------------------------------------------------------------}
prop_Join :: Int -> Property
prop_Join k
  = forValidUnitTree $ \t ->
    let (l,r) = split k t
    in valid (join k () l r)

prop_Merge :: Int -> Property
prop_Merge k
  = forValidUnitTree $ \t ->
    let (l,r) = split k t
    in valid (merge l r)


{--------------------------------------------------------------------
  Union
--------------------------------------------------------------------}
prop_UnionValid :: Property
prop_UnionValid
  = forValidUnitTree $ \t1 ->
    forValidUnitTree $ \t2 ->
    valid (union t1 t2)

prop_UnionInsert :: Int -> Int -> Map Int Int -> Bool
prop_UnionInsert k x t
  = union (singleton k x) t == insert k x t

prop_UnionAssoc :: Map Int Int -> Map Int Int -> Map Int Int -> Bool
prop_UnionAssoc t1 t2 t3
  = union t1 (union t2 t3) == union (union t1 t2) t3

prop_UnionComm :: Map Int Int -> Map Int Int -> Bool
prop_UnionComm t1 t2
  = (union t1 t2 == unionWith (\x y -> y) t2 t1)

prop_UnionWithValid
  = forValidIntTree $ \t1 ->
    forValidIntTree $ \t2 ->
    valid (unionWithKey (\k x y -> x+y) t1 t2)

prop_UnionWith :: [(Int,Int)] -> [(Int,Int)] -> Bool
prop_UnionWith xs ys
  = sum (elems (unionWith (+) (fromListWith (+) xs) (fromListWith (+) ys)))
    == (sum (Prelude.map snd xs) + sum (Prelude.map snd ys))

prop_DiffValid
  = forValidUnitTree $ \t1 ->
    forValidUnitTree $ \t2 ->
    valid (difference t1 t2)

prop_Diff :: [(Int,Int)] -> [(Int,Int)] -> Bool
prop_Diff xs ys
  =  List.sort (keys (difference (fromListWith (+) xs) (fromListWith (+) ys)))
    == List.sort ((List.\\) (nub (Prelude.map fst xs))  (nub (Prelude.map fst ys)))

prop_IntValid
  = forValidUnitTree $ \t1 ->
    forValidUnitTree $ \t2 ->
    valid (intersection t1 t2)

prop_Int :: [(Int,Int)] -> [(Int,Int)] -> Bool
prop_Int xs ys
  =  List.sort (keys (intersection (fromListWith (+) xs) (fromListWith (+) ys)))
    == List.sort (nub ((List.intersect) (Prelude.map fst xs)  (Prelude.map fst ys)))

{--------------------------------------------------------------------
  Lists
--------------------------------------------------------------------}
prop_Ordered
  = forAll (choose (5,100)) $ \n ->
    let xs = [(x,()) | x <- [0..n::Int]]
    in fromAscList xs == fromList xs

prop_List :: [Int] -> Bool
prop_List xs
  = (sort (nub xs) == [x | (x,()) <- toList (fromList [(x,()) | x <- xs])])
-}

