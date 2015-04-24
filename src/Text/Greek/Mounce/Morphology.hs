{-# LANGUAGE DeriveDataTypeable #-}

module Text.Greek.Mounce.Morphology where

import Data.Data

data NounCaseEndings = NounCaseEndings
  { nomSg :: String
  , nomPl :: String
  , genSg :: String
  , genPl :: String
  , datSg :: String
  , datPl :: String
  , accSg :: String
  , accPl :: String
  }
  deriving (Data, Typeable, Show, Eq)

data Noun = Noun
  { nounCategory :: String
  , nounDefinition :: String
  , nounCaseEndings :: NounCaseEndings
  }
  deriving (Show, Eq)