{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}

module Text.Greek.Xml.Event where

import Prelude hiding ((*), (+))
import Conduit
import Control.Lens
import Data.Char
import Data.Text (Text)
import Text.Greek.Source.FileReference
import Text.Greek.Utility
import Text.Greek.Xml.Common
import qualified Data.Conduit.Attoparsec as X
import qualified Data.Text as T
import qualified Data.XML.Types as X
import qualified Text.XML.Stream.Parse as X

xmlNamespace :: Text
xmlNamespace = "http://www.w3.org/XML/1998/namespace"

xmlNamespacePrefix :: Text
xmlNamespacePrefix = "xml"

readEventsConduit :: FilePath -> IO [Maybe X.PositionRange * X.Event]
readEventsConduit p = runResourceT $ sourceFile p =$= X.parseBytesPos X.def $$ sinkList

toFileReference :: FilePath -> X.PositionRange -> FileReference
toFileReference p (X.PositionRange (X.Position startLine startColumn) (X.Position endLine endColumn))
  = FileReference (Path p) (LineReference (Line startLine) (Column startColumn)) (LineReference (Line endLine) (Column endColumn))

tryDropBeginDocument :: [Maybe X.PositionRange * X.Event] -> [XmlInternalError] + [Maybe X.PositionRange * X.Event]
tryDropBeginDocument [] = Left [XmlInternalErrorEmptyEvents]
tryDropBeginDocument (x : xs) = case x of
  (_, X.EventBeginDocument) -> Right xs
  _ -> Left . pure $ XmlInternalErrorExpectedBeginDocument x

tryDropEndDocument :: [Maybe X.PositionRange * X.Event] -> [XmlInternalError] + [Maybe X.PositionRange * X.Event]
tryDropEndDocument [] = Left [XmlInternalErrorEmptyEvents]
tryDropEndDocument (x : xs) = case x of
  (_, X.EventEndDocument) -> Right xs
  _ -> Left . pure $ XmlInternalErrorExpectedEndDocument x

tryConvertPosition :: FilePath -> Maybe X.PositionRange * X.Event -> XmlInternalError + (FileReference * X.Event)
tryConvertPosition p (Just r, e) = Right (toFileReference p r, e)
tryConvertPosition _ x = Left $ XmlInternalErrorUnexpectedEmptyPositionRange x

tryConvertPositions :: FilePath -> [Maybe X.PositionRange * X.Event] -> [XmlInternalError] + [FileReference * X.Event]
tryConvertPositions p = splitMap (tryConvertPosition p)

dropComment :: (FileReference * X.Event) -> [FileReference * X.Event] -> [FileReference * X.Event]
dropComment (_, X.EventComment _) xs = xs
dropComment x xs = x : xs

dropComments :: [FileReference * X.Event] -> [FileReference * X.Event]
dropComments = foldr dropComment []

type XmlAttribute = X.Name * [X.Content]
type BasicEvent = BasicEventFull X.Name X.Name X.Content [XmlAttribute]
data BasicEventFull be ee c a
  = BasicEventBeginElement be a
  | BasicEventEndElement ee
  | BasicEventContent c
  deriving (Show)
makePrisms ''BasicEventFull

toBasicEvent :: X.Event -> X.Event + BasicEvent
toBasicEvent (X.EventBeginElement n as) = Right (BasicEventBeginElement n as)
toBasicEvent (X.EventEndElement n) = Right (BasicEventEndElement n)
toBasicEvent (X.EventContent c) = Right (BasicEventContent c)
toBasicEvent x = Left x

toBasicEvents :: [FileReference * X.Event] -> [XmlError] + [FileReference * BasicEvent]
toBasicEvents = splitMap (tryOver _2 toBasicEvent (errorContext XmlErrorNonBasicEvent _1))

readEvents :: FilePath -> IO ([XmlInternalError] + [FileReference * X.Event])
readEvents p = fmap (xmlInternalTransform p) . readEventsConduit $ p

xmlInternalTransform :: FilePath -> [Maybe X.PositionRange * X.Event] -> [XmlInternalError] + [FileReference * X.Event]
xmlInternalTransform p x = return x
  >>= tryDropBeginDocument
  >>. reverse
  >>= tryDropEndDocument
  >>. reverse
  >>= tryConvertPositions p

readBasicEvents :: FilePath -> IO ([XmlError] + [FileReference * BasicEvent])
readBasicEvents p = fmap transformBasicEvents . readEvents $ p

transformBasicEvents :: [XmlInternalError] + [FileReference * X.Event] -> [XmlError] + [FileReference * BasicEvent]
transformBasicEvents xs = liftErrors XmlErrorInternal xs
  >>. dropComments
  >>. trimContent _2
  >>= toBasicEvents

trimContent :: Getter s X.Event -> [s] -> [s]
trimContent g = foldr (trimContentItem g) []

trimContentItem :: Getter s X.Event -> s -> [s] -> [s]
trimContentItem g x xs
  | x1 : x2 : xs' <- xs
  , X.EventBeginElement _ _ <- view g x
  , X.EventContent (X.ContentText t) <- view g x1
  , X.EventBeginElement _ _ <- view g x2
  , T.all isSpace t
  = x : x2 : xs'

  | x1 : x2 : xs' <- xs
  , X.EventEndElement _ <- view g x
  , X.EventContent (X.ContentText t) <- view g x1
  , X.EventEndElement _ <- view g x2
  , T.all isSpace t
  = x : x2 : xs'

  | x1 : x2 : xs' <- xs
  , X.EventEndElement _ <- view g x
  , X.EventContent (X.ContentText t) <- view g x1
  , X.EventBeginElement _ _ <- view g x2
  , T.all isSpace t
  = x : x2 : xs'

  | otherwise
  = x : xs
