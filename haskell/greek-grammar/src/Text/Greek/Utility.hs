{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Text.Greek.Utility where

import Prelude hiding ((*), (+), getLine)
import Control.Lens
import Data.String
import Data.Tuple
import Data.Map (Map)
import qualified Data.Map as M

type a + b = Either a b
infixr 6 +

type a * b = (a, b)
infixr 7 *

(*) :: a -> b -> a * b
(*) = (,)

addSplit :: a + b -> [a] + [b] -> [a] + [b]
addSplit (Left  a)   (Left  as') = Left (a : as')
addSplit (Left  a)   (Right _  ) = Left [a]
addSplit (Right _) e@(Left  _  ) = e
addSplit (Right b)   (Right bs ) = Right (b : bs)

split :: [a + b] -> [a] + [b]
split = foldr addSplit (Right [])


sum1 :: a1 -> a1 + a2
sum1 = Left
sum2 :: a2 -> a1 + a2 + a3
sum2 = Right . sum1
sum3 :: a3 -> a1 + a2 + a3 + a4
sum3 = Right . sum2
sum4 :: a4 -> a1 + a2 + a3 + a4 + a5
sum4 = Right . sum3
sum5 :: a5 -> a1 + a2 + a3 + a4 + a5 + a6
sum5 = Right . sum4
sum6 :: a6 -> a1 + a2 + a3 + a4 + a5 + a6 + a7
sum6 = Right . sum5
sum7 :: a7 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8
sum7 = Right . sum6
sum8 :: a8 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9
sum8 = Right . sum7
sum9 :: a9 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10
sum9 = Right . sum8
sum10 :: a10 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11
sum10 = Right . sum9

sum2e :: a2 -> a1 + a2
sum2e = Right
sum3e :: a3 -> a1 + a2 + a3
sum3e = Right . sum2e
sum4e :: a4 -> a1 + a2 + a3 + a4
sum4e = Right . sum3e
sum5e :: a5 -> a1 + a2 + a3 + a4 + a5
sum5e = Right . sum4e
sum6e :: a6 -> a1 + a2 + a3 + a4 + a5 + a6
sum6e = Right . sum5e
sum7e :: a7 -> a1 + a2 + a3 + a4 + a5 + a6 + a7
sum7e = Right . sum6e
sum8e :: a8 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8
sum8e = Right . sum7e
sum9e :: a9 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9
sum9e = Right . sum8e
sum10e :: a10 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10
sum10e = Right . sum9e
sum11e :: a11 -> a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10 + a11
sum11e = Right . sum10e


prism1 :: Prism (a1 + a2) (a1' + a2) a1 a1'
prism1 = _Left
prism2 :: Prism (a1 + a2 + a3) (a1 + a2' + a3) a2 a2'
prism2 = _Right . prism1
prism3 :: Prism (a1 + a2 + a3 + a4) (a1 + a2 + a3' + a4) a3 a3'
prism3 = _Right . prism2
prism4 :: Prism (a1 + a2 + a3 + a4 + a5) (a1 + a2 + a3 + a4' + a5) a4 a4'
prism4 = _Right . prism3

prism2e :: Prism (a1 + a2) (a1 + a2') a2 a2'
prism2e = _Right
prism3e :: Prism (a1 + a2 + a3) (a1 + a2 + a3') a3 a3'
prism3e = _Right . prism2e
prism4e :: Prism (a1 + a2 + a3 + a4) (a1 + a2 + a3 + a4') a4 a4'
prism4e = _Right . prism3e

get2e :: a1 + a2 -> a2 + a1
get2e (Left a1) = Right a1
get2e (Right a2) = Left a2

get3e :: a1 + a2 + a3 -> a3 + a1 + a2
get3e = get2 . over _Right get2e
get4e :: a1 + a2 + a3 + a4 -> a4 + a1 + a2 + a3
get4e = get2 . over _Right get3e

shiftLeftSum :: a + (b + c) -> (a + b) + c
shiftLeftSum (Left a) = Left . Left $ a
shiftLeftSum (Right (Left b)) = Left . Right $ b
shiftLeftSum (Right (Right c)) = Right c

shiftLeftProduct :: a * (b * c) -> (a * b) * c
shiftLeftProduct (a, (b, c)) = (a * b) * c

get2 :: a1 + a2 + a3 -> a2 + a1 + a3
get2 (Left a1) = Right . Left $ a1
get2 (Right (Left a2)) = Left a2
get2 (Right (Right a3)) = Right . Right $ a3

get3 :: a1 + a2 + a3 + a4 -> a3 + a1 + a2 + a4
get3 = get2 . over _Right get2
get4 :: a1 + a2 + a3 + a4 + a5 -> a4 + a1 + a2 + a3 + a5
get4 = get2 . over _Right get3



tryDrop1 :: (a1 -> e) -> a1 + a2 -> e + a2
tryDrop1 = over prism1
tryDrop2 :: (a2 -> e) -> a1 + a2 + a3 -> e + a1 + a3
tryDrop2 f = get2 . over prism2 f
tryDrop3 :: (a3 -> e) -> a1 + a2 + a3 + a4 -> e + a1 + a2 + a4
tryDrop3 f = get3 . over prism3 f
tryDrop4 :: (a4 -> e) -> a1 + a2 + a3 + a4 + a5 -> e + a1 + a2 + a3 + a5
tryDrop4 f = get4 . over prism4 f

tryDrop2e :: (a2 -> e) -> a1 + a2 -> e + a1
tryDrop2e f = get2e . over prism2e f
tryDrop3e :: (a3 -> e) -> a1 + a2 + a3 -> e + a1 + a2
tryDrop3e f = get3e . over prism3e f
tryDrop4e :: (a4 -> e) -> a1 + a2 + a3 + a4 -> e + a1 + a2 + a3
tryDrop4e f = get4e . over prism4e f


only1 :: (a2 -> e) -> a1 + a2 -> e + a1
only1 f = tryDrop1 f . get2e

class Handler e a where
  handle :: a -> e



newtype ErrorMessage = ErrorMessage { getErrorMessage :: String } deriving (Show)

concatErrors :: [ErrorMessage] -> ErrorMessage
concatErrors = ErrorMessage . concat . fmap getErrorMessage

instance IsString ErrorMessage where
  fromString = ErrorMessage

distributeProductRight :: a * (b + c) -> (a * b) + (a * c)
distributeProductRight (a, Left  b) = Left  (a * b)
distributeProductRight (a, Right c) = Right (a * c)

distributeProductLeft :: (a + b) * c -> (a * c) + (b * c)
distributeProductLeft = over _Right swap . over _Left swap . distributeProductRight . swap

singleErrorContext :: (a * e) + b -> (a * [e]) + b
singleErrorContext = _Left %~ (_2 %~ pure)

(>.) :: (a -> b) -> (b -> c) -> (a -> c)
(>.) = flip (.)
infixr 9 >.

(>>.) :: forall a b m. Functor m => m a -> (a -> b) -> m b
(>>.) = flip fmap
infixl 1 >>.


instance (Handler e a) => Handler [e] a where
  handle = pure . handle
instance (Show a) => Handler ErrorMessage a where
  handle = fromString . show


constHandle :: (Handler e c) => ((a1 -> e) -> a -> e + a2) -> c -> a -> e + a2
constHandle f = f . const . handle

tryOver
  ::   (c -> r  -> b)
  -> ((b2 -> r) -> c)
  -> r
  -> b
tryOver s p x = s (p . const $ x) x

partialMap
  :: ((a -> s + a2) -> s -> s + t)
  -> ((a1 -> s) -> a -> s + a2)
  -> [s]
  -> [s] + [t]
partialMap s p = split . fmap (tryOver s p)

handleMap :: (Handler e s)
  => ((a -> s + a2) -> s -> s + t)
  -> ((a1 -> s) -> a -> s + a2)
  -> [s]
  -> [e] + [t]
handleMap s p = (_Left . each %~ handle) . partialMap s p



removePrefixWith :: Eq b => ([a] -> e) -> (a -> b) -> [b] -> [a] -> e + [a]
removePrefixWith e f m as
  | fmap f target == m = Right $ drop matchLength as
  | otherwise          = Left $ e target
  where
    matchLength = length m
    target = take matchLength as

removeSuffixWith :: Eq b => ([a] -> e) -> (a -> b) -> [b] -> [a] -> e + [a]
removeSuffixWith e f m as
  | fmap f reverseTarget == reverse m = Right . reverse . drop matchLength $ reverseList
  | otherwise                         = Left . e . reverse $ reverseTarget
  where
    matchLength = length m
    reverseTarget = take matchLength reverseList
    reverseList = reverse as

maybeToEither :: a -> Maybe b -> a + b
maybeToEither a Nothing = Left a
maybeToEither _ (Just b) = Right b


consValue :: Ord b => a -> b -> Map b [a] -> Map b [a]
consValue a b m = case M.lookup b m of
  Just as -> M.insert b (a : as) m
  Nothing -> M.insert b [a] m

mapGroupBy :: forall a b. (Ord b) => (a -> b) -> [a] -> Map b [a]
mapGroupBy f = foldr g M.empty where
  g :: a -> Map b [a] -> Map b [a]
  g a = consValue a (f a)

query :: (Ord b) => (a -> b) -> [a] -> [b * [a]]
query f = M.toList . mapGroupBy f

partialMapGroupBy :: forall a b e. (Ord b) => (a -> e + b) -> [a] -> [a] * Map b [a]
partialMapGroupBy f = foldr g ([] * M.empty) where
  g :: a -> [a] * Map b [a] -> [a] * Map b [a]
  g a x = case f a of
    Left _ -> x & _1 %~ (a :)
    Right b -> x & _2 %~ consValue a b

partialQuery :: (Ord b) => (a -> e + b) -> [a] -> [a] * [b * [a]]
partialQuery f = (_2 %~ M.toList) . partialMapGroupBy f

choose :: forall a b e. (a -> e + b) -> [a] -> [b]
choose f = foldr g [] where
  g :: a -> [b] -> [b]
  g a bs = case f a of
    Left _ -> bs
    Right b -> b : bs