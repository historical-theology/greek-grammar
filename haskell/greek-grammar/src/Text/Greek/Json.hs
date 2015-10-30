{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleInstances #-}

module Text.Greek.Json where

import Prelude hiding (Word)
import Data.Aeson ((.=))
import Data.Map (Map)
import Data.Text (Text)
import GHC.Generics
import Text.Greek.FileReference
import Text.Greek.Xml.Common
import System.FilePath
import qualified Control.Lens as Lens
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Char as Char
import qualified Data.Foldable as Foldable
import qualified Data.List as List
import qualified Data.Map as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.Lazy as Lazy
import qualified Data.Text.Format as Format
import qualified Text.Greek.Script.Elision as Elision
import qualified Text.Greek.Paths as Path
import qualified Text.Greek.Source.All as All
import qualified Text.Greek.Script.Unicode as Unicode
import qualified Text.Greek.Script.Word as Word

data Data = Data
  { properties :: [Property]
  , instance0 :: Instance
  , works :: [Work]
  }

data Index = Index
  { indexProperties :: [Property]
  } deriving (Generic, Show)
instance Aeson.ToJSON Index

data Instance = Instance
  { instanceName :: Text
  , instanceProperties :: [Text]
  , instanceValues :: [[Int]]
  } deriving (Generic, Show)
instance Aeson.ToJSON Instance

data Property = Property
  { propertyName :: Text
  , propertyValues :: [Text]
  } deriving (Generic, Show)
instance Aeson.ToJSON Property

data Kind a = Kind
  { kindName :: Text
  , kindValue :: a
  } deriving (Generic, Show)
instance Aeson.ToJSON a => Aeson.ToJSON (Kind a)

data Word = Word
  { wordText :: Text
  , wordProperties :: [Text]
  } deriving (Show)
instance Aeson.ToJSON Word where toJSON (Word t p) = Aeson.object ["t" .= t, "p" .= p]

data WordGroup = WordGroup
  { wordGroupName :: Text
  , wordGroupWords :: [[Int]]
  } deriving (Generic, Show)
instance Aeson.ToJSON WordGroup

data Work = Work
  { workSource :: Text
  , workTitle :: Text
  , workWords :: [Word]
  , workWordGroups :: [WordGroup]
  } deriving (Generic, Show)
instance Aeson.ToJSON Work

go :: IO ()
go = All.loadAll >>= handleResult dumpJson . Lens.over Lens._Right getData . process

process
  :: Either [XmlError] [All.Work [Word.Basic (Text, FileReference)]]
  -> Either String     [All.Work [Word.Basic [(Unicode.Composed, FileCharReference)]]]
process x
  =   showError x
  >>= showError . toStage0Hierarchy

getData :: [All.Work [Word.Basic [(Unicode.Composed, FileCharReference)]]] -> Data
getData xs = Data stage0Properties stage0Instance stage0Works
  where
    flatStage0 = flattenStage0 xs
    (stage0Instance, stage0Properties) = makeStage0Instance flatStage0
    stage0Works = fmap makeWork xs
    makeWork (All.Work s t c) = Work (titleWorkSource s) (titleWorkTitle t) (fmap (\(_,_,w) -> w) iws) [ps]
      where
        ps = paragraphs iws
        iws = indexedWords c
    paragraphs = WordGroup "Paragraph" . (fmap . fmap) fst . List.groupBy (\(_,p1) (_,p2) -> p1 == p2) . fmap (\(i,p,_) -> (i,p))
    indexedWords = fmap (uncurry makeWord) . zip [0..]
    makeWord i w@(Word.Basic s _ p) = (i, p, Word (titleStage0Word . getStageWord $ s) (getWordProperties w))

getWordProperties :: Word.Basic [(Unicode.Composed, FileCharReference)] -> [Text]
getWordProperties (Word.Basic s e _) = concat
  [ getElisionProperty e
  , unicodeComposedProperty . fmap fst $ s
  , locationProperty . fmap snd $ s
  ]
  where
    locationProperty ((FileCharReference (Path p) (LineReference (Line l) (Column c))) : _) =
      [ Lazy.toStrict $ Format.format "Line:Col {}:{}" (l, c)
      , Text.pack p
      ]
    locationProperty [] = []

    unicodeComposedProperty = pure . Text.intercalate ", " . fmap titleUnicodeComposed

getElisionProperty :: Maybe (Elision.ElisionChar, FileCharReference) -> [Text]
getElisionProperty (Just (Elision.ElisionChar c, r)) = [Lazy.toStrict $ Format.format "Elision: {} {}" (formatUnicodeCodePoint c, titleFileCharReference r)]
getElisionProperty _ = []

handleResult :: (a -> IO ()) -> Either String a -> IO ()
handleResult _ (Left e) = putStrLn e
handleResult f (Right a) = f a

dumpJson :: Data -> IO ()
dumpJson (Data ps i0 ws) = do
  _ <- write "index.json" $ Kind "index" $ Index ps
  _ <- write "stage0.json" $ Kind "stage0" i0
  _ <- write "works.json" $ Kind "works" ws
  return ()
  where
    write n = BL.writeFile (Path.pagesData </> n) . Aeson.encode

showError :: Show a => Either a b -> Either String b
showError = Lens.over Lens._Left show


newtype Stage0Word = Stage0Word [Unicode.Composed] deriving (Eq, Ord, Show)
type Stage0 = (All.WorkSource, All.WorkTitle, Stage0Word, FileCharReference, Unicode.Composed)

toStage0Hierarchy
  ::  [All.Work [Word.Basic (Text, FileReference)]]
  -> Either Unicode.Error
      [All.Work [Word.Basic [(Unicode.Composed, FileCharReference)]]]
toStage0Hierarchy = (traverse . All.workContent . traverse . Word.basicSurface) (uncurry Unicode.splitText)

flattenStage0
  :: [All.Work [Word.Basic [(Unicode.Composed, FileCharReference)]]]
  -> [Stage0]
flattenStage0 = concatMap flattenWork
  where
    flattenWork :: All.Work [Word.Basic [(Unicode.Composed, FileCharReference)]] -> [Stage0]
    flattenWork (All.Work source title content) = fmap (\(w, r, c) -> (source, title, w, r, c)) $ concatMap flattenWord content
  
    flattenWord :: Word.Basic [(Unicode.Composed, FileCharReference)] -> [(Stage0Word, FileCharReference, Unicode.Composed)]
    flattenWord (Word.Basic surface _ _) = fmap (\(c, r) -> (stageWord, r, c)) surface
      where
        stageWord = getStageWord surface

getStageWord :: [(Unicode.Composed, FileCharReference)] -> Stage0Word
getStageWord = Stage0Word . fmap fst

makeValueMap :: Ord a => [a] -> Map a Int
makeValueMap xs = Map.fromList indexedList
  where
    uniqueValues = Set.toAscList . Set.fromList $ xs
    indexedList = zip uniqueValues [0..]

makeStage0Instance :: [Stage0] -> (Instance, [Property])
makeStage0Instance ss = (stage0Instance, stage0Properties)
  where
    workSourceMap        = makeValueMap $ fmap (\(x,_,_,_,_) -> x) ss
    workTitleMap         = makeValueMap $ fmap (\(_,x,_,_,_) -> x) ss
    stage0WordMap        = makeValueMap $ fmap (\(_,_,x,_,_) -> x) ss
    fileCharReferenceMap = makeValueMap $ fmap (\(_,_,_,x,_) -> x) ss
    unicodeComposedMap   = makeValueMap $ fmap (\(_,_,_,_,x) -> x) ss

    stage0Instance = Instance "Stage0"
      [ workSourceName
      , workTitleName
      , stage0WordName
      , fileCharReferenceName
      , unicodeComposedName
      ]
      (concat . Foldable.toList $ maybeInstanceValues)

    stage0Properties = [workSourceProperty, workTitleProperty, stage0WordProperty, fileCharReferenceProperty, unicodeComposedProperty]

    workSourceProperty = makeProperty workSourceName titleWorkSource workSourceMap
    workTitleProperty = makeProperty workTitleName titleWorkTitle workTitleMap
    stage0WordProperty = makeProperty stage0WordName titleStage0Word stage0WordMap
    fileCharReferenceProperty = makeProperty fileCharReferenceName titleFileCharReference fileCharReferenceMap
    unicodeComposedProperty = makeProperty unicodeComposedName titleUnicodeComposed unicodeComposedMap

    maybeInstanceValues :: Maybe [[Int]]
    maybeInstanceValues = traverse makeInstanceValue ss

    makeInstanceValue :: Stage0 -> Maybe [Int]
    makeInstanceValue (a, b, c, d, e) = sequence
      [ Map.lookup a workSourceMap
      , Map.lookup b workTitleMap
      , Map.lookup c stage0WordMap
      , Map.lookup d fileCharReferenceMap
      , Map.lookup e unicodeComposedMap
      ]

makeProperty :: Ord a => Text -> (a -> Text) -> Map a Int -> Property
makeProperty t f = Property t . fmap f . fmap fst . Map.toAscList

workSourceName :: Text
workSourceName = "WorkSource"

workTitleName :: Text
workTitleName = "WorkTitle"

stage0WordName :: Text
stage0WordName = "Stage0Word"

fileCharReferenceName :: Text
fileCharReferenceName = "FileLocation"

unicodeComposedName :: Text
unicodeComposedName = "UnicodeComposed"

titleWorkSource :: All.WorkSource -> Text
titleWorkSource = Text.pack . show

titleWorkTitle :: All.WorkTitle -> Text
titleWorkTitle (All.WorkTitle t) = t

titleStage0Word :: Stage0Word -> Text
titleStage0Word (Stage0Word cs) = Text.pack . fmap (\(Unicode.Composed c) -> c) $ cs

titleFileCharReference :: FileCharReference -> Text
titleFileCharReference (FileCharReference (Path p) (LineReference (Line l) (Column c))) = Lazy.toStrict $ Format.format "{}:{}:{}" (p, l, c)

titleUnicodeComposed :: Unicode.Composed -> Text
titleUnicodeComposed (Unicode.Composed c) = Lazy.toStrict $ Format.format "{} {}" (formatUnicodeCodePoint c, c)

formatUnicodeCodePoint :: Char -> Text
formatUnicodeCodePoint c = Lazy.toStrict $ Format.format "U+{}" (Format.Only . Format.left 4 '0' . Format.hex . Char.ord $ c)
